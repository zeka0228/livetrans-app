import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:record/record.dart';

import '../../core/api/rest_client.dart';
import '../../core/api/ws_client.dart';
import '../../core/config/server_config.dart';
import '../../core/models/events.dart';
import '../../core/models/session.dart';
import '../transcript/transcript_entry.dart';
import 'pcm_framer.dart';

enum MicStatus { idle, connecting, recording, stopping, error }

const micLanguages = <String, String>{
  'auto': '자동',
  'ko': '한국어',
  'en': '영어',
  'ja': '일본어',
};

class MicState {
  const MicState({
    this.status = MicStatus.idle,
    this.language = 'auto',
    this.level = 0,
    this.partial,
    this.entries = const [],
    this.sessionId,
    this.serverState,
    this.errorMessage,
    this.bytesSent = 0,
  });

  final MicStatus status;
  final String language;
  final double level;
  final TranscriptEntry? partial;
  final List<TranscriptEntry> entries;
  final String? sessionId;
  final String? serverState;
  final String? errorMessage;
  final int bytesSent;

  bool get isBusy =>
      status == MicStatus.connecting || status == MicStatus.stopping;

  MicState copyWith({
    MicStatus? status,
    String? language,
    double? level,
    TranscriptEntry? partial,
    bool clearPartial = false,
    List<TranscriptEntry>? entries,
    String? sessionId,
    bool clearSession = false,
    String? serverState,
    bool clearServerState = false,
    String? errorMessage,
    bool clearError = false,
    int? bytesSent,
  }) =>
      MicState(
        status: status ?? this.status,
        language: language ?? this.language,
        level: level ?? this.level,
        partial: clearPartial ? null : (partial ?? this.partial),
        entries: entries ?? this.entries,
        sessionId: clearSession ? null : (sessionId ?? this.sessionId),
        serverState: clearServerState ? null : (serverState ?? this.serverState),
        errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
        bytesSent: bytesSent ?? this.bytesSent,
      );
}

class MicController extends Notifier<MicState> {
  static const _sampleRate = 16000;
  static const _frameBytes = 640;

  AudioRecorder? _recorder;
  WsClient? _ws;
  StreamSubscription<Uint8List>? _audioSub;
  StreamSubscription<ServerEvent>? _eventSub;
  final PcmFramer _framer = PcmFramer(frameBytes: _frameBytes);
  DateTime _lastLevelUpdate = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  MicState build() {
    ref.onDispose(_teardown);
    return const MicState();
  }

  void setLanguage(String code) {
    if (state.status != MicStatus.idle && state.status != MicStatus.error) return;
    state = state.copyWith(language: code);
  }

  void clearEntries() {
    state = state.copyWith(entries: const [], clearPartial: true);
  }

  Future<void> start() async {
    if (state.status == MicStatus.recording || state.isBusy) return;
    state = state.copyWith(
      status: MicStatus.connecting,
      clearError: true,
      clearPartial: true,
      bytesSent: 0,
    );

    final recorder = AudioRecorder();
    try {
      if (!await recorder.hasPermission()) {
        throw StateError('마이크 권한이 없습니다');
      }

      final rest = ref.read(restClientProvider);
      final config = ref.read(serverConfigProvider);
      final session = await rest.createSession(
        SessionRequest.mic(srcLang: state.language),
      );

      final ws = WsClient(config.ws(session.wsUrl));
      await ws.connect();
      _ws = ws;
      _eventSub = ws.events.listen(
        _onEvent,
        onError: (Object e) => _fail('서버 연결 오류: $e'),
        onDone: _onServerClosed,
      );
      ws.sendText(ClientMessage.control('start'));

      final audio = await recorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: _sampleRate,
          numChannels: 1,
        ),
      );
      _recorder = recorder;
      _audioSub = audio.listen(_onAudio, onError: (Object e) => _fail('녹음 오류: $e'));

      state = state.copyWith(
        status: MicStatus.recording,
        sessionId: session.sessionId,
      );
    } catch (e) {
      await recorder.dispose();
      await _teardown();
      _fail(_describe(e));
    }
  }

  Future<void> stop() async {
    if (state.status != MicStatus.recording) return;
    state = state.copyWith(status: MicStatus.stopping);
    final sessionId = state.sessionId;
    try {
      await _audioSub?.cancel();
      _audioSub = null;
      await _recorder?.stop();
      final tail = _framer.flush();
      if (tail != null) _ws?.sendBinary(tail);
      _ws?.sendText(ClientMessage.control('stop'));
      await _teardown();
      if (sessionId != null) {
        try {
          await ref.read(restClientProvider).stopSession(sessionId);
        } catch (_) {}
      }
    } finally {
      state = state.copyWith(
        status: MicStatus.idle,
        level: 0,
        clearSession: true,
        clearPartial: true,
        clearServerState: true,
      );
    }
  }

  void _onAudio(Uint8List chunk) {
    final ws = _ws;
    if (ws == null) return;
    var sent = 0;
    for (final frame in _framer.push(chunk)) {
      ws.sendBinary(frame);
      sent += frame.length;
    }
    final now = DateTime.now();
    if (now.difference(_lastLevelUpdate).inMilliseconds >= 80) {
      _lastLevelUpdate = now;
      state = state.copyWith(
        level: pcm16Rms(chunk),
        bytesSent: state.bytesSent + sent,
      );
    } else if (sent > 0) {
      state = state.copyWith(bytesSent: state.bytesSent + sent);
    }
  }

  void _onEvent(ServerEvent event) {
    switch (event.payload) {
      case SessionStatePayload p:
        state = state.copyWith(serverState: p.state);
      case SegmentPartialPayload p:
        state = state.copyWith(
          partial: TranscriptEntry(
            segId: p.segId,
            tStartMs: p.tStartMs,
            tEndMs: null,
            text: p.text,
            lang: p.lang,
            langProb: null,
            isFinal: false,
          ),
        );
      case SegmentFinalPayload p:
        final entry = TranscriptEntry(
          segId: p.segId,
          tStartMs: p.tStartMs,
          tEndMs: p.tEndMs,
          text: p.text,
          lang: p.lang,
          langProb: p.langProb,
          isFinal: true,
          sttMs: p.sttMs,
          forcedCut: p.forcedCut,
        );
        final clearPartial = state.partial?.segId == p.segId;
        state = state.copyWith(
          entries: [...state.entries, entry],
          clearPartial: clearPartial,
        );
      case TranslationFinalPayload p:
        state = state.copyWith(
          entries: [
            for (final e in state.entries)
              if (e.segId == p.segId) e.copyWith(translation: p.text) else e,
          ],
        );
      case ErrorPayload p:
        if (p.recoverable) {
          state = state.copyWith(errorMessage: '${p.code}: ${p.message}');
        } else {
          _fail('${p.code}: ${p.message}');
          unawaited(_abort());
        }
      case TtsReadyPayload():
      case DeadlineEventPayload():
      case MetricsPayload():
      case UnknownPayload():
        break;
    }
  }

  void _onServerClosed() {
    if (state.status == MicStatus.recording) {
      _fail('서버가 연결을 끊었습니다');
      unawaited(_abort());
    }
  }

  Future<void> _abort() async {
    await _audioSub?.cancel();
    _audioSub = null;
    await _recorder?.stop();
    await _teardown();
  }

  void _fail(String message) {
    state = state.copyWith(
      status: MicStatus.error,
      errorMessage: message,
      level: 0,
      clearSession: true,
      clearPartial: true,
      clearServerState: true,
    );
  }

  Future<void> _teardown() async {
    await _audioSub?.cancel();
    _audioSub = null;
    await _eventSub?.cancel();
    _eventSub = null;
    final recorder = _recorder;
    _recorder = null;
    await recorder?.dispose();
    final ws = _ws;
    _ws = null;
    await ws?.close();
    _framer.flush();
  }

  static String _describe(Object e) {
    if (e is ApiException) return '서버 응답 오류 (${e.statusCode ?? '-'}): ${e.message}';
    if (e is TimeoutException) return '서버 응답 시간 초과';
    if (e is StateError) return e.message;
    return '연결 실패: $e';
  }
}

final micControllerProvider = NotifierProvider<MicController, MicState>(
  MicController.new,
);

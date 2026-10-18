import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:record/record.dart';

import '../../core/api/rest_client.dart';
import '../../core/config/server_config.dart';
import '../../core/models/events.dart';
import '../../core/models/session.dart';
import '../../core/session/stt_session.dart';
import '../transcript/transcript_entry.dart';
import '../transcript/transcript_session_state.dart';
import 'pcm_framer.dart';

enum MicStatus { idle, connecting, recording, stopping, error }

class MicState {
  const MicState({
    this.status = MicStatus.idle,
    this.language = 'auto',
    this.level = 0,
    this.transcript = const TranscriptSessionState(),
    this.sessionId,
    this.errorMessage,
    this.bytesSent = 0,
  });

  final MicStatus status;
  final String language;
  final double level;
  final TranscriptSessionState transcript;
  final String? sessionId;
  final String? errorMessage;
  final int bytesSent;

  TranscriptEntry? get partial => transcript.partial;
  List<TranscriptEntry> get entries => transcript.entries;
  String? get serverState => transcript.serverState;
  String? get warning => transcript.warning;

  bool get isBusy =>
      status == MicStatus.connecting || status == MicStatus.stopping;

  MicState copyWith({
    MicStatus? status,
    String? language,
    double? level,
    TranscriptSessionState? transcript,
    String? sessionId,
    bool clearSession = false,
    String? errorMessage,
    bool clearError = false,
    int? bytesSent,
  }) =>
      MicState(
        status: status ?? this.status,
        language: language ?? this.language,
        level: level ?? this.level,
        transcript: transcript ?? this.transcript,
        sessionId: clearSession ? null : (sessionId ?? this.sessionId),
        errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
        bytesSent: bytesSent ?? this.bytesSent,
      );
}

class MicController extends Notifier<MicState> {
  static const _sampleRate = 16000;
  static const _frameBytes = 640;

  AudioRecorder? _recorder;
  SttSessionClient? _client;
  StreamSubscription<Uint8List>? _audioSub;
  StreamSubscription<ServerEvent>? _eventSub;
  final PcmFramer _framer = PcmFramer(frameBytes: _frameBytes);
  DateTime _lastLevelUpdate = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  MicState build() {
    ref.onDispose(() => unawaited(_teardown()));
    return const MicState();
  }

  void setLanguage(String code) {
    if (state.status != MicStatus.idle && state.status != MicStatus.error) {
      return;
    }
    state = state.copyWith(language: code);
  }

  void clearEntries() {
    state = state.copyWith(
      transcript: state.transcript.copyWith(entries: const [], clearPartial: true),
    );
  }

  Future<void> start() async {
    if (state.status == MicStatus.recording || state.isBusy) return;
    state = state.copyWith(
      status: MicStatus.connecting,
      clearError: true,
      bytesSent: 0,
      transcript: state.transcript.ended().copyWith(clearWarning: true),
    );

    final recorder = AudioRecorder();
    try {
      if (!await recorder.hasPermission()) {
        throw StateError('마이크 권한이 없습니다');
      }

      final client = SttSessionClient(
        rest: ref.read(restClientProvider),
        config: ref.read(serverConfigProvider),
      );
      _client = client;
      final session = await client.open(
        SessionRequest.mic(srcLang: state.language),
      );
      _eventSub = client.events.listen(
        _onEvent,
        onError: (Object e) => _fail('서버 연결 오류: $e'),
        onDone: _onServerClosed,
      );

      final audio = await recorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: _sampleRate,
          numChannels: 1,
        ),
      );
      _recorder = recorder;
      _audioSub = audio.listen(
        _onAudio,
        onError: (Object e) => _fail('녹음 오류: $e'),
      );

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

  /// 녹음을 멈추고 `control stop` → 서버가 마지막 발화를 끝내 `stopped` 를 줄 때까지 기다린다 (S-1).
  Future<void> stop() async {
    if (state.status != MicStatus.recording) return;
    state = state.copyWith(status: MicStatus.stopping);
    try {
      await _audioSub?.cancel();
      _audioSub = null;
      await _recorder?.stop();
      final tail = _framer.flush();
      if (tail != null) _client?.sendAudio(tail);
      await _client?.stop();
      await _teardown();
    } finally {
      state = state.copyWith(
        status: MicStatus.idle,
        level: 0,
        clearSession: true,
        transcript: state.transcript.ended(),
      );
    }
  }

  void _onAudio(Uint8List chunk) {
    final client = _client;
    if (client == null) return;
    var sent = 0;
    for (final frame in _framer.push(chunk)) {
      client.sendAudio(frame);
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
    state = state.copyWith(transcript: reduceTranscript(state.transcript, event));
    if (event.payload case ErrorPayload(recoverable: false) && final p) {
      _fail('${p.code}: ${p.message}');
      unawaited(_abort());
    }
  }

  void _onServerClosed() {
    // 앱이 stop 을 보낸 뒤의 close 는 정상 (서버가 stopped 후 닫는다, S-1)
    if (state.status == MicStatus.recording && _client?.isStopping != true) {
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
      transcript: state.transcript.ended(),
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
    final client = _client;
    _client = null;
    await client?.abort();
    _framer.flush();
  }

  static String _describe(Object e) {
    if (e is ApiException) return '서버 응답 오류: $e';
    if (e is TimeoutException) return '서버 응답 시간 초과';
    if (e is StateError) return e.message;
    return '연결 실패: $e';
  }
}

final micControllerProvider = NotifierProvider<MicController, MicState>(
  MicController.new,
);

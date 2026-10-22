import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/rest_client.dart';
import '../../core/config/server_config.dart';
import '../../core/models/capture_target.dart';
import '../../core/models/events.dart';
import '../../core/models/session.dart';
import '../../core/session/stt_session.dart';
import '../transcript/transcript_entry.dart';
import '../transcript/transcript_session_state.dart';

/// 방송(모드 B) — PC 에서 재생 중인 창의 소리를 서버가 캡처해 실시간 자막을 준다 (API 계약 S-8·S-9).
enum BroadcastStatus { idle, loadingTargets, connecting, running, stopping, error }

class BroadcastState {
  const BroadcastState({
    this.status = BroadcastStatus.idle,
    this.targets = const [],
    this.appCaptureSupported = true,
    this.captureAvailable = true,
    this.targetsError,
    this.selectedTargetId,
    this.language = 'auto',
    this.transcript = const TranscriptSessionState(),
    this.sessionId,
    this.errorMessage,
    this.startedAt,
    this.tick = 0,
  });

  final BroadcastStatus status;
  final List<CaptureTarget> targets;
  final bool appCaptureSupported;
  final bool captureAvailable;
  final String? targetsError;
  final String? selectedTargetId;
  final String language;
  final TranscriptSessionState transcript;
  final String? sessionId;
  final String? errorMessage;
  final DateTime? startedAt;

  /// 실행 중 1 s 마다 증가 — 경과 시간 표시를 다시 그리기 위한 값.
  final int tick;

  TranscriptEntry? get partial => transcript.partial;
  List<TranscriptEntry> get entries => transcript.entries;
  String? get serverState => transcript.serverState;
  String? get warning => transcript.warning;

  bool get isRunning => status == BroadcastStatus.running;
  bool get isBusy =>
      status == BroadcastStatus.connecting ||
      status == BroadcastStatus.stopping ||
      status == BroadcastStatus.loadingTargets;

  CaptureTarget? get selectedTarget {
    for (final t in targets) {
      if (t.id == selectedTargetId) return t;
    }
    return null;
  }

  BroadcastState copyWith({
    BroadcastStatus? status,
    List<CaptureTarget>? targets,
    bool? appCaptureSupported,
    bool? captureAvailable,
    String? targetsError,
    bool clearTargetsError = false,
    String? selectedTargetId,
    String? language,
    TranscriptSessionState? transcript,
    String? sessionId,
    bool clearSession = false,
    String? errorMessage,
    bool clearError = false,
    DateTime? startedAt,
    bool clearStartedAt = false,
    int? tick,
  }) =>
      BroadcastState(
        status: status ?? this.status,
        targets: targets ?? this.targets,
        appCaptureSupported: appCaptureSupported ?? this.appCaptureSupported,
        captureAvailable: captureAvailable ?? this.captureAvailable,
        targetsError:
            clearTargetsError ? null : (targetsError ?? this.targetsError),
        selectedTargetId: selectedTargetId ?? this.selectedTargetId,
        language: language ?? this.language,
        transcript: transcript ?? this.transcript,
        sessionId: clearSession ? null : (sessionId ?? this.sessionId),
        errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
        startedAt: clearStartedAt ? null : (startedAt ?? this.startedAt),
        tick: tick ?? this.tick,
      );
}

class BroadcastController extends Notifier<BroadcastState> {
  SttSessionClient? _client;
  StreamSubscription<ServerEvent>? _eventSub;
  Timer? _ticker;

  @override
  BroadcastState build() {
    ref.onDispose(() => unawaited(_teardown()));
    return const BroadcastState();
  }

  /// `GET /api/capture/targets`. 실행 중에는 목록만 갱신하고 선택은 유지한다.
  Future<void> refreshTargets() async {
    if (state.status == BroadcastStatus.loadingTargets) return;
    final wasIdle = !state.isRunning && state.status != BroadcastStatus.stopping;
    if (wasIdle) {
      state = state.copyWith(
        status: BroadcastStatus.loadingTargets,
        clearTargetsError: true,
      );
    }
    try {
      final result = await ref.read(restClientProvider).captureTargets();
      final ids = result.targets.map((t) => t.id).toSet();
      final keep = state.selectedTargetId != null &&
          ids.contains(state.selectedTargetId);
      state = state.copyWith(
        status: wasIdle ? BroadcastStatus.idle : state.status,
        targets: result.targets,
        appCaptureSupported: result.appCaptureSupported,
        captureAvailable: result.captureAvailable,
        selectedTargetId: keep
            ? state.selectedTargetId
            : (result.targets.isEmpty ? null : result.targets.first.id),
        clearTargetsError: true,
      );
    } catch (e) {
      state = state.copyWith(
        status: wasIdle ? BroadcastStatus.idle : state.status,
        targetsError: _describe(e),
      );
    }
  }

  void selectTarget(String id) {
    if (state.isRunning || state.isBusy) return;
    state = state.copyWith(selectedTargetId: id);
  }

  void setLanguage(String code) {
    if (state.isRunning || state.isBusy) return;
    state = state.copyWith(language: code);
  }

  void clearEntries() {
    state = state.copyWith(
      transcript: state.transcript.copyWith(entries: const [], clearPartial: true),
    );
  }

  Future<void> start() async {
    if (state.isRunning || state.isBusy) return;
    final target = state.selectedTargetId;
    if (target == null) {
      state = state.copyWith(
        status: BroadcastStatus.error,
        errorMessage: '캡처할 대상을 먼저 고르세요',
      );
      return;
    }
    state = state.copyWith(
      status: BroadcastStatus.connecting,
      clearError: true,
      transcript: state.transcript.ended().copyWith(clearWarning: true),
    );
    try {
      final client = SttSessionClient(
        rest: ref.read(restClientProvider),
        config: ref.read(serverConfigProvider),
      );
      _client = client;
      final session = await client.open(
        SessionRequest.broadcast(target: target, srcLang: state.language),
      );
      _eventSub = client.events.listen(
        _onEvent,
        onError: (Object e) => _fail('서버 연결 오류: $e'),
        onDone: _onServerClosed,
      );
      state = state.copyWith(
        status: BroadcastStatus.running,
        sessionId: session.sessionId,
        startedAt: DateTime.now(),
        tick: 0,
      );
      _ticker?.cancel();
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (state.isRunning) state = state.copyWith(tick: state.tick + 1);
      });
    } catch (e) {
      await _teardown();
      _fail(_describe(e));
    }
  }

  Future<void> stop() async {
    if (!state.isRunning) return;
    state = state.copyWith(status: BroadcastStatus.stopping);
    try {
      await _client?.stop();
      await _teardown();
    } finally {
      state = state.copyWith(
        status: BroadcastStatus.idle,
        clearSession: true,
        clearStartedAt: true,
        transcript: state.transcript.ended(),
      );
    }
  }

  void _onEvent(ServerEvent event) {
    state = state.copyWith(transcript: reduceTranscript(state.transcript, event));
    if (event.payload case ErrorPayload(recoverable: false) && final p) {
      _fail(_captureMessage(p));
      unawaited(_teardown());
    }
  }

  void _onServerClosed() {
    if (state.isRunning && _client?.isStopping != true) {
      _fail('서버가 연결을 끊었습니다');
      unawaited(_teardown());
    }
  }

  void _fail(String message) {
    state = state.copyWith(
      status: BroadcastStatus.error,
      errorMessage: message,
      clearSession: true,
      clearStartedAt: true,
      transcript: state.transcript.ended(),
    );
  }

  Future<void> _teardown() async {
    _ticker?.cancel();
    _ticker = null;
    await _eventSub?.cancel();
    _eventSub = null;
    final client = _client;
    _client = null;
    await client?.abort();
  }

  static String _captureMessage(ErrorPayload p) => switch (p.code) {
        'E_CAPTURE_LOST' => '캡처가 끊겼습니다 (창이 닫혔거나 소리 장치가 바뀜)',
        'E_CAPTURE_START' => '캡처를 시작하지 못했습니다: ${p.message}',
        _ => '${p.code}: ${p.message}',
      };

  static String _describe(Object e) {
    if (e is ApiException) {
      if (e.code == 'E_CAPTURE_TARGET') {
        return '대상을 찾을 수 없습니다. 목록을 새로 고친 뒤 다시 고르세요';
      }
      if (e.code == 'E_CAPTURE_UNAVAILABLE' || e.statusCode == 503) {
        return r'서버에 캡처 도구가 없습니다 (scripts\build_wincap.bat 실행 필요)';
      }
      // 404(엔드포인트 없음)·501 은 서버가 아직 방송 캡처를 지원하지 않는 것
      if (e.code == 'E_NOT_IMPLEMENTED' || e.statusCode == 404 || e.statusCode == 501) {
        return '서버가 아직 방송 캡처를 지원하지 않습니다 (서버 업데이트 필요)';
      }
      return '서버 응답 오류: $e';
    }
    if (e is TimeoutException) return '서버 응답 시간 초과';
    return '연결 실패: $e';
  }
}

final broadcastControllerProvider =
    NotifierProvider<BroadcastController, BroadcastState>(
  BroadcastController.new,
);

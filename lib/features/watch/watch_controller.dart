import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/rest_client.dart';
import '../../core/config/server_config.dart';
import '../../core/models/audio_route.dart';
import '../../core/models/events.dart';
import '../../core/session/stt_session.dart';
import '../engines/engine_controller.dart';
import '../transcript/transcript_entry.dart';
import '../transcript/transcript_session_state.dart';
import 'watch_settings.dart';
import 'watch_timeline.dart';

/// 세션 단계. 서버 `session.state` (명세 §6.2) 에 앱 쪽 단계(연결 중·정리 중·종료·오류)를 더한 것.
enum WatchPhase {
  idle,

  /// REST 세션 생성 + WS 연결 중 (서버 이벤트 받기 전).
  connecting,
  starting,
  calibrating,
  buffering,
  playing,
  stopping,

  /// 입력이 정상 종료(`E_INPUT_ENDED`, S-31)되고 서버 세션은 `stopped` 됐지만, HLS 에 D 초만큼 지연된
  /// 내용이 남아 있어 플레이어·자막을 계속 보여 주는 단계. 플레이어가 ENDLIST 에 닿거나
  /// [WatchState.drainUntilMs] 가 지나면 [ended].
  draining,
  ended,
  error;

  static WatchPhase? fromServer(String state) => switch (state) {
        'starting' => WatchPhase.starting,
        'calibrating' => WatchPhase.calibrating,
        'buffering' => WatchPhase.buffering,
        'playing' => WatchPhase.playing,
        'stopped' => WatchPhase.ended,
        'error' => WatchPhase.error,
        _ => null,
      };

  bool get isLive =>
      this == WatchPhase.starting ||
      this == WatchPhase.calibrating ||
      this == WatchPhase.buffering ||
      this == WatchPhase.playing;

  bool get isBusy => this == WatchPhase.connecting || this == WatchPhase.stopping;

  /// 플레이어가 재생 중이고 자막을 그려야 하는 단계 (재생 중 + 방송 끝 뒤 남은 지연분).
  bool get isPlayback => this == WatchPhase.playing || this == WatchPhase.draining;

  String get label => switch (this) {
        WatchPhase.idle => '대기',
        WatchPhase.connecting => '서버 연결 중',
        WatchPhase.starting => '세션 준비 중',
        WatchPhase.calibrating => '지연 보정 중',
        WatchPhase.buffering => '지연 버퍼 채우는 중',
        WatchPhase.playing => '재생 중',
        WatchPhase.stopping => '마지막 문장 정리 중',
        WatchPhase.draining => '방송 끝 · 남은 지연분 재생 중',
        WatchPhase.ended => '종료됨',
        WatchPhase.error => '오류',
      };
}

enum RouteCheckStatus { unknown, loadingDevices, unsupported, idle, checking, passed, failed }

/// 소리 격리 점검 (명세 §4.9). 서버가 엔드포인트를 아직 안 주면 [RouteCheckStatus.unsupported].
class RouteCheckState {
  const RouteCheckState({
    this.status = RouteCheckStatus.unknown,
    this.devices,
    this.devicesError,
    this.result,
    this.error,
  });

  final RouteCheckStatus status;
  final AudioDevices? devices;
  final String? devicesError;
  final RouteStatus? result;
  final String? error;

  bool get blocksStart => status == RouteCheckStatus.failed;

  RouteCheckState copyWith({
    RouteCheckStatus? status,
    AudioDevices? devices,
    String? devicesError,
    bool clearDevicesError = false,
    RouteStatus? result,
    bool clearResult = false,
    String? error,
    bool clearError = false,
  }) =>
      RouteCheckState(
        status: status ?? this.status,
        devices: devices ?? this.devices,
        devicesError: clearDevicesError ? null : (devicesError ?? this.devicesError),
        result: clearResult ? null : (result ?? this.result),
        error: clearError ? null : (error ?? this.error),
      );
}

enum CalibrateStatus { idle, running, done, failed, unsupported }

class CalibrateState {
  const CalibrateState({this.status = CalibrateStatus.idle, this.result, this.error});

  final CalibrateStatus status;
  final CalibrateResult? result;
  final String? error;
}

class WatchError {
  const WatchError({required this.code, required this.message, this.recoverable = false});

  final String code;
  final String message;
  final bool recoverable;

  /// 사용자용 한 줄 설명 (코드별, API 계약 Q-API-7·S-11, 명세 v0.5 E_ROUTE_*).
  String get title => switch (code) {
        'E_ROUTE_LOST' => '격리 장치 연결이 끊겼습니다',
        'E_ROUTE_NOT_ISOLATED' => '원본 소리가 격리되지 않았습니다',
        'E_CAPTURE_LOST' => '방송 입력이 끊겼습니다',
        'E_CAPTURE_START' => '캡처를 시작하지 못했습니다',
        'E_CAPTURE_TARGET' => '캡처 대상을 찾을 수 없습니다',
        'E_CAPTURE_UNAVAILABLE' => '서버에 캡처 도구가 없습니다',
        'E_NOT_IMPLEMENTED' => '서버가 아직 동기 시청을 지원하지 않습니다',
        'E_SESSION_NOT_FOUND' => '세션이 사라졌습니다',
        'E_STT_FAILED' => '한 문장 인식에 실패했습니다',
        'E_CONNECTION_LOST' => '서버와 연결이 끊겼습니다',
        'E_TIMEOUT' => '서버 응답이 없습니다',
        _ => '문제가 생겼습니다',
      };

  String get hint => switch (code) {
        'E_ROUTE_LOST' => '격리 장치(모니터 오디오 등)가 꺼지거나 분리됐습니다. 장치를 다시 연결하고 점검 후 시작하세요.',
        'E_ROUTE_NOT_ISOLATED' =>
          '브라우저 출력 장치를 격리 장치로 바꾼 뒤 "소리 격리 점검"을 통과해야 시작할 수 있습니다.',
        'E_CAPTURE_LOST' =>
          '연결 거부·시간 초과·디코딩 실패 또는 소리 장치 변경입니다. 방송이 정상적으로 끝난 경우는 오류 없이 "방송이 끝났습니다"로 표시됩니다.',
        'E_NOT_IMPLEMENTED' => '서버가 모드 A 를 올리면 같은 화면으로 바로 연결됩니다. 지금은 UI 만 미리 준비된 상태입니다.',
        'E_CONNECTION_LOST' => '서버가 꺼졌거나 네트워크가 끊겼습니다. 서버 상태를 확인한 뒤 다시 시도하세요.',
        'E_TIMEOUT' => '서버를 방금 켰다면 모델 로드 중(10~20 s)일 수 있습니다.',
        _ => message,
      };
}

class WatchState {
  const WatchState({
    this.settings = const WatchSettings(),
    this.route = const RouteCheckState(),
    this.calibrate = const CalibrateState(),
    this.phase = WatchPhase.idle,
    this.sessionId,
    this.hlsUrl,
    this.clock = const PlaybackClock(),
    this.transcript = const TranscriptSessionState(),
    this.deadlines = const DeadlineStats(),
    this.metrics,
    this.error,
    this.warning,
    this.warningSeq = 0,
    this.subtitleMode = SubtitleMode.translation,
    this.originalVolume = 1.0,
    this.ttsVolume = 1.0,
    this.muted = false,
    this.startedAt,
    this.endedAt,
    this.restoreGuide,
    this.inputEnded = false,
    this.drainUntilMs,
  });

  final WatchSettings settings;
  final RouteCheckState route;
  final CalibrateState calibrate;

  final WatchPhase phase;
  final String? sessionId;
  final String? hlsUrl;
  final PlaybackClock clock;
  final TranscriptSessionState transcript;
  final DeadlineStats deadlines;
  final MetricsPayload? metrics;
  final WatchError? error;

  /// 복구 가능한 오류·경고 (스낵바용). [warningSeq] 가 바뀔 때마다 새로 띄운다.
  final String? warning;
  final int warningSeq;

  final SubtitleMode subtitleMode;
  final double originalVolume;
  final double ttsVolume;
  final bool muted;
  final DateTime? startedAt;
  final DateTime? endedAt;

  /// 세션 종료 시 보여줄 복구 안내 ("브라우저 출력을 원래 장치로", 명세 §4.9).
  final String? restoreGuide;

  /// 서버가 `E_INPUT_ENDED` (입력 정상 종료, S-31) 를 보냈다. 이어서 오는 `stopped` 는 종료 화면 대신
  /// [WatchPhase.draining] 으로 간다.
  final bool inputEnded;

  /// [WatchPhase.draining] 을 늦어도 이 벽시계(ms)에는 끝낸다 (플레이어 ENDLIST 신호가 없을 때의 보험).
  final int? drainUntilMs;

  /// 방송 끝 뒤 남은 재생 시간(초, 0 이상). draining 이 아니면 null.
  int? drainRemainingS(int nowMs) {
    final until = drainUntilMs;
    if (phase != WatchPhase.draining || until == null) return null;
    return ((until - nowMs) / 1000).ceil().clamp(0, 1 << 30);
  }

  /// 방송 끝 뒤 플레이어를 더 틀어 둘 마감: 지연 D 초 + 여유. 서버는 남은 인식·번역·HLS 플러시를 끝낸 뒤
  /// `E_INPUT_ENDED` 를 보내므로 실제 남은 양은 이보다 짧다 — 플레이어 ENDLIST 가 먼저 오면 그때 끝낸다.
  static const drainMarginMs = 2000;
  static int drainDeadline(int nowMs, int? delayS) => nowMs + (delayS ?? 0) * 1000 + drainMarginMs;

  List<TranscriptEntry> get entries => transcript.entries;
  int? get delayS => clock.delayS;
  bool get isLive => phase.isLive;
  /// 소스에 영상이 있다고 기대하는가 (`obs_stream`). 소리만 모드도 서버 HLS(오디오 믹스)는 준다 → [hasStream].
  bool get hasVideo => settings.sourceKind == WatchSourceKind.obs;

  /// 서버가 `hls_url` 을 줬는가 (모드 A 는 영상 유무와 관계없이 준다, S-21 ①③).
  bool get hasStream => hlsUrl != null;

  /// 서버가 소리 격리(`/api/audio/*`)를 지원한다고 확인됐는가 (장치 목록을 받은 뒤).
  bool get routeSupported => switch (route.status) {
        RouteCheckStatus.unknown ||
        RouteCheckStatus.loadingDevices ||
        RouteCheckStatus.unsupported =>
          false,
        _ => true,
      };

  /// 시작을 막아야 하는 이유. null 이면 시작 가능 (API 계약 S-29 ③).
  ///
  /// - 점검 실패 → 통과해야 시작.
  /// - **"소리만" 입력은 격리 장치가 필수**: PC 전체 소리를 캡처하면 지연 출력이 다시 녹음되므로 서버가
  ///   400 `E_ROUTE_NOT_ISOLATED` 로 거부한다. 서버가 격리를 지원하는 걸 확인한 뒤에만 막는다
  ///   (구 서버·가짜 서버는 `route` 없이도 시작).
  String? get startBlockReason {
    if (route.blocksStart) return '소리 격리 점검을 통과해야 시작할 수 있어요';
    if (settings.sourceKind == WatchSourceKind.audioOnly &&
        routeSupported &&
        settings.isolationDeviceId == null) {
      return '소리만 입력은 격리 장치를 골라야 시작할 수 있어요 (PC 전체 소리는 되먹임 때문에 서버가 거부합니다)';
    }
    return null;
  }

  int? get recommendedNextDelayS => recommendedNextDelay(
        delayS: delayS,
        missRate: metrics?.missRate ?? 0,
      );

  WatchState copyWith({
    WatchSettings? settings,
    RouteCheckState? route,
    CalibrateState? calibrate,
    WatchPhase? phase,
    String? sessionId,
    bool clearSession = false,
    String? hlsUrl,
    PlaybackClock? clock,
    TranscriptSessionState? transcript,
    DeadlineStats? deadlines,
    MetricsPayload? metrics,
    bool clearMetrics = false,
    WatchError? error,
    bool clearError = false,
    String? warning,
    int? warningSeq,
    SubtitleMode? subtitleMode,
    double? originalVolume,
    double? ttsVolume,
    bool? muted,
    DateTime? startedAt,
    DateTime? endedAt,
    bool clearTimes = false,
    String? restoreGuide,
    bool clearRestoreGuide = false,
    bool? inputEnded,
    int? drainUntilMs,
    bool clearDrain = false,
  }) =>
      WatchState(
        settings: settings ?? this.settings,
        route: route ?? this.route,
        calibrate: calibrate ?? this.calibrate,
        phase: phase ?? this.phase,
        sessionId: clearSession ? null : (sessionId ?? this.sessionId),
        hlsUrl: clearSession ? null : (hlsUrl ?? this.hlsUrl),
        clock: clock ?? this.clock,
        transcript: transcript ?? this.transcript,
        deadlines: deadlines ?? this.deadlines,
        metrics: clearMetrics ? null : (metrics ?? this.metrics),
        error: clearError ? null : (error ?? this.error),
        warning: warning ?? this.warning,
        warningSeq: warningSeq ?? this.warningSeq,
        subtitleMode: subtitleMode ?? this.subtitleMode,
        originalVolume: originalVolume ?? this.originalVolume,
        ttsVolume: ttsVolume ?? this.ttsVolume,
        muted: muted ?? this.muted,
        startedAt: clearTimes ? null : (startedAt ?? this.startedAt),
        endedAt: clearTimes ? null : (endedAt ?? this.endedAt),
        restoreGuide: clearRestoreGuide ? null : (restoreGuide ?? this.restoreGuide),
        inputEnded: clearDrain ? false : (inputEnded ?? this.inputEnded),
        drainUntilMs: clearDrain ? null : (drainUntilMs ?? this.drainUntilMs),
      );
}

/// 동기 시청(모드 A) 컨트롤러.
///
/// 서버가 모드 A 를 아직 올리지 않았으므로 모든 호출은 "엔드포인트 없음(404·501)" 을
/// 정상 경로로 다룬다 — 화면은 미지원 안내를 보여주고, 서버가 올라오면 코드 변경 없이 붙는다.
class WatchController extends Notifier<WatchState> {
  SttSessionClient? _client;
  StreamSubscription<ServerEvent>? _sub;
  Timer? _drainTimer;

  @override
  WatchState build() {
    ref.onDispose(() {
      _drainTimer?.cancel();
      unawaited(_teardown());
    });
    return const WatchState();
  }

  /// 서버 주소가 바뀌었을 때 (설정 화면이 호출). 미지원/장치 목록 판단을 처음부터 다시 한다.
  Future<void> onServerChanged() async {
    if (state.isLive || state.phase.isBusy) return;
    state = state.copyWith(route: const RouteCheckState(), calibrate: const CalibrateState());
    // restClientProvider 가 새 주소로 다시 만들어진 뒤에 읽도록 한 틱 미룬다.
    await Future<void>.delayed(Duration.zero);
    await loadDevices();
  }

  // ---- 설정 -----------------------------------------------------------------

  void updateSettings(WatchSettings Function(WatchSettings) f) {
    if (state.isLive || state.phase.isBusy) return;
    final next = f(state.settings);
    final deviceChanged = next.isolationDeviceId != state.settings.isolationDeviceId;
    state = state.copyWith(
      settings: next,
      // 격리 장치를 바꾸면 이전 점검 결과는 무효.
      route: deviceChanged && state.route.status != RouteCheckStatus.unsupported
          ? state.route.copyWith(status: RouteCheckStatus.idle, clearResult: true, clearError: true)
          : null,
    );
  }

  void setSubtitleMode(SubtitleMode mode) => state = state.copyWith(subtitleMode: mode);

  void cycleSubtitleMode() => setSubtitleMode(state.subtitleMode.next);

  /// 원음·번역 음성 볼륨 (0~1). 서버 합성 믹스라 `config.update` 로 서버에도 알린다 (API 계약 Q-API-10).
  void setVolumes({double? original, double? tts, bool? muted}) {
    state = state.copyWith(originalVolume: original, ttsVolume: tts, muted: muted);
    _sendConfig({
      'volume': {
        'original': state.muted ? 0.0 : state.originalVolume,
        'tts': state.muted ? 0.0 : state.ttsVolume,
      },
    });
  }

  void _sendConfig(Map<String, dynamic> payload) {
    final client = _client;
    if (client == null || !state.isLive) return;
    client.sendText(jsonEncode({'type': 'config.update', 'payload': payload}));
  }

  // ---- 소리 격리 점검 -------------------------------------------------------

  Future<void> loadDevices() async {
    if (state.route.status == RouteCheckStatus.loadingDevices) return;
    state = state.copyWith(
      route: state.route.copyWith(status: RouteCheckStatus.loadingDevices, clearDevicesError: true),
    );
    try {
      final devices = await ref.read(restClientProvider).audioDevices();
      final keep = state.settings.isolationDeviceId != null &&
          devices.devices.any((d) => d.id == state.settings.isolationDeviceId);
      final firstCandidate = devices.candidates.isEmpty ? null : devices.candidates.first.id;
      state = state.copyWith(
        route: state.route.copyWith(
          status: RouteCheckStatus.idle,
          devices: devices,
          clearResult: true,
        ),
        settings: state.settings.copyWith(
          isolationDeviceId: keep ? state.settings.isolationDeviceId : firstCandidate,
          clearIsolationDevice: !keep && firstCandidate == null,
          router: devices.router ?? state.settings.router,
        ),
      );
    } on ApiException catch (e) {
      if (_isUnsupported(e)) {
        state = state.copyWith(
          route: const RouteCheckState(status: RouteCheckStatus.unsupported),
          settings: state.settings.copyWith(clearIsolationDevice: true),
        );
        return;
      }
      state = state.copyWith(
        route: state.route.copyWith(status: RouteCheckStatus.idle, devicesError: _describe(e)),
      );
    } catch (e) {
      state = state.copyWith(
        route: state.route.copyWith(status: RouteCheckStatus.idle, devicesError: _describe(e)),
      );
    }
  }

  Future<void> runRouteCheck() async {
    final device = state.settings.isolationDeviceId;
    if (device == null || state.route.status == RouteCheckStatus.checking) return;
    state = state.copyWith(
      route: state.route.copyWith(status: RouteCheckStatus.checking, clearError: true),
    );
    try {
      final result = await ref.read(restClientProvider).routeCheck(
            router: state.settings.router,
            isolationDevice: device,
          );
      state = state.copyWith(
        route: state.route.copyWith(
          status: result.isolated ? RouteCheckStatus.passed : RouteCheckStatus.failed,
          result: result,
        ),
      );
    } on ApiException catch (e) {
      if (_isUnsupported(e)) {
        state = state.copyWith(route: const RouteCheckState(status: RouteCheckStatus.unsupported));
        return;
      }
      state = state.copyWith(
        route: state.route.copyWith(status: RouteCheckStatus.idle, error: _describe(e)),
      );
    } catch (e) {
      state = state.copyWith(
        route: state.route.copyWith(status: RouteCheckStatus.idle, error: _describe(e)),
      );
    }
  }

  // ---- 지연 보정 -----------------------------------------------------------

  Future<void> runCalibrate() async {
    if (state.calibrate.status == CalibrateStatus.running) return;
    state = state.copyWith(calibrate: const CalibrateState(status: CalibrateStatus.running));
    try {
      final result = await ref.read(restClientProvider).calibrate();
      state = state.copyWith(
        calibrate: CalibrateState(status: CalibrateStatus.done, result: result),
        settings: state.settings.copyWith(manualDelayS: _clampDelay(result.recommendedDelayS)),
      );
    } on ApiException catch (e) {
      state = state.copyWith(
        calibrate: _isUnsupported(e)
            ? const CalibrateState(status: CalibrateStatus.unsupported)
            : CalibrateState(status: CalibrateStatus.failed, error: _describe(e)),
      );
    } catch (e) {
      state = state.copyWith(
        calibrate: CalibrateState(status: CalibrateStatus.failed, error: _describe(e)),
      );
    }
  }

  static int _clampDelay(int v) =>
      v.clamp(WatchSettings.minDelayS, WatchSettings.maxDelayS);

  // ---- 세션 -----------------------------------------------------------------

  Future<void> start() async {
    if (state.isLive || state.phase.isBusy) return;
    state = state.copyWith(
      phase: WatchPhase.connecting,
      clearError: true,
      clearSession: true,
      clearMetrics: true,
      clearTimes: true,
      clearRestoreGuide: true,
      clearDrain: true,
      clock: const PlaybackClock(),
      deadlines: const DeadlineStats(),
      transcript: const TranscriptSessionState(),
    );
    try {
      final client = SttSessionClient(
        rest: ref.read(restClientProvider),
        config: ref.read(serverConfigProvider),
      );
      _client = client;
      final engines = ref.read(engineControllerProvider).selection;
      final info = await client.open(state.settings.toRequest(
        sttEngine: engines.sttEngineForRequest,
        mtModel: engines.mtModel,
      ));
      _sub = client.events.listen(
        _onEvent,
        onError: (Object e) => _fail(WatchError(code: 'E_CONNECTION_LOST', message: '$e')),
        onDone: _onServerClosed,
      );
      state = state.copyWith(
        phase: WatchPhase.starting,
        sessionId: info.sessionId,
        hlsUrl: info.hlsUrl,
        clock: state.clock.copyWith(delayS: info.delayS),
        startedAt: DateTime.now(),
        restoreGuide: state.route.result?.restoreGuide,
      );
    } catch (e) {
      await _teardown();
      _fail(_toError(e));
    }
  }

  Future<void> stop() async {
    if (state.phase == WatchPhase.draining) {
      _finishDrain();
      return;
    }
    if (!state.isLive) return;
    state = state.copyWith(phase: WatchPhase.stopping);
    try {
      await _client?.stop();
    } finally {
      await _teardown();
      if (state.phase == WatchPhase.stopping) {
        state = state.copyWith(
          phase: WatchPhase.ended,
          endedAt: DateTime.now(),
          transcript: state.transcript.ended(),
        );
      }
    }
  }

  /// 오류·종료 화면에서 같은 설정으로 다시 시작.
  Future<void> retry() async {
    _drainTimer?.cancel();
    await _teardown();
    state = state.copyWith(phase: WatchPhase.idle);
    await start();
  }

  /// 플레이어 화면을 닫을 때. 실행 중이면 정지까지 한다.
  Future<void> leave() async {
    if (state.isLive) await stop();
    _drainTimer?.cancel();
    await _teardown();
    state = state.copyWith(phase: WatchPhase.idle, clearError: true, clearDrain: true);
  }

  /// 플레이어가 플레이리스트 끝(ENDLIST)에 닿았다 — 남은 지연분 재생 끝 (S-31).
  void onHlsEnded() {
    if (state.phase == WatchPhase.draining) _finishDrain();
  }

  void _finishDrain() {
    _drainTimer?.cancel();
    _drainTimer = null;
    if (state.phase != WatchPhase.draining) return;
    state = state.copyWith(
      phase: WatchPhase.ended,
      endedAt: DateTime.now(),
      transcript: state.transcript.ended(),
    );
  }

  void _onEvent(ServerEvent event) {
    final now = DateTime.now().millisecondsSinceEpoch;
    var next = state.copyWith(
      clock: state.clock.observe(event, now),
      transcript: reduceTranscript(state.transcript, event),
    );
    switch (event.payload) {
      case SessionStatePayload p:
        var phase = WatchPhase.fromServer(p.state);
        // 입력이 정상 종료(E_INPUT_ENDED)된 뒤의 stopped: 서버 세션은 끝났지만 HLS 에 D 초가 남아 있으니
        // 종료 화면 대신 플레이어를 유지한다 (S-31). 사용자가 직접 정지한 경우는 그냥 끝.
        final drain = phase == WatchPhase.ended &&
            state.inputEnded &&
            state.phase != WatchPhase.stopping;
        if (drain) {
          phase = WatchPhase.draining;
          final until = WatchState.drainDeadline(now, state.delayS ?? p.delayS);
          _drainTimer?.cancel();
          _drainTimer = Timer(Duration(milliseconds: until - now), _finishDrain);
          next = next.copyWith(drainUntilMs: until);
        }
        next = next.copyWith(
          phase: phase == WatchPhase.ended && state.phase == WatchPhase.stopping ? null : phase,
          clock: next.clock.copyWith(
            delayS: p.delayS,
            playStartWallMs: p.playStartWallMs,
          ),
          endedAt: phase == WatchPhase.ended ? DateTime.now() : null,
        );
      case DeadlineEventPayload p:
        next = next.copyWith(
          deadlines: state.deadlines.add(p),
          warning: p.level == 'L3' ? '문장 하나가 늦어 재생에 못 실렸습니다 (+${p.lateMs} ms)' : null,
          warningSeq: p.level == 'L3' ? state.warningSeq + 1 : null,
        );
      case MetricsPayload p:
        next = next.copyWith(metrics: p);
      case ErrorPayload p when p.code == 'E_INPUT_ENDED':
        // 입력 정상 종료 (S-31): 오류가 아니다. 곧 stopped 가 오면 draining 으로.
        next = next.copyWith(
          inputEnded: true,
          warning: describeRecoverable(p),
          warningSeq: state.warningSeq + 1,
        );
      case ErrorPayload p when p.recoverable:
        next = next.copyWith(warning: describeRecoverable(p), warningSeq: state.warningSeq + 1);
      case ErrorPayload p:
        state = next;
        _fail(WatchError(code: p.code, message: p.message));
        unawaited(_teardown());
        return;
      default:
        break;
    }
    state = next;
  }

  void _onServerClosed() {
    if (state.isLive && _client?.isStopping != true) {
      _fail(const WatchError(code: 'E_CONNECTION_LOST', message: '서버가 연결을 끊었습니다'));
      unawaited(_teardown());
    }
  }

  void _fail(WatchError error) {
    state = state.copyWith(
      phase: WatchPhase.error,
      error: error,
      endedAt: DateTime.now(),
      transcript: state.transcript.ended(),
    );
  }

  Future<void> _teardown() async {
    await _sub?.cancel();
    _sub = null;
    final client = _client;
    _client = null;
    await client?.abort();
  }

  static bool _isUnsupported(ApiException e) =>
      e.statusCode == 404 || e.statusCode == 501 || e.code == 'E_NOT_IMPLEMENTED';

  static WatchError _toError(Object e) {
    if (e is ApiException) {
      if (_isUnsupported(e)) {
        return WatchError(code: 'E_NOT_IMPLEMENTED', message: e.message);
      }
      final engine = describeEngineError(e);
      if (engine != null) return WatchError(code: e.code!, message: engine);
      return WatchError(code: e.code ?? 'HTTP ${e.statusCode}', message: e.message);
    }
    if (e is TimeoutException) {
      return const WatchError(code: 'E_TIMEOUT', message: '서버 응답 시간 초과');
    }
    return WatchError(code: 'E_CONNECTION_LOST', message: '$e');
  }

  static String _describe(Object e) {
    if (e is ApiException) return '서버 응답 오류: $e';
    if (e is TimeoutException) return '서버 응답 시간 초과';
    return '연결 실패: $e';
  }
}

final watchControllerProvider =
    NotifierProvider<WatchController, WatchState>(WatchController.new);

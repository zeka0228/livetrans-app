import '../../core/models/session.dart';

/// 모드 A 입력 종류.
enum WatchSourceKind {
  /// 격리 장치의 소리만 서버가 loopback 캡처. 영상 없음 (지금 서버가 지원하는 경로에 가장 가깝다).
  audioOnly,

  /// OBS 가 창 영상 + 격리 장치 소리를 SRT 로 보내고 서버가 받는다 (명세 §4.1 `obs_stream`).
  obs,
}

/// 세션 시작 화면에서 고르는 값. 시작 후에는 바뀌지 않는다 (I3: D 는 세션 동안 고정).
class WatchSettings {
  const WatchSettings({
    this.sourceKind = WatchSourceKind.audioOnly,
    this.obsUrl = 'srt://127.0.0.1:9000?mode=listener',
    this.srcLang = 'ja',
    this.tgtLang = 'ko',
    this.autoDelay = true,
    this.manualDelayS = 36,
    this.ttsEnabled = true,
    this.showOriginal = true,
    this.showSpeaker = true,
    this.enhance = true,
    this.diarize = true,
    this.router = 'spare_device',
    this.isolationDeviceId,
  });

  final WatchSourceKind sourceKind;
  final String obsUrl;
  final String srcLang;
  final String tgtLang;

  /// true 면 `delay_s: null` 로 보내 서버 권장값(calibrate)을 쓴다.
  final bool autoDelay;
  final int manualDelayS;
  final bool ttsEnabled;
  final bool showOriginal;
  final bool showSpeaker;
  final bool enhance;
  final bool diarize;
  final String router;

  /// `device:<id>`. null 이면 `route` 를 보내지 않는다 (격리 미지원 서버·가짜 서버).
  final String? isolationDeviceId;

  static const minDelayS = 5;
  static const maxDelayS = 90;

  int? get requestedDelayS => autoDelay ? null : manualDelayS;

  SessionRequest toRequest() {
    final (type, params) = switch (sourceKind) {
      WatchSourceKind.obs => ('obs_stream', <String, dynamic>{'url': obsUrl}),
      WatchSourceKind.audioOnly => (
          'loopback',
          <String, dynamic>{
            if (isolationDeviceId != null) 'target': isolationDeviceId,
          },
        ),
    };
    return SessionRequest.watch(
      sourceType: type,
      sourceParams: params,
      srcLang: srcLang,
      tgtLang: tgtLang,
      delayS: requestedDelayS,
      ttsEnabled: ttsEnabled,
      showOriginal: showOriginal,
      showSpeaker: showSpeaker,
      router: isolationDeviceId == null ? null : router,
      isolationDevice: isolationDeviceId,
      enhance: enhance,
      diarize: diarize,
    );
  }

  WatchSettings copyWith({
    WatchSourceKind? sourceKind,
    String? obsUrl,
    String? srcLang,
    String? tgtLang,
    bool? autoDelay,
    int? manualDelayS,
    bool? ttsEnabled,
    bool? showOriginal,
    bool? showSpeaker,
    bool? enhance,
    bool? diarize,
    String? router,
    String? isolationDeviceId,
    bool clearIsolationDevice = false,
  }) =>
      WatchSettings(
        sourceKind: sourceKind ?? this.sourceKind,
        obsUrl: obsUrl ?? this.obsUrl,
        srcLang: srcLang ?? this.srcLang,
        tgtLang: tgtLang ?? this.tgtLang,
        autoDelay: autoDelay ?? this.autoDelay,
        manualDelayS: manualDelayS ?? this.manualDelayS,
        ttsEnabled: ttsEnabled ?? this.ttsEnabled,
        showOriginal: showOriginal ?? this.showOriginal,
        showSpeaker: showSpeaker ?? this.showSpeaker,
        enhance: enhance ?? this.enhance,
        diarize: diarize ?? this.diarize,
        router: router ?? this.router,
        isolationDeviceId: clearIsolationDevice
            ? null
            : (isolationDeviceId ?? this.isolationDeviceId),
      );
}

const watchTargetLanguages = <String, String>{
  'ko': '한국어',
  'en': '영어',
  'ja': '일본어',
};

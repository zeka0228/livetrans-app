/// 기술 명세서 §6.1 REST 요청·응답.
class SessionRequest {
  const SessionRequest({
    required this.mode,
    required this.sourceType,
    this.sourceParams = const {},
    required this.srcLang,
    required this.tgtLang,
    this.delayS,
    this.ttsEnabled = false,
    this.voiceRef,
    this.duckDb = -12,
    this.showOriginal = true,
    this.showSpeaker,
    this.route,
    this.audio,
  });

  final String mode;
  final String sourceType;
  final Map<String, dynamic> sourceParams;
  final String srcLang;
  final String tgtLang;
  final int? delayS;
  final bool ttsEnabled;
  final String? voiceRef;
  final int duckDb;
  final bool showOriginal;

  /// 명세 v0.4 `display.show_speaker`. null 이면 보내지 않는다 (모드 B·C 요청은 예전 그대로).
  final bool? showSpeaker;

  /// 명세 v0.5 `route` — 모드 A 원본 소리 격리 (`{"router", "isolation_device"}`). null 이면 보내지 않는다.
  final Map<String, dynamic>? route;

  /// 명세 v0.4 `audio` — `{"enhance", "diarize", "game_dialogue"}`. null 이면 보내지 않는다.
  final Map<String, dynamic>? audio;

  /// 모드 C — 앱 마이크 PCM 을 WS 로 보낸다.
  factory SessionRequest.mic({required String srcLang, String tgtLang = 'ko'}) =>
      SessionRequest(
        mode: 'C',
        sourceType: 'mic_ws',
        srcLang: srcLang,
        tgtLang: tgtLang,
      );

  /// 모드 B — 서버가 PC 의 창·프로세스 소리를 캡처한다 (API 계약 S-9 ②). 앱은 오디오를 보내지 않는다.
  factory SessionRequest.broadcast({
    required String target,
    required String srcLang,
    String tgtLang = 'ko',
  }) =>
      SessionRequest(
        mode: 'B',
        sourceType: 'loopback',
        sourceParams: {'target': target},
        srcLang: srcLang,
        tgtLang: tgtLang,
      );

  /// 모드 A — 동기 시청 (명세 §6.1 v0.5). 서버가 캡처·지연·합성을 모두 하고 앱은 재생한다.
  ///
  /// [sourceType] 은 `obs_stream`(OBS → SRT) 또는 `loopback`(격리 장치 소리만, 영상 없음).
  /// [delayS] 가 null 이면 서버가 calibrate 결과(권장 D)를 쓴다.
  factory SessionRequest.watch({
    required String sourceType,
    required Map<String, dynamic> sourceParams,
    required String srcLang,
    required String tgtLang,
    int? delayS,
    required bool ttsEnabled,
    bool showOriginal = true,
    bool showSpeaker = true,
    String? router,
    String? isolationDevice,
    bool enhance = true,
    bool diarize = true,
  }) =>
      SessionRequest(
        mode: 'A',
        sourceType: sourceType,
        sourceParams: sourceParams,
        srcLang: srcLang,
        tgtLang: tgtLang,
        delayS: delayS,
        ttsEnabled: ttsEnabled,
        showOriginal: showOriginal,
        showSpeaker: showSpeaker,
        route: router == null
            ? null
            : {'router': router, 'isolation_device': isolationDevice},
        audio: {'enhance': enhance, 'diarize': diarize, 'game_dialogue': 'keep'},
      );

  Map<String, dynamic> toJson() => {
        'mode': mode,
        'source': {'type': sourceType, 'params': sourceParams},
        'src_lang': srcLang,
        'tgt_lang': tgtLang,
        'delay_s': delayS,
        if (route != null) 'route': route,
        if (audio != null) 'audio': audio,
        'tts': {
          'enabled': ttsEnabled,
          'voice_ref': voiceRef,
          'duck_db': duckDb,
        },
        'display': {
          'show_original': showOriginal,
          if (showSpeaker != null) 'show_speaker': showSpeaker,
        },
      };
}

class SessionInfo {
  const SessionInfo({
    required this.sessionId,
    required this.delayS,
    required this.hlsUrl,
    required this.wsUrl,
  });

  final String sessionId;
  final int? delayS;
  final String? hlsUrl;
  final String wsUrl;

  factory SessionInfo.fromJson(Map<String, dynamic> j) {
    final id = j['session_id'].toString();
    return SessionInfo(
      sessionId: id,
      delayS: (j['delay_s'] as num?)?.toInt(),
      hlsUrl: j['hls_url'] as String?,
      wsUrl: j['ws_url'] as String? ?? '/ws/sessions/$id',
    );
  }
}

class HealthInfo {
  const HealthInfo({
    required this.status,
    this.gpuName,
    this.memTotalMb,
    this.memUsedMb,
    this.modelsLoaded = const [],
  });

  final String status;
  final String? gpuName;
  final int? memTotalMb;
  final int? memUsedMb;
  final List<String> modelsLoaded;

  factory HealthInfo.fromJson(Map<String, dynamic> j) {
    final gpu = (j['gpu'] as Map?)?.cast<String, dynamic>();
    return HealthInfo(
      status: j['status']?.toString() ?? 'unknown',
      gpuName: gpu?['name'] as String?,
      memTotalMb: (gpu?['mem_total_mb'] as num?)?.toInt(),
      memUsedMb: (gpu?['mem_used_mb'] as num?)?.toInt(),
      modelsLoaded:
          (j['models_loaded'] as List?)?.map((e) => e.toString()).toList() ??
              const [],
    );
  }
}

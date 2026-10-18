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

  Map<String, dynamic> toJson() => {
        'mode': mode,
        'source': {'type': sourceType, 'params': sourceParams},
        'src_lang': srcLang,
        'tgt_lang': tgtLang,
        'delay_s': delayS,
        'tts': {
          'enabled': ttsEnabled,
          'voice_ref': voiceRef,
          'duck_db': duckDb,
        },
        'display': {'show_original': showOriginal},
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

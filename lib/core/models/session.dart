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

  factory SessionRequest.mic({required String srcLang, String tgtLang = 'ko'}) =>
      SessionRequest(
        mode: 'C',
        sourceType: 'mic_ws',
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

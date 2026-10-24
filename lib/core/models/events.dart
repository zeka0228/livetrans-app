import 'dart:convert';

/// 기술 명세서 §6.2 WebSocket 이벤트. 서버 스키마가 바뀌면 같은 PR에서 함께 고친다.
class ServerEvent {
  const ServerEvent({
    required this.v,
    required this.type,
    required this.seq,
    required this.sessionId,
    required this.tsWallMs,
    required this.payload,
  });

  final int v;
  final String type;
  final int seq;
  final String sessionId;
  final int tsWallMs;
  final ServerPayload payload;

  static ServerEvent parse(String raw) =>
      ServerEvent.fromJson(jsonDecode(raw) as Map<String, dynamic>);

  factory ServerEvent.fromJson(Map<String, dynamic> json) {
    final type = asString(json['type']);
    final body = (json['payload'] as Map?)?.cast<String, dynamic>() ?? const {};
    return ServerEvent(
      v: asInt(json['v'], fallback: 1),
      type: type,
      seq: asInt(json['seq']),
      sessionId: asString(json['session_id']),
      tsWallMs: asInt(json['ts_wall_ms']),
      payload: ServerPayload.fromType(type, body),
    );
  }
}

sealed class ServerPayload {
  const ServerPayload();

  static ServerPayload fromType(String type, Map<String, dynamic> p) {
    return switch (type) {
      'session.state' => SessionStatePayload.fromJson(p),
      'segment.partial' => SegmentPartialPayload.fromJson(p),
      'segment.final' => SegmentFinalPayload.fromJson(p),
      'translation.final' => TranslationFinalPayload.fromJson(p),
      'segment.update' => RevisionPayload.fromJson(RevisionKind.segment, p),
      'translation.update' => RevisionPayload.fromJson(RevisionKind.translation, p),
      'tts.ready' => TtsReadyPayload.fromJson(p),
      'deadline.event' => DeadlineEventPayload.fromJson(p),
      'metrics' => MetricsPayload.fromJson(p),
      'error' => ErrorPayload.fromJson(p),
      _ => UnknownPayload(type, p),
    };
  }
}

class SessionStatePayload extends ServerPayload {
  const SessionStatePayload({
    required this.state,
    this.delayS,
    this.playStartWallMs,
  });

  final String state;
  final int? delayS;
  final int? playStartWallMs;

  factory SessionStatePayload.fromJson(Map<String, dynamic> p) =>
      SessionStatePayload(
        state: asString(p['state']),
        delayS: asIntOrNull(p['delay_s']),
        playStartWallMs: asIntOrNull(p['play_start_wall_ms']),
      );
}

class SegmentPartialPayload extends ServerPayload {
  const SegmentPartialPayload({
    required this.segId,
    required this.tStartMs,
    required this.text,
    required this.lang,
    this.speaker,
  });

  final int segId;
  final int tStartMs;
  final String text;
  final String lang;

  /// 화자 레인 모드(S-19 ②)에서는 partial 에도 화자가 붙는다. 없으면 null.
  final String? speaker;

  factory SegmentPartialPayload.fromJson(Map<String, dynamic> p) =>
      SegmentPartialPayload(
        segId: asInt(p['seg_id']),
        tStartMs: asInt(p['t_start_ms']),
        text: asString(p['text']),
        lang: asString(p['lang']),
        speaker: asStringOrNull(p['speaker']),
      );
}

class WordTiming {
  const WordTiming({required this.w, required this.t0Ms, required this.t1Ms});

  final String w;
  final int t0Ms;
  final int t1Ms;

  factory WordTiming.fromJson(Map<String, dynamic> p) => WordTiming(
        w: asString(p['w']),
        t0Ms: asInt(p['t0_ms']),
        t1Ms: asInt(p['t1_ms']),
      );
}

class SegmentFinalPayload extends ServerPayload {
  const SegmentFinalPayload({
    required this.segId,
    required this.tStartMs,
    required this.tEndMs,
    required this.text,
    required this.lang,
    required this.langProb,
    required this.words,
    required this.forcedCut,
    required this.sttMs,
    this.speaker,
  });

  final int segId;
  final int tStartMs;
  final int tEndMs;
  final String text;
  final String lang;
  final double langProb;
  final List<WordTiming> words;
  final bool forcedCut;
  final int sttMs;

  /// 명세 v0.4 §6.2 — 화자 분할이 켜지면 `"S0"` 같은 세션 내 익명 ID. 없으면 null.
  /// 한 구간에 화자가 둘이면 같은 seg_id 로 final 이 화자마다 1개씩 온다 → 키는 (seg_id, speaker).
  final String? speaker;

  factory SegmentFinalPayload.fromJson(Map<String, dynamic> p) =>
      SegmentFinalPayload(
        segId: asInt(p['seg_id']),
        tStartMs: asInt(p['t_start_ms']),
        tEndMs: asInt(p['t_end_ms']),
        text: asString(p['text']),
        lang: asString(p['lang']),
        langProb: asDouble(p['lang_prob']),
        words: (p['words'] as List?)
                ?.map((e) => WordTiming.fromJson((e as Map).cast()))
                .toList() ??
            const [],
        forcedCut: p['forced_cut'] == true,
        sttMs: asInt(p['stt_ms']),
        speaker: asStringOrNull(p['speaker']),
      );
}

class TranslationFinalPayload extends ServerPayload {
  const TranslationFinalPayload({
    required this.segId,
    required this.text,
    required this.srcLang,
    required this.tgtLang,
    required this.engine,
    required this.fallback,
    required this.mtMs,
    this.speaker,
  });

  final int segId;
  final String text;
  final String srcLang;
  final String tgtLang;
  final String engine;
  final bool fallback;
  final int mtMs;
  final String? speaker;

  factory TranslationFinalPayload.fromJson(Map<String, dynamic> p) =>
      TranslationFinalPayload(
        segId: asInt(p['seg_id']),
        text: asString(p['text']),
        srcLang: asString(p['src_lang']),
        tgtLang: asString(p['tgt_lang']),
        engine: asString(p['engine']),
        fallback: p['fallback'] == true,
        mtMs: asInt(p['mt_ms']),
        speaker: asStringOrNull(p['speaker']),
      );
}

/// API 계약 S-28 2차 패스 — 뒤 문맥이 온 뒤 서버가 이미 낸 줄을 고쳐 보낸다.
enum RevisionKind {
  /// `segment.update`: 원문 줄 교체 (STT 오류 교정).
  segment,

  /// `translation.update`: 번역 줄 교체.
  translation,
}

/// `segment.update` / `translation.update` `{seg_id, speaker?, text, prev_text, reason}` (S-28).
/// (seg_id, speaker) 키로 기록의 줄을 찾아 [text] 로 바꾼다. 발화당 최대 1회, 달라진 것만 온다.
class RevisionPayload extends ServerPayload {
  const RevisionPayload({
    required this.kind,
    required this.segId,
    required this.text,
    this.prevText,
    this.reason,
    this.speaker,
  });

  final RevisionKind kind;
  final int segId;
  final String text;
  final String? prevText;

  /// 지금은 `context`(앞뒤 문맥) 뿐.
  final String? reason;
  final String? speaker;

  factory RevisionPayload.fromJson(RevisionKind kind, Map<String, dynamic> p) => RevisionPayload(
        kind: kind,
        segId: asInt(p['seg_id']),
        text: asString(p['text']),
        prevText: asStringOrNull(p['prev_text']),
        reason: asStringOrNull(p['reason']),
        speaker: asStringOrNull(p['speaker']),
      );
}

class TtsReadyPayload extends ServerPayload {
  const TtsReadyPayload({
    required this.segId,
    required this.durationMs,
    required this.rate,
    required this.voiceRef,
    required this.ttsMs,
    this.audioUrl,
    this.speaker,
  });

  final int segId;
  final int durationMs;
  final double rate;
  final String voiceRef;
  final int ttsMs;

  /// 모드 A 서버 TTS 는 HLS 오디오에 믹스되므로 null (S-21 ④). 모드 B 는 앱이 재생할 URL.
  final String? audioUrl;

  /// 화자 레인 (S-21 ④ `speaker?`). 없으면 null.
  final String? speaker;

  factory TtsReadyPayload.fromJson(Map<String, dynamic> p) => TtsReadyPayload(
        segId: asInt(p['seg_id']),
        durationMs: asInt(p['duration_ms']),
        rate: asDouble(p['rate'], fallback: 1.0),
        voiceRef: asString(p['voice_ref']),
        ttsMs: asInt(p['tts_ms']),
        audioUrl: p['audio_url'] as String?,
        speaker: asStringOrNull(p['speaker']),
      );
}

class DeadlineEventPayload extends ServerPayload {
  const DeadlineEventPayload({
    required this.segId,
    required this.kind,
    required this.level,
    required this.lateMs,
  });

  final int segId;
  final String kind;
  final String level;
  final int lateMs;

  factory DeadlineEventPayload.fromJson(Map<String, dynamic> p) =>
      DeadlineEventPayload(
        segId: asInt(p['seg_id']),
        kind: asString(p['kind']),
        level: asString(p['level']),
        lateMs: asInt(p['late_ms']),
      );
}

class MetricsPayload extends ServerPayload {
  const MetricsPayload({
    required this.p50Ms,
    required this.p99Ms,
    required this.missRate,
    required this.queueDepth,
    required this.gpuMemUsedMb,
    this.gpuUtilStream,
  });

  final Map<String, int> p50Ms;
  final Map<String, int> p99Ms;
  final double missRate;
  final int queueDepth;
  final int gpuMemUsedMb;

  /// 명세 v0.4 — 분리·화자 분할 같은 상시 단계의 평균 GPU 점유율 (0~1). 없으면 null.
  final double? gpuUtilStream;

  factory MetricsPayload.fromJson(Map<String, dynamic> p) => MetricsPayload(
        p50Ms: _intMap(p['p50_ms']),
        p99Ms: _intMap(p['p99_ms']),
        missRate: asDouble(p['miss_rate']),
        queueDepth: asInt(p['queue_depth']),
        gpuMemUsedMb: asInt(p['gpu_mem_used_mb']),
        gpuUtilStream: p['gpu_util_stream'] == null
            ? null
            : asDouble(p['gpu_util_stream']),
      );

  static Map<String, int> _intMap(Object? v) {
    if (v is! Map) return const {};
    return v.map((k, val) => MapEntry(k.toString(), asInt(val)));
  }
}

class ErrorPayload extends ServerPayload {
  const ErrorPayload({
    required this.code,
    required this.message,
    required this.recoverable,
  });

  final String code;
  final String message;
  final bool recoverable;

  factory ErrorPayload.fromJson(Map<String, dynamic> p) => ErrorPayload(
        code: asString(p['code']),
        message: asString(p['message']),
        recoverable: p['recoverable'] == true,
      );
}

class UnknownPayload extends ServerPayload {
  const UnknownPayload(this.type, this.raw);

  final String type;
  final Map<String, dynamic> raw;
}

/// 클라이언트 → 서버 텍스트 메시지 (§6.2).
class ClientMessage {
  static String control(String action) => jsonEncode({
        'type': 'control',
        'payload': {'action': action},
      });

  static String configUpdate(Map<String, dynamic> payload) =>
      jsonEncode({'type': 'config.update', 'payload': payload});
}

int asInt(Object? v, {int fallback = 0}) {
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v) ?? fallback;
  return fallback;
}

int? asIntOrNull(Object? v) => v == null ? null : asInt(v);

double asDouble(Object? v, {double fallback = 0}) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v) ?? fallback;
  return fallback;
}

String asString(Object? v) => v?.toString() ?? '';

String? asStringOrNull(Object? v) {
  if (v == null) return null;
  final s = v.toString();
  return s.isEmpty ? null : s;
}

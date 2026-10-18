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
  });

  final int segId;
  final int tStartMs;
  final String text;
  final String lang;

  factory SegmentPartialPayload.fromJson(Map<String, dynamic> p) =>
      SegmentPartialPayload(
        segId: asInt(p['seg_id']),
        tStartMs: asInt(p['t_start_ms']),
        text: asString(p['text']),
        lang: asString(p['lang']),
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
  });

  final int segId;
  final String text;
  final String srcLang;
  final String tgtLang;
  final String engine;
  final bool fallback;
  final int mtMs;

  factory TranslationFinalPayload.fromJson(Map<String, dynamic> p) =>
      TranslationFinalPayload(
        segId: asInt(p['seg_id']),
        text: asString(p['text']),
        srcLang: asString(p['src_lang']),
        tgtLang: asString(p['tgt_lang']),
        engine: asString(p['engine']),
        fallback: p['fallback'] == true,
        mtMs: asInt(p['mt_ms']),
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
  });

  final int segId;
  final int durationMs;
  final double rate;
  final String voiceRef;
  final int ttsMs;
  final String? audioUrl;

  factory TtsReadyPayload.fromJson(Map<String, dynamic> p) => TtsReadyPayload(
        segId: asInt(p['seg_id']),
        durationMs: asInt(p['duration_ms']),
        rate: asDouble(p['rate'], fallback: 1.0),
        voiceRef: asString(p['voice_ref']),
        ttsMs: asInt(p['tts_ms']),
        audioUrl: p['audio_url'] as String?,
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
  });

  final Map<String, int> p50Ms;
  final Map<String, int> p99Ms;
  final double missRate;
  final int queueDepth;
  final int gpuMemUsedMb;

  factory MetricsPayload.fromJson(Map<String, dynamic> p) => MetricsPayload(
        p50Ms: _intMap(p['p50_ms']),
        p99Ms: _intMap(p['p99_ms']),
        missRate: asDouble(p['miss_rate']),
        queueDepth: asInt(p['queue_depth']),
        gpuMemUsedMb: asInt(p['gpu_mem_used_mb']),
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

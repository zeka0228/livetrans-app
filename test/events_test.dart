import 'package:flutter_test/flutter_test.dart';
import 'package:livetrans_app/core/models/events.dart';

void main() {
  group('ServerEvent.parse', () {
    test('segment.final 봉투와 단어 타임스탬프를 파싱한다', () {
      const raw = '''
      {"v":1,"type":"segment.final","seq":42,"session_id":"s1","ts_wall_ms":1792300000000,
       "payload":{"seg_id":7,"t_start_ms":1200,"t_end_ms":3400,"text":"こんにちは","lang":"ja",
                  "lang_prob":0.97,"words":[{"w":"こんにちは","t0_ms":1200,"t1_ms":3400}],
                  "forced_cut":false,"stt_ms":830}}''';
      final ev = ServerEvent.parse(raw);
      expect(ev.v, 1);
      expect(ev.type, 'segment.final');
      expect(ev.seq, 42);
      expect(ev.sessionId, 's1');
      final p = ev.payload as SegmentFinalPayload;
      expect(p.segId, 7);
      expect(p.tStartMs, 1200);
      expect(p.tEndMs, 3400);
      expect(p.text, 'こんにちは');
      expect(p.lang, 'ja');
      expect(p.langProb, closeTo(0.97, 1e-9));
      expect(p.words.single.w, 'こんにちは');
      expect(p.forcedCut, isFalse);
      expect(p.sttMs, 830);
    });

    test('S-17: segment.final 의 speaker 를 읽고, 없거나 비면 null 이다', () {
      final withSpeaker = ServerEvent.fromJson({
        'v': 1, 'type': 'segment.final', 'seq': 1, 'session_id': 's', 'ts_wall_ms': 0,
        'payload': {'seg_id': 4, 't_start_ms': 0, 't_end_ms': 900, 'text': 'hello', 'lang': 'en',
          'lang_prob': 0.99, 'words': [], 'forced_cut': false, 'stt_ms': 200, 'speaker': 'S1', 'diar_ms': 40},
      }).payload as SegmentFinalPayload;
      expect(withSpeaker.speaker, 'S1');
      expect(withSpeaker.words, isEmpty);

      final without = ServerEvent.fromJson({
        'v': 1, 'type': 'segment.final', 'seq': 2, 'session_id': 's', 'ts_wall_ms': 0,
        'payload': {'seg_id': 5, 't_start_ms': 0, 't_end_ms': 900, 'text': 'x', 'lang': 'en',
          'lang_prob': 0.9, 'words': [], 'forced_cut': false, 'stt_ms': 1, 'speaker': ''},
      }).payload as SegmentFinalPayload;
      expect(without.speaker, isNull);
    });

    test('S-19: segment.partial 의 speaker 를 읽는다', () {
      final p = ServerEvent.fromJson({
        'v': 1, 'type': 'segment.partial', 'seq': 3, 'session_id': 's', 'ts_wall_ms': 0,
        'payload': {'seg_id': 12, 't_start_ms': 500, 'text': 'hel', 'lang': 'en', 'speaker': 'S1'},
      }).payload as SegmentPartialPayload;
      expect(p.speaker, 'S1');
    });

    test('segment.partial을 파싱한다', () {
      final ev = ServerEvent.parse(
        '{"v":1,"type":"segment.partial","seq":1,"session_id":"s","ts_wall_ms":0,'
        '"payload":{"seg_id":3,"t_start_ms":500,"text":"안녕","lang":"ko"}}',
      );
      final p = ev.payload as SegmentPartialPayload;
      expect(p.segId, 3);
      expect(p.text, '안녕');
    });

    test('session.state의 선택 필드가 없어도 파싱한다', () {
      final ev = ServerEvent.parse(
        '{"v":1,"type":"session.state","seq":0,"session_id":"s","ts_wall_ms":0,'
        '"payload":{"state":"starting"}}',
      );
      final p = ev.payload as SessionStatePayload;
      expect(p.state, 'starting');
      expect(p.delayS, isNull);
    });

    test('모르는 type은 UnknownPayload로 남기고 예외를 내지 않는다', () {
      final ev = ServerEvent.parse(
        '{"v":2,"type":"future.thing","seq":9,"session_id":"s","ts_wall_ms":0,"payload":{"x":1}}',
      );
      expect(ev.payload, isA<UnknownPayload>());
      expect((ev.payload as UnknownPayload).raw['x'], 1);
    });

    test('error 이벤트를 파싱한다', () {
      final ev = ServerEvent.parse(
        '{"v":1,"type":"error","seq":1,"session_id":"s","ts_wall_ms":0,'
        '"payload":{"code":"E_STT","message":"boom","recoverable":true}}',
      );
      final p = ev.payload as ErrorPayload;
      expect(p.code, 'E_STT');
      expect(p.recoverable, isTrue);
    });
  });

  group('모드 A 이벤트 (API 계약 S-21 ④)', () {
    test('tts.ready: audio_url null·speaker 를 읽는다', () {
      final ev = ServerEvent.fromJson({
        'v': 1, 'type': 'tts.ready', 'seq': 3, 'session_id': 's1', 'ts_wall_ms': 1,
        'payload': {'seg_id': 9, 'duration_ms': 1800, 'rate': 1.02, 'voice_ref': 'system:Heami',
                    'tts_ms': 320, 'audio_url': null, 'speaker': 'S1'},
      });
      final p = ev.payload as TtsReadyPayload;
      expect(p.segId, 9);
      expect(p.durationMs, 1800);
      expect(p.rate, closeTo(1.02, 1e-9));
      expect(p.audioUrl, isNull);
      expect(p.speaker, 'S1');
    });

    test('tts.ready: speaker 가 없거나 비면 null (모드 B 호환)', () {
      final ev = ServerEvent.fromJson({
        'v': 1, 'type': 'tts.ready', 'seq': 4, 'session_id': 's1', 'ts_wall_ms': 1,
        'payload': {'seg_id': 1, 'duration_ms': 500, 'rate': 1.0, 'voice_ref': 'system:Zira',
                    'tts_ms': 100, 'audio_url': '/api/tts/1.wav', 'speaker': ''},
      });
      final p = ev.payload as TtsReadyPayload;
      expect(p.audioUrl, '/api/tts/1.wav');
      expect(p.speaker, isNull);
    });

    test('metrics: p50_ms.diar 등 단계별 값과 gpu_util_stream 을 읽는다', () {
      final ev = ServerEvent.fromJson({
        'v': 1, 'type': 'metrics', 'seq': 5, 'session_id': 's1', 'ts_wall_ms': 1,
        'payload': {'p50_ms': {'stt': 800, 'mt': 1200, 'tts': 300, 'diar': 40},
                    'p99_ms': {'stt': 1500, 'mt': 2500, 'tts': 600, 'diar': 90},
                    'gpu_util_stream': 0.35, 'miss_rate': 0.02, 'queue_depth': 1, 'gpu_mem_used_mb': 12600},
      });
      final p = ev.payload as MetricsPayload;
      expect(p.p50Ms['diar'], 40);
      expect(p.p99Ms['mt'], 2500);
      expect(p.gpuUtilStream, closeTo(0.35, 1e-9));
      expect(p.missRate, closeTo(0.02, 1e-9));
      expect(p.gpuMemUsedMb, 12600);
    });

    test('deadline.event: L2/L3 와 late_ms', () {
      final ev = ServerEvent.fromJson({
        'v': 1, 'type': 'deadline.event', 'seq': 6, 'session_id': 's1', 'ts_wall_ms': 1,
        'payload': {'seg_id': 2, 'kind': 'tts', 'level': 'L2', 'late_ms': 1400},
      });
      final p = ev.payload as DeadlineEventPayload;
      expect(p.kind, 'tts');
      expect(p.level, 'L2');
      expect(p.lateMs, 1400);
    });
  });

  group('2차 패스 갱신 이벤트 (API 계약 S-28)', () {
    test('translation.update → RevisionPayload(translation)', () {
      final e = ServerEvent.fromJson({
        'v': 1, 'type': 'translation.update', 'seq': 9, 'session_id': 's', 'ts_wall_ms': 0,
        'payload': {'seg_id': 3, 'speaker': 'S1', 'text': '아니 다른 열쇠 말이야', 'prev_text': '다른 거', 'reason': 'context'},
      });
      final p = e.payload as RevisionPayload;
      expect(p.kind, RevisionKind.translation);
      expect(p.segId, 3);
      expect(p.speaker, 'S1');
      expect(p.text, '아니 다른 열쇠 말이야');
      expect(p.prevText, '다른 거');
      expect(p.reason, 'context');
    });

    test('segment.update → RevisionPayload(segment), speaker 없으면 null', () {
      final e = ServerEvent.fromJson({
        'v': 1, 'type': 'segment.update', 'seq': 9, 'session_id': 's', 'ts_wall_ms': 0,
        'payload': {'seg_id': 4, 'text': '볼래?', 'prev_text': '불레', 'reason': 'context'},
      });
      final p = e.payload as RevisionPayload;
      expect(p.kind, RevisionKind.segment);
      expect(p.speaker, isNull);
      expect(p.text, '볼래?');
    });
  });

  test('ClientMessage.control은 명세 형식의 JSON을 만든다', () {
    expect(
      ClientMessage.control('start'),
      '{"type":"control","payload":{"action":"start"}}',
    );
  });
}

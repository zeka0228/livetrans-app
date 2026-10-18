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

  test('ClientMessage.control은 명세 형식의 JSON을 만든다', () {
    expect(
      ClientMessage.control('start'),
      '{"type":"control","payload":{"action":"start"}}',
    );
  });
}

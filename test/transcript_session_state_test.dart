import 'package:flutter_test/flutter_test.dart';
import 'package:livetrans_app/core/models/events.dart';
import 'package:livetrans_app/features/transcript/transcript_session_state.dart';

ServerEvent _ev(String type, Map<String, dynamic> payload) => ServerEvent.fromJson({
      'v': 1,
      'type': type,
      'seq': 1,
      'session_id': 's',
      'ts_wall_ms': 0,
      'payload': payload,
    });

Map<String, dynamic> _partial(int segId, String text, {int tStart = 0, String? speaker}) => {
      'seg_id': segId,
      't_start_ms': tStart,
      'text': text,
      'lang': 'ko',
      'speaker': ?speaker,
    };

Map<String, dynamic> _final(int segId, String text, {int tStart = 0, String? speaker}) => {
      'seg_id': segId,
      't_start_ms': tStart,
      't_end_ms': tStart + 1000,
      'text': text,
      'lang': 'ko',
      'lang_prob': 0.9,
      'words': [],
      'forced_cut': false,
      'stt_ms': 100,
      'speaker': ?speaker,
    };

Map<String, dynamic> _translation(int segId, String text,
        {String? speaker, String engine = 'fake', bool fallback = false}) =>
    {
      'seg_id': segId,
      'text': text,
      'src_lang': 'ja',
      'tgt_lang': 'ko',
      'engine': engine,
      'fallback': fallback,
      'mt_ms': 5,
      'speaker': ?speaker,
    };

void main() {
  group('partial', () {
    test('화자가 없으면 seg_id 와 무관하게 하나만 유지하고 덮어쓴다', () {
      var s = const TranscriptSessionState();
      s = reduceTranscript(s, _ev('segment.partial', _partial(1, 'a')));
      s = reduceTranscript(s, _ev('segment.partial', _partial(2, 'ab')));
      expect(s.partials.single.text, 'ab');
      expect(s.partial!.text, 'ab');
      expect(s.entries, isEmpty);
    });

    test('S-19: 화자 레인마다 partial 하나씩, 같은 화자는 덮어쓴다', () {
      var s = const TranscriptSessionState();
      s = reduceTranscript(s, _ev('segment.partial', _partial(10, '안녕', tStart: 0, speaker: 'S0')));
      s = reduceTranscript(s, _ev('segment.partial', _partial(11, 'hel', tStart: 500, speaker: 'S1')));
      s = reduceTranscript(s, _ev('segment.partial', _partial(10, '안녕하세', tStart: 0, speaker: 'S0')));
      expect(s.partials.map((e) => '${e.speaker}:${e.text}'), ['S0:안녕하세', 'S1:hel']);
    });

    test('final 이 오면 같은 seg_id 또는 같은 화자의 partial 만 지운다', () {
      var s = const TranscriptSessionState();
      s = reduceTranscript(s, _ev('segment.partial', _partial(10, '안녕', speaker: 'S0')));
      s = reduceTranscript(s, _ev('segment.partial', _partial(11, 'hel', tStart: 500, speaker: 'S1')));
      s = reduceTranscript(s, _ev('segment.final', _final(10, '안녕하세요', speaker: 'S0')));
      expect(s.partials.single.speaker, 'S1');
      expect(s.entries.single.text, '안녕하세요');
    });
  });

  group('final', () {
    test('기록에 추가하고 같은 seg_id 의 partial 을 지운다', () {
      var s = const TranscriptSessionState();
      s = reduceTranscript(s, _ev('segment.partial', _partial(3, '중간')));
      s = reduceTranscript(s, _ev('segment.final', _final(3, '확정')));
      expect(s.partials, isEmpty);
      expect(s.entries.single.text, '확정');
      expect(s.entries.single.isFinal, isTrue);
    });

    test('S-2: 빈 final 은 기록에 넣지 않고 partial 만 지운다', () {
      var s = const TranscriptSessionState();
      s = reduceTranscript(s, _ev('segment.partial', _partial(4, '…')));
      s = reduceTranscript(s, _ev('segment.final', _final(4, '   ')));
      expect(s.partials, isEmpty);
      expect(s.entries, isEmpty);
    });

    test('S-19 ④: 레인끼리 seg_id 가 섞여 와도 기록은 t_start_ms 순서다', () {
      var s = const TranscriptSessionState();
      s = reduceTranscript(s, _ev('segment.final', _final(7, 'S1 늦게 끝난 긴 문장', tStart: 2000, speaker: 'S1')));
      s = reduceTranscript(s, _ev('segment.final', _final(8, 'S0 먼저 시작한 문장', tStart: 500, speaker: 'S0')));
      s = reduceTranscript(s, _ev('segment.final', _final(9, 'S0 그 다음', tStart: 2000, speaker: 'S0')));
      expect(s.entries.map((e) => e.segId), [8, 7, 9]);
    });

    test('S-17: 같은 seg_id 로 화자별 final 이 오면 기록이 화자 수만큼 생기고 키가 다르다', () {
      var s = const TranscriptSessionState();
      s = reduceTranscript(s, _ev('segment.final', _final(4, '산책하기 좋은 날입니다', speaker: 'S0')));
      s = reduceTranscript(s, _ev('segment.final', _final(4, 'hello everyone', speaker: 'S1')));
      expect(s.entries.map((e) => e.key), ['4@S0', '4@S1']);
    });

    test('같은 (seg_id, speaker) final 이 다시 오면 제자리에서 덮어쓰고 번역은 유지한다', () {
      var s = const TranscriptSessionState();
      s = reduceTranscript(s, _ev('segment.final', _final(4, 'first', speaker: 'S0')));
      s = reduceTranscript(s, _ev('segment.final', _final(5, 'second', tStart: 3000, speaker: 'S0')));
      s = reduceTranscript(s, _ev('translation.final', _translation(4, '첫째', speaker: 'S0')));
      s = reduceTranscript(s, _ev('segment.final', _final(4, 'first fixed', speaker: 'S0')));
      expect(s.entries.map((e) => e.text), ['first fixed', 'second']);
      expect(s.entries.first.translation, '첫째');
    });
  });

  group('translation', () {
    test('같은 seg_id 기록에 번역문을 붙인다', () {
      var s = const TranscriptSessionState();
      s = reduceTranscript(s, _ev('segment.final', _final(7, 'こんにちは')));
      s = reduceTranscript(s, _ev('translation.final', _translation(7, '안녕하세요')));
      expect(s.entries.single.translation, '안녕하세요');
    });

    test('화자가 붙은 번역은 같은 화자 기록에만, 화자 없는 번역은 seg_id 전부에', () {
      var s = const TranscriptSessionState();
      s = reduceTranscript(s, _ev('segment.final', _final(4, 'a', speaker: 'S0')));
      s = reduceTranscript(s, _ev('segment.final', _final(4, 'b', speaker: 'S1')));
      s = reduceTranscript(s, _ev('translation.final', _translation(4, 'B 번역', speaker: 'S1')));
      expect(s.entries[0].translation, isNull);
      expect(s.entries[1].translation, 'B 번역');
      s = reduceTranscript(s, _ev('translation.final', _translation(4, '공통')));
      expect(s.entries.map((e) => e.translation), ['공통', '공통']);
    });

    test('S-20: passthrough 로 원문과 같은 번역이 오면 붙이지 않는다', () {
      var s = const TranscriptSessionState();
      s = reduceTranscript(s, _ev('segment.final', _final(1, '오늘 날씨 좋네요')));
      s = reduceTranscript(
          s, _ev('translation.final', _translation(1, '오늘 날씨 좋네요', engine: 'passthrough')));
      expect(s.entries.single.translation, isNull);
      s = reduceTranscript(s, _ev('segment.final', _final(2, 'hello', tStart: 2000)));
      s = reduceTranscript(
          s, _ev('translation.final', _translation(2, 'hello', engine: 'passthrough', fallback: true)));
      expect(s.entries.last.translation, isNull);
    });
  });

  test('recoverable error 는 경고만, session.state 는 그대로 기록, ended 는 partial 만 지운다', () {
    var s = const TranscriptSessionState();
    s = reduceTranscript(s, _ev('session.state', {'state': 'playing'}));
    s = reduceTranscript(s, _ev('segment.partial', _partial(1, 'a', speaker: 'S0')));
    s = reduceTranscript(s, _ev('error', {'code': 'E_STT_FAILED', 'message': 'x', 'recoverable': true}));
    expect(s.serverState, 'playing');
    expect(s.warning, 'E_STT_FAILED: x');
    expect(s.ended().serverState, isNull);
    expect(s.ended().partials, isEmpty);
    expect(s.ended().warning, 'E_STT_FAILED: x');
  });

  group('2차 패스 갱신 (API 계약 S-28)', () {
    TranscriptSessionState seed() {
      var s = const TranscriptSessionState();
      s = reduceTranscript(s, _ev('segment.final', _final(1, '불레', speaker: 'S0')));
      s = reduceTranscript(s, _ev('segment.final', _final(1, 'the other one', speaker: 'S1')));
      s = reduceTranscript(s, _ev('translation.final', {'seg_id': 1, 'text': '다른 거', 'speaker': 'S1'}));
      return s;
    }

    test('translation.update 는 같은 (seg_id, speaker) 줄의 번역만 바꾸고 revised 를 켠다', () {
      var s = seed();
      s = reduceTranscript(s, _ev('translation.update', {
        'seg_id': 1, 'speaker': 'S1', 'text': '아니 다른 열쇠 말이야', 'prev_text': '다른 거', 'reason': 'context',
      }));
      final s1 = s.entries.singleWhere((e) => e.speaker == 'S1');
      final s0 = s.entries.singleWhere((e) => e.speaker == 'S0');
      expect(s1.translation, '아니 다른 열쇠 말이야');
      expect(s1.revised, isTrue);
      expect(s0.translation, isNull);
      expect(s0.revised, isFalse);
    });

    test('segment.update 는 원문을 바꾸고 번역은 유지한다', () {
      var s = seed();
      s = reduceTranscript(s, _ev('segment.update', {
        'seg_id': 1, 'speaker': 'S0', 'text': '볼래?', 'prev_text': '불레', 'reason': 'context',
      }));
      final s0 = s.entries.singleWhere((e) => e.speaker == 'S0');
      expect(s0.text, '볼래?');
      expect(s0.revised, isTrue);
      expect(s.entries.singleWhere((e) => e.speaker == 'S1').translation, '다른 거');
    });

    test('speaker 없는 update 는 같은 seg_id 전부에, 빈 text 는 무시', () {
      var s = seed();
      s = reduceTranscript(s, _ev('translation.update', {'seg_id': 1, 'text': '', 'reason': 'context'}));
      expect(s.entries.every((e) => !e.revised), isTrue);
      s = reduceTranscript(s, _ev('segment.update', {'seg_id': 1, 'text': '같이', 'reason': 'context'}));
      expect(s.entries.every((e) => e.text == '같이' && e.revised), isTrue);
    });

    test('교정으로 번역이 원문과 같아지면 번역을 지운다 (passthrough 규칙)', () {
      var s = seed();
      s = reduceTranscript(s, _ev('translation.update', {'seg_id': 1, 'speaker': 'S1', 'text': 'the other one'}));
      expect(s.entries.singleWhere((e) => e.speaker == 'S1').translation, isNull);
      s = seed();
      s = reduceTranscript(s, _ev('segment.update', {'seg_id': 1, 'speaker': 'S1', 'text': '다른 거'}));
      final e = s.entries.singleWhere((x) => x.speaker == 'S1');
      expect(e.text, '다른 거');
      expect(e.translation, isNull);
    });

    test('모르는 seg_id 의 update 는 아무것도 바꾸지 않는다', () {
      final s = seed();
      final after = reduceTranscript(s, _ev('translation.update', {'seg_id': 99, 'text': 'x'}));
      expect(after.entries.map((e) => e.translation), s.entries.map((e) => e.translation));
    });
  });
}

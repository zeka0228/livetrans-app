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

Map<String, dynamic> _final(int segId, String text) => {
      'seg_id': segId,
      't_start_ms': 0,
      't_end_ms': 1000,
      'text': text,
      'lang': 'ko',
      'lang_prob': 0.9,
      'words': [],
      'forced_cut': false,
      'stt_ms': 100,
    };

void main() {
  test('partial 은 seg_id 와 무관하게 하나만 유지하고 덮어쓴다', () {
    var s = const TranscriptSessionState();
    s = reduceTranscript(s, _ev('segment.partial', {'seg_id': 1, 't_start_ms': 0, 'text': 'a', 'lang': 'ko'}));
    s = reduceTranscript(s, _ev('segment.partial', {'seg_id': 1, 't_start_ms': 0, 'text': 'ab', 'lang': 'ko'}));
    expect(s.partial!.text, 'ab');
    expect(s.entries, isEmpty);
  });

  test('final 은 기록에 추가하고 같은 seg_id 의 partial 을 지운다', () {
    var s = const TranscriptSessionState();
    s = reduceTranscript(s, _ev('segment.partial', {'seg_id': 3, 't_start_ms': 0, 'text': '중간', 'lang': 'ko'}));
    s = reduceTranscript(s, _ev('segment.final', _final(3, '확정')));
    expect(s.partial, isNull);
    expect(s.entries.single.text, '확정');
    expect(s.entries.single.isFinal, isTrue);
  });

  test('S-2: 빈 final 은 기록에 넣지 않고 partial 만 지운다', () {
    var s = const TranscriptSessionState();
    s = reduceTranscript(s, _ev('segment.partial', {'seg_id': 4, 't_start_ms': 0, 'text': '…', 'lang': 'ko'}));
    s = reduceTranscript(s, _ev('segment.final', _final(4, '   ')));
    expect(s.partial, isNull);
    expect(s.entries, isEmpty);
  });

  test('translation.final 은 같은 seg_id 기록에 번역문을 붙인다', () {
    var s = const TranscriptSessionState();
    s = reduceTranscript(s, _ev('segment.final', _final(7, 'こんにちは')));
    s = reduceTranscript(s, _ev('translation.final', {
      'seg_id': 7,
      'text': '안녕하세요',
      'src_lang': 'ja',
      'tgt_lang': 'ko',
      'engine': 'fake',
      'fallback': false,
      'mt_ms': 5,
    }));
    expect(s.entries.single.translation, '안녕하세요');
  });

  test('recoverable error 는 경고만, session.state 는 그대로 기록', () {
    var s = const TranscriptSessionState();
    s = reduceTranscript(s, _ev('session.state', {'state': 'playing'}));
    s = reduceTranscript(s, _ev('error', {'code': 'E_STT_FAILED', 'message': 'x', 'recoverable': true}));
    expect(s.serverState, 'playing');
    expect(s.warning, 'E_STT_FAILED: x');
    expect(s.ended().serverState, isNull);
    expect(s.ended().warning, 'E_STT_FAILED: x');
  });
}

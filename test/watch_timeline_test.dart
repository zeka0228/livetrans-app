import 'package:flutter_test/flutter_test.dart';
import 'package:livetrans_app/core/models/events.dart';
import 'package:livetrans_app/features/transcript/transcript_entry.dart';
import 'package:livetrans_app/features/watch/watch_timeline.dart';

TranscriptEntry entry(int id, int start, int? end, {String? speaker, bool late = false, String? tr}) =>
    TranscriptEntry(
      segId: id,
      tStartMs: start,
      tEndMs: end,
      text: '원문 $id',
      lang: 'ja',
      langProb: 0.9,
      isFinal: true,
      speaker: speaker,
      late: late,
      translation: tr,
    );

ServerEvent ev(String type, Map<String, dynamic> payload, {int tsWall = 0}) => ServerEvent.fromJson({
      'v': 1,
      'type': type,
      'seq': 1,
      'session_id': 's',
      'ts_wall_ms': tsWall,
      'payload': payload,
    });

void main() {
  group('PlaybackClock', () {
    test('재생 전에는 playhead 음수, 남은 시간·진행률 계산', () {
      const clock = PlaybackClock(playStartWallMs: 10_000, delayS: 20);
      expect(clock.playheadMs(2_000), -8_000);
      expect(clock.remainingMs(2_000), 8_000);
      expect(clock.bufferProgress(2_000), closeTo(0.6, 1e-9));
    });

    test('재생 후에는 playhead 양수, 남은 시간 0', () {
      const clock = PlaybackClock(playStartWallMs: 10_000, delayS: 20);
      expect(clock.playheadMs(13_500), 3_500);
      expect(clock.remainingMs(13_500), 0);
      expect(clock.bufferProgress(13_500), 1.0);
    });

    test('시작 시각을 모르면 null', () {
      const clock = PlaybackClock(delayS: 20);
      expect(clock.playheadMs(1), isNull);
      expect(clock.remainingMs(1), isNull);
      expect(clock.bufferProgress(1), isNull);
    });

    test('스큐는 (수신 시각 − ts_wall_ms) 의 최솟값으로 추정하고 playhead 에 반영', () {
      var clock = const PlaybackClock(playStartWallMs: 1_000_000);
      // 앱 시계가 서버보다 5 s 빠르고, 네트워크 지연 30 ms·80 ms
      clock = clock.observe(ev('metrics', {}, tsWall: 1_000_000), 1_005_030);
      clock = clock.observe(ev('metrics', {}, tsWall: 1_000_500), 1_005_580);
      expect(clock.skewMs, 5_030);
      expect(clock.skewSamples, 2);
      // 앱 시계 1_006_030 = 서버 1_001_000 → playhead 1_000
      expect(clock.playheadMs(1_006_030), 1_000);
    });

    test('ts_wall_ms 가 0 이면 스큐 표본으로 쓰지 않는다', () {
      final clock = const PlaybackClock().observe(ev('metrics', {}), 123);
      expect(clock.skewSamples, 0);
      expect(clock.skewMs, 0);
    });
  });

  group('activeCues', () {
    final entries = [
      entry(0, 0, 2_000),
      entry(1, 2_500, 2_800), // 너무 짧음 → 1.5 s 로 늘어남
      entry(2, 5_000, 9_000, late: true),
      entry(3, 6_000, 8_000, speaker: 'S0'),
      entry(3, 6_000, 8_000, speaker: 'S1'),
    ];

    test('재생 위치에 걸친 문장만', () {
      expect(activeCues(entries, 1_000).map((e) => e.segId), [0]);
      expect(activeCues(entries, 2_100), isEmpty);
    });

    test('최소 표시 1.5 s 보장', () {
      expect(activeCues(entries, 3_500).map((e) => e.segId), [1]);
      expect(activeCues(entries, 4_100), isEmpty);
    });

    test('지연(L3) 문장은 제외, 같은 seg_id 화자 둘은 둘 다', () {
      final cues = activeCues(entries, 7_000);
      expect(cues.map((e) => e.speaker), ['S0', 'S1']);
      expect(cues.any((e) => e.segId == 2), isFalse);
    });

    test('maxCues 를 넘으면 최근 것만', () {
      final many = [entry(0, 0, 10_000), entry(1, 1_000, 10_000), entry(2, 2_000, 10_000)];
      expect(activeCues(many, 5_000).map((e) => e.segId), [1, 2]);
    });

    test('pendingCueCount 는 재생 위치 뒤의 문장 수', () {
      expect(pendingCueCount(entries, 1_000), 3); // 1, 3(S0), 3(S1) — late 2 제외
    });
  });

  group('DeadlineStats · 권장 D', () {
    test('레벨별 집계', () {
      var s = const DeadlineStats();
      s = s.add(DeadlineEventPayload.fromJson({'seg_id': 1, 'kind': 'tts', 'level': 'L1', 'late_ms': 100}));
      s = s.add(DeadlineEventPayload.fromJson({'seg_id': 2, 'kind': 'subtitle', 'level': 'L3', 'late_ms': 900}));
      expect((s.l1, s.l2, s.l3, s.total), (1, 0, 1, 2));
      expect(s.lastLevel, 'L3');
      expect(s.lastLateMs, 900);
    });

    test('미스율 1 % 이하면 권장 없음, 넘으면 25 % 올림', () {
      expect(recommendedNextDelay(delayS: 36, missRate: 0.01), isNull);
      expect(recommendedNextDelay(delayS: 36, missRate: 0.02), 45);
      expect(recommendedNextDelay(delayS: null, missRate: 0.5), isNull);
    });
  });

  test('formatClock', () {
    expect(formatClock(0), '00:00');
    expect(formatClock(61_500), '01:01');
    expect(formatClock(3_600_000 + 5_000), '1:00:05');
    expect(formatClock(-12_000), '-00:12');
  });
}

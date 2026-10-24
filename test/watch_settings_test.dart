import 'package:flutter_test/flutter_test.dart';
import 'package:livetrans_app/core/models/events.dart';
import 'package:livetrans_app/core/models/session.dart';
import 'package:livetrans_app/features/transcript/transcript_session_state.dart';
import 'package:livetrans_app/features/watch/watch_controller.dart';
import 'package:livetrans_app/features/watch/watch_settings.dart';

ServerEvent ev(String type, Map<String, dynamic> payload) => ServerEvent.fromJson({
      'v': 1,
      'type': type,
      'seq': 1,
      'session_id': 's',
      'ts_wall_ms': 0,
      'payload': payload,
    });

void main() {
  group('WatchSettings.toRequest (명세 §6.1 v0.5)', () {
    test('소리만 + 격리 장치 → mode A, loopback device, route·audio·show_speaker 포함', () {
      const s = WatchSettings(
        isolationDeviceId: 'device:{abc}',
        autoDelay: true,
        srcLang: 'ja',
        tgtLang: 'ko',
      );
      final j = s.toRequest().toJson();
      expect(j['mode'], 'A');
      expect(j['source'], {'type': 'loopback', 'params': {'target': 'device:{abc}'}});
      expect(j['delay_s'], isNull);
      expect(j['route'], {'router': 'spare_device', 'isolation_device': 'device:{abc}'});
      expect(j['audio'], {'enhance': true, 'diarize': true, 'game_dialogue': 'keep'});
      expect((j['display'] as Map)['show_speaker'], true);
      expect((j['tts'] as Map)['enabled'], true);
    });

    test('OBS + 수동 지연, 격리 장치 없음 → route 생략', () {
      const s = WatchSettings(
        sourceKind: WatchSourceKind.obs,
        obsUrl: 'srt://127.0.0.1:9000?mode=listener',
        autoDelay: false,
        manualDelayS: 20,
      );
      final j = s.toRequest().toJson();
      expect(j['source'], {'type': 'obs_stream', 'params': {'url': 'srt://127.0.0.1:9000?mode=listener'}});
      expect(j['delay_s'], 20);
      expect(j.containsKey('route'), isFalse);
    });

    test('모드 B·C 요청은 예전 그대로 (route·audio·show_speaker 없음)', () {
      final j = SessionRequest.mic(srcLang: 'auto').toJson();
      expect(j.containsKey('route'), isFalse);
      expect(j.containsKey('audio'), isFalse);
      expect((j['display'] as Map).containsKey('show_speaker'), isFalse);
    });
  });

  group('리듀서 — 화자·지연 (명세 v0.4)', () {
    test('같은 seg_id 로 화자별 final 둘, translation 은 화자별로 붙는다', () {
      var s = const TranscriptSessionState();
      final base = {
        'seg_id': 7, 't_start_ms': 0, 't_end_ms': 1000, 'lang': 'ja', 'lang_prob': 0.9,
        'words': [], 'forced_cut': false, 'stt_ms': 100,
      };
      s = reduceTranscript(s, ev('segment.final', {...base, 'text': 'A', 'speaker': 'S0'}));
      s = reduceTranscript(s, ev('segment.final', {...base, 'text': 'B', 'speaker': 'S1'}));
      s = reduceTranscript(s, ev('translation.final', {'seg_id': 7, 'text': '비', 'speaker': 'S1'}));
      expect(s.entries.length, 2);
      expect(s.entries[0].translation, isNull);
      expect(s.entries[1].translation, '비');
      expect(s.entries[1].speaker, 'S1');
    });

    test('speaker 없는 translation 은 같은 seg_id 전부에 붙는다 (화자 분할 꺼짐)', () {
      var s = const TranscriptSessionState();
      s = reduceTranscript(s, ev('segment.final', {
        'seg_id': 1, 't_start_ms': 0, 't_end_ms': 1000, 'text': 'A', 'lang': 'en', 'lang_prob': 0.9,
        'words': [], 'forced_cut': false, 'stt_ms': 1,
      }));
      s = reduceTranscript(s, ev('translation.final', {'seg_id': 1, 'text': '에이'}));
      expect(s.entries.single.translation, '에이');
      expect(s.entries.single.speaker, isNull);
    });

    test('deadline.event L3 → 해당 문장 late', () {
      var s = const TranscriptSessionState();
      s = reduceTranscript(s, ev('segment.final', {
        'seg_id': 3, 't_start_ms': 0, 't_end_ms': 1000, 'text': 'A', 'lang': 'en', 'lang_prob': 0.9,
        'words': [], 'forced_cut': false, 'stt_ms': 1,
      }));
      s = reduceTranscript(s, ev('deadline.event', {'seg_id': 3, 'kind': 'subtitle', 'level': 'L2', 'late_ms': 10}));
      expect(s.entries.single.late, isFalse);
      s = reduceTranscript(s, ev('deadline.event', {'seg_id': 3, 'kind': 'subtitle', 'level': 'L3', 'late_ms': 900}));
      expect(s.entries.single.late, isTrue);
    });

    test('metrics gpu_util_stream 파싱', () {
      final p = ev('metrics', {
        'p50_ms': {'stt': 300}, 'p99_ms': {'stt': 900}, 'miss_rate': 0.02,
        'queue_depth': 1, 'gpu_mem_used_mb': 8000, 'gpu_util_stream': 0.35,
      }).payload as MetricsPayload;
      expect(p.gpuUtilStream, 0.35);
      expect(p.p99Ms['stt'], 900);
    });
  });

  group('입력 정상 종료 뒤 남은 지연분 재생 (API 계약 S-31)', () {
    test('draining 은 isPlayback 이지만 isLive 는 아니다', () {
      expect(WatchPhase.draining.isPlayback, isTrue);
      expect(WatchPhase.playing.isPlayback, isTrue);
      expect(WatchPhase.draining.isLive, isFalse);
      expect(WatchPhase.ended.isPlayback, isFalse);
    });

    test('마감 = 지금 + D 초 + 여유, 남은 초는 0 아래로 내려가지 않는다', () {
      final until = WatchState.drainDeadline(10_000, 8);
      expect(until, 10_000 + 8000 + WatchState.drainMarginMs);
      final st = WatchState(phase: WatchPhase.draining, drainUntilMs: until);
      expect(st.drainRemainingS(10_000), 10);
      expect(st.drainRemainingS(until + 5000), 0);
      expect(const WatchState(phase: WatchPhase.playing, drainUntilMs: 1).drainRemainingS(0), isNull);
    });

    test('copyWith(clearDrain) 은 inputEnded·drainUntilMs 를 지운다', () {
      final st = const WatchState().copyWith(inputEnded: true, drainUntilMs: 5);
      expect(st.inputEnded, isTrue);
      expect(st.copyWith(clearDrain: true).inputEnded, isFalse);
      expect(st.copyWith(clearDrain: true).drainUntilMs, isNull);
    });
  });

  group('WatchState.startBlockReason (API 계약 S-29 ③)', () {
    const supported = RouteCheckState(status: RouteCheckStatus.idle);

    test('소리만 + 격리 지원 서버 + 장치 미선택 → 시작 막음', () {
      const st = WatchState(settings: WatchSettings(), route: supported);
      expect(st.routeSupported, isTrue);
      expect(st.startBlockReason, contains('격리 장치를 골라야'));
    });

    test('장치를 고르면 시작 가능', () {
      const st = WatchState(settings: WatchSettings(isolationDeviceId: 'device:x'), route: supported);
      expect(st.startBlockReason, isNull);
    });

    test('OBS 입력은 장치 없이도 시작 가능', () {
      const st = WatchState(settings: WatchSettings(sourceKind: WatchSourceKind.obs), route: supported);
      expect(st.startBlockReason, isNull);
    });

    test('구 서버(미지원)·아직 모름이면 막지 않는다 (서버가 400 으로 답하면 그때 오류 표시)', () {
      for (final status in [RouteCheckStatus.unsupported, RouteCheckStatus.unknown, RouteCheckStatus.loadingDevices]) {
        final st = WatchState(settings: const WatchSettings(), route: RouteCheckState(status: status));
        expect(st.routeSupported, isFalse);
        expect(st.startBlockReason, isNull, reason: '$status');
      }
    });

    test('점검 실패가 우선', () {
      const st = WatchState(
        settings: WatchSettings(isolationDeviceId: 'device:x'),
        route: RouteCheckState(status: RouteCheckStatus.failed),
      );
      expect(st.startBlockReason, contains('점검을 통과'));
    });
  });
}

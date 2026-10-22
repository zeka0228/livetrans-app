import '../../core/models/events.dart';
import '../transcript/transcript_entry.dart';

/// 모드 A 재생 시계 (명세 §3 시간 모델의 앱 쪽 구현).
///
/// 서버는 `session.state{state:buffering|playing, delay_s, play_start_wall_ms}` 로
/// "`t_cap = 0` 인 장면이 벽시계 몇 ms 에 재생되는가"를 알려준다 (API 계약 Q-API-9).
/// 앱은 자막을 **재생 위치** `playhead = now_server − play_start_wall_ms` 에 맞춰 보여준다.
/// 재생 시작 전(버퍼링)에는 playhead 가 음수이고, 그 절댓값이 남은 대기 시간이다.
///
/// 폰과 PC 의 시계가 다를 수 있으므로 [skewMs] (= 앱 시계 − 서버 시계) 를 이벤트의
/// `ts_wall_ms` 와 수신 시각으로 추정한다: 네트워크 지연은 0 보다 작을 수 없으니
/// `min(수신 시각 − ts_wall_ms)` 가 스큐의 상한 근사다.
class PlaybackClock {
  const PlaybackClock({
    this.playStartWallMs,
    this.delayS,
    this.skewMs = 0,
    this.skewSamples = 0,
  });

  final int? playStartWallMs;
  final int? delayS;
  final int skewMs;
  final int skewSamples;

  bool get hasStart => playStartWallMs != null;

  /// 서버 벽시계 기준 지금.
  int serverNow(int localNowMs) => localNowMs - skewMs;

  /// 재생 위치 (`t_cap`, ms). 시작 시각을 모르면 null. 재생 전이면 음수.
  int? playheadMs(int localNowMs) {
    final start = playStartWallMs;
    if (start == null) return null;
    return serverNow(localNowMs) - start;
  }

  /// 재생 시작까지 남은 ms (0 이상). 시작 시각을 모르면 null.
  int? remainingMs(int localNowMs) {
    final p = playheadMs(localNowMs);
    if (p == null) return null;
    return p >= 0 ? 0 : -p;
  }

  /// 버퍼링 진행률 0~1. [delayS] 를 모르면 null.
  double? bufferProgress(int localNowMs) {
    final d = delayS;
    final r = remainingMs(localNowMs);
    if (d == null || d <= 0 || r == null) return null;
    final total = d * 1000;
    return ((total - r) / total).clamp(0.0, 1.0);
  }

  /// 이벤트 하나로 스큐 추정을 갱신한다.
  PlaybackClock observe(ServerEvent e, int localReceiveMs) {
    if (e.tsWallMs <= 0) return this;
    final sample = localReceiveMs - e.tsWallMs;
    final next = skewSamples == 0 ? sample : (sample < skewMs ? sample : skewMs);
    return copyWith(skewMs: next, skewSamples: skewSamples + 1);
  }

  PlaybackClock copyWith({
    int? playStartWallMs,
    int? delayS,
    int? skewMs,
    int? skewSamples,
  }) =>
      PlaybackClock(
        playStartWallMs: playStartWallMs ?? this.playStartWallMs,
        delayS: delayS ?? this.delayS,
        skewMs: skewMs ?? this.skewMs,
        skewSamples: skewSamples ?? this.skewSamples,
      );
}

/// 화면에 띄울 자막 큐. 번역·원문 중 무엇을 보여줄지는 [SubtitleMode] 가 정한다.
enum SubtitleMode { translation, original, both }

extension SubtitleModeLabel on SubtitleMode {
  String get label => switch (this) {
        SubtitleMode.translation => '번역',
        SubtitleMode.original => '원문',
        SubtitleMode.both => '둘 다',
      };

  SubtitleMode get next => switch (this) {
        SubtitleMode.translation => SubtitleMode.original,
        SubtitleMode.original => SubtitleMode.both,
        SubtitleMode.both => SubtitleMode.translation,
      };
}

/// 명세 §3.5 L2 — 자막은 적어도 이만큼은 보여준다.
const kMinCueDisplayMs = 1500;

/// 재생 위치 [playheadMs] 에 보여야 할 자막. 시작 시각 순, 화자가 여럿이면 여러 개.
///
/// - 데드라인을 놓쳐 출력에서 빠진 문장([TranscriptEntry.late]) 은 제외.
/// - 끝 시각이 시작 + 1.5 s 보다 이르면 1.5 s 까지 늘려 보여준다 (너무 짧은 문장 깜빡임 방지).
/// - [maxCues] 개를 넘으면 가장 최근 것만 남긴다.
List<TranscriptEntry> activeCues(
  List<TranscriptEntry> entries,
  int playheadMs, {
  int maxCues = 2,
}) {
  final out = <TranscriptEntry>[];
  for (final e in entries) {
    if (e.late || !e.isFinal) continue;
    final end = _cueEnd(e);
    if (e.tStartMs <= playheadMs && playheadMs < end) out.add(e);
  }
  out.sort((a, b) => a.tStartMs.compareTo(b.tStartMs));
  if (out.length > maxCues) return out.sublist(out.length - maxCues);
  return out;
}

int _cueEnd(TranscriptEntry e) {
  final end = e.tEndMs ?? (e.tStartMs + kMinCueDisplayMs);
  final min = e.tStartMs + kMinCueDisplayMs;
  return end < min ? min : end;
}

/// 재생 위치보다 뒤에 있어 아직 안 보인 문장 수 — "준비된 자막 N개" 표시용.
int pendingCueCount(List<TranscriptEntry> entries, int playheadMs) =>
    entries.where((e) => e.isFinal && !e.late && e.tStartMs > playheadMs).length;

/// `deadline.event` 집계 (명세 §3.5 사다리).
class DeadlineStats {
  const DeadlineStats({
    this.l1 = 0,
    this.l2 = 0,
    this.l3 = 0,
    this.lastLateMs,
    this.lastLevel,
  });

  final int l1;
  final int l2;
  final int l3;
  final int? lastLateMs;
  final String? lastLevel;

  int get total => l1 + l2 + l3;

  DeadlineStats add(DeadlineEventPayload p) => DeadlineStats(
        l1: l1 + (p.level == 'L1' ? 1 : 0),
        l2: l2 + (p.level == 'L2' ? 1 : 0),
        l3: l3 + (p.level == 'L3' ? 1 : 0),
        lastLateMs: p.lateMs,
        lastLevel: p.level,
      );

  static String describe(String level) => switch (level) {
        'L1' => '음성만 늦음 (빠르게 재생)',
        'L2' => '자막이 늦게 표시됨',
        'L3' => '문장이 재생에 못 실림',
        _ => level,
      };
}

/// 미스율이 1 % 를 넘으면 다음 세션 권장 D 를 안내한다 (명세 §3.4 ②, I3: 실행 중 변경 없음).
int? recommendedNextDelay({required int? delayS, required double missRate}) {
  if (delayS == null || missRate <= 0.01) return null;
  // 보수적으로 25 % 더 길게, 1 s 단위 올림.
  return (delayS * 1.25).ceil();
}

String formatClock(int ms) {
  final neg = ms < 0;
  final total = (ms.abs() / 1000).floor();
  final h = total ~/ 3600;
  final m = (total % 3600) ~/ 60;
  final s = total % 60;
  final mm = m.toString().padLeft(2, '0');
  final ss = s.toString().padLeft(2, '0');
  final body = h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
  return neg ? '-$body' : body;
}

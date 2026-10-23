import '../../core/models/events.dart';
import 'transcript_entry.dart';

/// 서버 이벤트를 자막 화면 상태로 접는 순수 리듀서. 마이크·방송·시청 모드가 같이 쓴다.
///
/// 규칙 (API 계약 §1.3, S-2, S-4, S-17, S-19, S-20):
/// - `segment.partial` 은 **화자(레인)마다 하나**만 유지하고 덮어쓴다 (S-19 ②). 화자 분할이 꺼져 있으면
///   speaker 가 없으므로 칸 하나 — seg_id 와 무관하게 덮어쓴다 (버려진 발화의 id 재사용 대응).
/// - `segment.final` 은 기록에 **t_start_ms 순서로** 끼워 넣는다 (S-19 ④: 레인끼리 seg_id 가 섞여 시간 순 ≠ id 순).
///   같은 seg_id 또는 같은 화자의 partial 은 지운다. **text 가 비면 추가하지 않는다** (S-2).
///   기록 키는 (seg_id, speaker) — 발화 단위 모드(S-17)에서 같은 seg_id 로 화자별 final 이 올 수 있어서.
///   같은 키의 final 이 다시 오면 그 자리에서 덮어쓴다 (번역 유지).
/// - `translation.final` 은 같은 (seg_id, speaker) 기록에 번역문을 붙인다. 원문과 똑같은 번역
///   (S-20 ②③ `passthrough`) 은 붙이지 않는다 — 같은 문장을 두 번 보여줄 이유가 없다.
/// - `deadline.event` L3 는 그 문장을 "지연" 으로 표시한다 (모드 A).
/// - `error(recoverable=true)` 는 경고 문구만. 치명적 error 는 컨트롤러가 따로 처리한다.
class TranscriptSessionState {
  const TranscriptSessionState({
    this.partials = const [],
    this.entries = const [],
    this.serverState,
    this.warning,
  });

  /// 화자(레인)별 "지금 듣는 중" 문장. t_start_ms 순.
  final List<TranscriptEntry> partials;
  final List<TranscriptEntry> entries;
  final String? serverState;
  final String? warning;

  /// 화자 분할이 꺼져 있을 때의 단일 partial (호환용). 레인이 여럿이면 가장 최근 것.
  TranscriptEntry? get partial => partials.isEmpty ? null : partials.last;

  TranscriptSessionState copyWith({
    List<TranscriptEntry>? partials,
    List<TranscriptEntry>? entries,
    String? serverState,
    bool clearServerState = false,
    String? warning,
    bool clearWarning = false,
  }) =>
      TranscriptSessionState(
        partials: partials ?? this.partials,
        entries: entries ?? this.entries,
        serverState:
            clearServerState ? null : (serverState ?? this.serverState),
        warning: clearWarning ? null : (warning ?? this.warning),
      );

  /// 세션이 끝났을 때: 기록은 남기고 진행 중 표시만 지운다.
  TranscriptSessionState ended() =>
      copyWith(partials: const [], clearServerState: true);
}

/// partial 끼리 같은 칸인지: 화자가 있으면 화자 레인, 없으면 전부 한 칸.
bool _sameLane(TranscriptEntry a, String? speaker) =>
    (a.speaker ?? '') == (speaker ?? '');

/// t_start_ms 오름차순을 유지하며 끼워 넣는다 (같은 시각이면 뒤에).
List<TranscriptEntry> _insertByTime(List<TranscriptEntry> list, TranscriptEntry e) {
  var i = list.length;
  while (i > 0 && list[i - 1].tStartMs > e.tStartMs) {
    i--;
  }
  return [...list.sublist(0, i), e, ...list.sublist(i)];
}

TranscriptSessionState reduceTranscript(
  TranscriptSessionState s,
  ServerEvent event,
) {
  switch (event.payload) {
    case SessionStatePayload p:
      return s.copyWith(serverState: p.state);
    case SegmentPartialPayload p:
      if (p.text.isEmpty) return s;
      final entry = TranscriptEntry(
        segId: p.segId,
        tStartMs: p.tStartMs,
        tEndMs: null,
        text: p.text,
        lang: p.lang,
        langProb: null,
        isFinal: false,
        speaker: p.speaker,
      );
      final kept = [for (final x in s.partials) if (!_sameLane(x, p.speaker)) x];
      return s.copyWith(partials: _insertByTime(kept, entry));
    case SegmentFinalPayload p:
      final partials = [
        for (final x in s.partials)
          if (x.segId != p.segId && !(p.speaker != null && x.speaker == p.speaker)) x,
      ];
      if (p.text.trim().isEmpty) {
        return s.copyWith(partials: partials);
      }
      final entry = TranscriptEntry(
        segId: p.segId,
        tStartMs: p.tStartMs,
        tEndMs: p.tEndMs,
        text: p.text,
        lang: p.lang,
        langProb: p.langProb,
        isFinal: true,
        sttMs: p.sttMs,
        forcedCut: p.forcedCut,
        speaker: p.speaker,
      );
      final i = s.entries.indexWhere((e) => e.key == entry.key);
      return s.copyWith(
        entries: i < 0
            ? _insertByTime(s.entries, entry)
            : [
                for (var j = 0; j < s.entries.length; j++)
                  if (j == i)
                    entry.copyWith(translation: s.entries[j].translation)
                  else
                    s.entries[j],
              ],
        partials: partials,
      );
    case TranslationFinalPayload p:
      return s.copyWith(
        entries: [
          for (final e in s.entries)
            if (e.sameAs(p.segId, p.speaker) && p.text.trim() != e.text.trim())
              e.copyWith(translation: p.text)
            else
              e,
        ],
      );
    case DeadlineEventPayload p when p.level == 'L3':
      // 모드 A: 발화 재생이 이미 끝나 출력에서 빠진 문장 → 기록에 "지연" 표시 (명세 §3.5).
      return s.copyWith(
        entries: [
          for (final e in s.entries)
            if (e.segId == p.segId) e.copyWith(late: true) else e,
        ],
      );
    case ErrorPayload p when p.recoverable:
      return s.copyWith(warning: '${p.code}: ${p.message}');
    case ErrorPayload():
    case TtsReadyPayload():
    case DeadlineEventPayload():
    case MetricsPayload():
    case UnknownPayload():
      return s;
  }
}

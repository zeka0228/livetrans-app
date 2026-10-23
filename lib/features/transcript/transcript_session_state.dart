import '../../core/models/events.dart';
import 'transcript_entry.dart';

/// 서버 이벤트를 자막 화면 상태로 접는 순수 리듀서. 마이크·방송 모드가 같이 쓴다.
///
/// 규칙 (API 계약 §1.3, S-2, S-4):
/// - `segment.partial` 은 seg_id 와 무관하게 "지금 듣는 중" 칸 하나에 덮어쓴다 (버려진 발화의 id 재사용 대응).
/// - `segment.final` 은 기록에 추가하고 같은 seg_id 의 partial 을 지운다. **text 가 비면 추가하지 않는다** (S-2).
///   화자 분할이 켜지면 같은 seg_id 로 화자별 final 이 하나씩 온다 → 기록 키는 (seg_id, speaker) (S-17).
///   같은 키의 final 이 다시 오면 덮어쓴다 (서버 재전송 대비, 기록이 두 줄 되지 않게).
/// - `translation.final` 은 같은 (seg_id, speaker) 기록에 번역문을 붙인다.
/// - `error(recoverable=true)` 는 경고 문구만. 치명적 error 는 컨트롤러가 따로 처리한다.
class TranscriptSessionState {
  const TranscriptSessionState({
    this.partial,
    this.entries = const [],
    this.serverState,
    this.warning,
  });

  final TranscriptEntry? partial;
  final List<TranscriptEntry> entries;
  final String? serverState;
  final String? warning;

  TranscriptSessionState copyWith({
    TranscriptEntry? partial,
    bool clearPartial = false,
    List<TranscriptEntry>? entries,
    String? serverState,
    bool clearServerState = false,
    String? warning,
    bool clearWarning = false,
  }) =>
      TranscriptSessionState(
        partial: clearPartial ? null : (partial ?? this.partial),
        entries: entries ?? this.entries,
        serverState:
            clearServerState ? null : (serverState ?? this.serverState),
        warning: clearWarning ? null : (warning ?? this.warning),
      );

  /// 세션이 끝났을 때: 기록은 남기고 진행 중 표시만 지운다.
  TranscriptSessionState ended() =>
      copyWith(clearPartial: true, clearServerState: true);
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
      return s.copyWith(
        partial: TranscriptEntry(
          segId: p.segId,
          tStartMs: p.tStartMs,
          tEndMs: null,
          text: p.text,
          lang: p.lang,
          langProb: null,
          isFinal: false,
        ),
      );
    case SegmentFinalPayload p:
      final clearPartial = s.partial?.segId == p.segId;
      if (p.text.trim().isEmpty) {
        return s.copyWith(clearPartial: clearPartial);
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
            ? [...s.entries, entry]
            : [
                for (var j = 0; j < s.entries.length; j++)
                  if (j == i)
                    entry.copyWith(translation: s.entries[j].translation)
                  else
                    s.entries[j],
              ],
        clearPartial: clearPartial,
      );
    case TranslationFinalPayload p:
      return s.copyWith(
        entries: [
          for (final e in s.entries)
            if (e.sameAs(p.segId, p.speaker)) e.copyWith(translation: p.text) else e,
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

/// 자막 기록 한 줄. `segment.final` + `translation.final` 을 (seg_id, speaker) 로 합친다.
class TranscriptEntry {
  const TranscriptEntry({
    required this.segId,
    required this.tStartMs,
    required this.tEndMs,
    required this.text,
    required this.lang,
    required this.langProb,
    required this.isFinal,
    this.sttMs,
    this.forcedCut = false,
    this.translation,
    this.speaker,
    this.late = false,
    this.revised = false,
    this.confidence,
    this.uncertain = false,
  });

  final int segId;
  final int tStartMs;
  final int? tEndMs;
  final String text;
  final String lang;
  final double? langProb;
  final bool isFinal;
  final int? sttMs;
  final bool forcedCut;
  final String? translation;

  /// 화자 분할 ID (`S0` …, API 계약 S-17). 화자를 못 찾은 발화는 null.
  final String? speaker;

  /// 기록 안에서 한 문장을 가리키는 키. 화자 분할이 켜지면 같은 seg_id 로 화자별 final 이
  /// 하나씩 오므로 seg_id 만으로는 부족하다 (S-16·S-17).
  String get key => speaker == null ? '$segId' : '$segId@$speaker';

  /// `translation.final` 등이 이 문장을 가리키는지. 어느 한쪽에 화자가 없으면 seg_id 만 비교한다.
  bool sameAs(int segId, String? speaker) =>
      this.segId == segId &&
      (speaker == null || this.speaker == null || this.speaker == speaker);

  /// 화면에 보이는 화자 이름: `S0` → `화자 1`.
  static String speakerLabel(String speaker) {
    final n = int.tryParse(speaker.replaceFirst(RegExp('^S'), ''));
    return n == null ? speaker : '화자 ${n + 1}';
  }

  /// 모드 A 에서 데드라인을 놓쳐 재생에 못 실린 문장 (`deadline.event` L3). 기록에는 "지연" 표시로 남긴다.
  final bool late;

  /// 서버 2차 패스(S-28 `segment.update`/`translation.update`)로 원문 또는 번역이 고쳐진 줄. 목록에 "교정" 배지.
  final bool revised;

  /// 번역 모델이 문맥으로 고른 읽기의 확신도 0~1 (S-30 `translation.final.confidence`). 없으면 null.
  final double? confidence;

  /// 확신도가 낮은 줄 (S-30 `uncertain`). 목록·자막에서 흐리게/기울임으로 보여 준다.
  final bool uncertain;

  /// 확신도 백분율 표시 ("42%"). 없으면 null.
  String? get confidenceLabel => confidence == null ? null : '${(confidence! * 100).round()}%';

  TranscriptEntry copyWith({
    int? tEndMs,
    String? text,
    String? lang,
    double? langProb,
    bool? isFinal,
    int? sttMs,
    bool? forcedCut,
    String? translation,
    String? speaker,
    bool? late,
    bool? revised,
    double? confidence,
    bool? uncertain,
    bool clearTranslation = false,
  }) =>
      TranscriptEntry(
        segId: segId,
        tStartMs: tStartMs,
        tEndMs: tEndMs ?? this.tEndMs,
        text: text ?? this.text,
        lang: lang ?? this.lang,
        langProb: langProb ?? this.langProb,
        isFinal: isFinal ?? this.isFinal,
        sttMs: sttMs ?? this.sttMs,
        forcedCut: forcedCut ?? this.forcedCut,
        translation: clearTranslation ? null : (translation ?? this.translation),
        speaker: speaker ?? this.speaker,
        late: late ?? this.late,
        revised: revised ?? this.revised,
        confidence: confidence ?? this.confidence,
        uncertain: uncertain ?? this.uncertain,
      );

  static String formatMs(int ms) {
    final totalSeconds = ms ~/ 1000;
    final m = totalSeconds ~/ 60;
    final s = totalSeconds % 60;
    final tenth = (ms % 1000) ~/ 100;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}.$tenth';
  }

  static String langLabel(String code) => switch (code) {
        'ko' => '한국어',
        'en' => '영어',
        'ja' => '일본어',
        '' => '-',
        _ => code,
      };
}

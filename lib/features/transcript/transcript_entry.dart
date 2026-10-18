/// 자막 기록 한 줄. `segment.final` + `translation.final`을 seg_id로 합친다.
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

  TranscriptEntry copyWith({
    int? tEndMs,
    String? text,
    String? lang,
    double? langProb,
    bool? isFinal,
    int? sttMs,
    bool? forcedCut,
    String? translation,
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
        translation: translation ?? this.translation,
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

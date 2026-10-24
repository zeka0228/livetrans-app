import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livetrans_app/features/transcript/transcript_entry.dart';
import 'package:livetrans_app/features/transcript/transcript_list.dart';

Widget _wrap(TranscriptEntry entry) => MaterialApp(
      home: Scaffold(body: TranscriptList(entries: [entry])),
    );

const _base = TranscriptEntry(
  segId: 1,
  tStartMs: 0,
  tEndMs: 1000,
  text: 'the gain is on',
  lang: 'en',
  langProb: 0.9,
  isFinal: true,
  translation: '게인이 켜져 있어',
);

void main() {
  testWidgets('확신도 낮은 번역(S-30)은 "불확실 N%" 배지 + 기울임 + 물음표', (tester) async {
    await tester.pumpWidget(_wrap(_base.copyWith(confidence: 0.42, uncertain: true)));
    expect(find.byKey(const Key('uncertain-badge')), findsOneWidget);
    expect(find.text('불확실 42%'), findsOneWidget);
    final t = tester.widget<Text>(find.text('게인이 켜져 있어 ?'));
    expect(t.style?.fontStyle, FontStyle.italic);
  });

  testWidgets('확신도가 높거나 없으면 배지 없이 평소대로', (tester) async {
    await tester.pumpWidget(_wrap(_base.copyWith(confidence: 0.97)));
    expect(find.byKey(const Key('uncertain-badge')), findsNothing);
    expect(find.text('게인이 켜져 있어'), findsOneWidget);
    await tester.pumpWidget(_wrap(_base));
    expect(find.byKey(const Key('uncertain-badge')), findsNothing);
  });
}

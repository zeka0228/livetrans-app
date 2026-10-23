import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livetrans_app/core/video/hls_video.dart';

void main() {
  testWidgets('웹이 아닌 플랫폼에서는 자리 표시와 unsupported 상태를 낸다', (tester) async {
    HlsVideoState? got;
    await tester.pumpWidget(
      MaterialApp(
        home: HlsVideoView(
          url: 'http://127.0.0.1:8790/master.m3u8',
          onState: (s) => got = s,
        ),
      ),
    );
    await tester.pump();
    expect(find.textContaining('웹(Chrome)'), findsOneWidget);
    expect(got?.status, HlsVideoStatus.unsupported);
  });

  test('HlsVideoState.toString 은 상태·지연·자막 수를 담는다', () {
    const s = HlsVideoState(
      status: HlsVideoStatus.playing,
      latencyS: 3.04,
      subtitleTracks: 2,
    );
    expect(s.toString(), 'HlsVideoState(HlsVideoStatus.playing, latency 3.0 s, subs 2)');
  });
}

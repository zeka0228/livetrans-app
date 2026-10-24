import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livetrans_app/core/video/hls_video.dart';
import 'package:livetrans_app/features/watch/player_surface.dart';

Widget _surface({
  String? hlsUrl,
  required bool expectVideo,
  required bool playing,
}) =>
    MaterialApp(
      home: PlayerSurface(
        hlsUrl: hlsUrl,
        expectVideo: expectVideo,
        playing: playing,
        muted: false,
        volume: 1,
      ),
    );

void main() {
  const url = 'http://127.0.0.1:8765/hls/s1/master.m3u8';

  testWidgets('S-21 ②: playing 전에는 hls_url 이 있어도 플레이어를 열지 않는다', (tester) async {
    await tester.pumpWidget(_surface(hlsUrl: url, expectVideo: true, playing: false));
    await tester.pump();
    expect(find.byType(HlsVideoView), findsNothing);
  });

  testWidgets('playing 이 되면 플레이어를 열고, 그 뒤 playing 이 꺼져도(종료) 닫지 않는다', (tester) async {
    await tester.pumpWidget(_surface(hlsUrl: url, expectVideo: true, playing: false));
    await tester.pump();
    expect(find.byType(HlsVideoView), findsNothing);

    await tester.pumpWidget(_surface(hlsUrl: url, expectVideo: true, playing: true));
    await tester.pump();
    expect(find.byType(HlsVideoView), findsOneWidget);

    await tester.pumpWidget(_surface(hlsUrl: url, expectVideo: true, playing: false));
    await tester.pump();
    expect(find.byType(HlsVideoView), findsOneWidget);
  });

  testWidgets('URL 이 바뀌면 다시 playing 을 기다린다', (tester) async {
    await tester.pumpWidget(_surface(hlsUrl: url, expectVideo: true, playing: true));
    await tester.pump();
    expect(find.byType(HlsVideoView), findsOneWidget);

    await tester.pumpWidget(_surface(hlsUrl: '$url?b', expectVideo: true, playing: false));
    await tester.pump();
    expect(find.byType(HlsVideoView), findsNothing);
  });

  testWidgets('소리만 모드도 hls_url 이 있으면 플레이어를 열고 배경으로 덮는다 (S-21 ③ 오디오 전용 HLS)',
      (tester) async {
    await tester.pumpWidget(_surface(hlsUrl: url, expectVideo: false, playing: true));
    await tester.pump();
    expect(find.byType(HlsVideoView), findsOneWidget);
    expect(find.text('소리만 모드 · 자막·번역 음성 재생 중'), findsOneWidget);
  });

  testWidgets('영상 기대 + URL 없음 + playing 이면 "영상 스트림 대기 중"', (tester) async {
    await tester.pumpWidget(_surface(hlsUrl: null, expectVideo: true, playing: true));
    await tester.pump();
    expect(find.byType(HlsVideoView), findsNothing);
    expect(find.text('영상 스트림 대기 중'), findsOneWidget);
  });

  testWidgets('플레이어가 재생 중이 아니면 상태 칩을 띄운다 (테스트 플랫폼 = 미지원)', (tester) async {
    await tester.pumpWidget(_surface(hlsUrl: url, expectVideo: true, playing: true));
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('이 플랫폼은 영상 미지원'), findsOneWidget);
    // 미지원은 재시도 대상이 아니다 (오류일 때만 "다시 시도").
    expect(find.text('다시 시도'), findsNothing);
  });
}

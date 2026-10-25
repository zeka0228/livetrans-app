import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livetrans_app/core/storage/local_flags.dart';
import 'package:livetrans_app/features/watch/watch_controller.dart';
import 'package:livetrans_app/features/watch/watch_player_screen.dart';
import 'package:livetrans_app/features/watch/watch_settings.dart';

/// 재생 중(playing) 상태로 고정된 가짜 컨트롤러. 서버·HLS 없이 플레이어 화면만 띄운다.
class _PlayingController extends WatchController {
  @override
  WatchState build() => const WatchState(
        phase: WatchPhase.playing,
        settings: WatchSettings(sourceKind: WatchSourceKind.obs),
      );
}

Widget _app() => ProviderScope(
      overrides: [watchControllerProvider.overrideWith(_PlayingController.new)],
      child: const MaterialApp(home: WatchPlayerScreen()),
    );

final _hint = find.byKey(const Key('fullscreen-esc-hint'));
final _enterIcon = find.byIcon(Icons.fullscreen_rounded);
final _exitIcon = find.byIcon(Icons.fullscreen_exit_rounded);

void main() {
  setUp(LocalFlags.clear);

  testWidgets('Esc 키로 전체화면을 해제한다', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pump();
    expect(_enterIcon, findsOneWidget);

    await tester.tap(_enterIcon);
    await tester.pump();
    expect(_exitIcon, findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(_enterIcon, findsOneWidget);
    expect(_exitIcon, findsNothing);

    await tester.pumpWidget(const SizedBox()); // 타이머 정리
  });

  testWidgets('전체화면이 아니면 Esc 는 아무것도 하지 않는다', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(_enterIcon, findsOneWidget);
    expect(find.byType(WatchPlayerScreen), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('첫 전체화면에서만 Esc 안내를 띄우고, 확인을 누르면 사라진다', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pump();
    expect(_hint, findsNothing);

    await tester.tap(_enterIcon);
    await tester.pump();
    expect(_hint, findsOneWidget);
    expect(find.text('Esc 키를 누르면 전체화면이 해제돼요'), findsOneWidget);

    await tester.tap(find.text('확인'));
    await tester.pump();
    expect(_hint, findsNothing);

    // 해제했다가 다시 들어가도 두 번째는 안내 없음.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    await tester.tap(_enterIcon);
    await tester.pump();
    expect(_hint, findsNothing);
    expect(LocalFlags.get('watch.fullscreen_esc_hint_seen'), isTrue);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('안내는 8 초 뒤 저절로 사라지고, Esc 로 해제해도 사라진다', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pump();
    await tester.tap(_enterIcon);
    await tester.pump();
    expect(_hint, findsOneWidget);

    await tester.pump(const Duration(seconds: 8));
    await tester.pump();
    expect(_hint, findsNothing);

    // 다른 세션(플래그 초기화) 에서 Esc 로 해제한 경우.
    LocalFlags.clear();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    await tester.tap(_enterIcon);
    await tester.pump();
    expect(_hint, findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(_hint, findsNothing);

    await tester.pumpWidget(const SizedBox());
  });

  test('LocalFlags: 없는 키는 false, set 한 값은 유지, clear 로 비운다', () {
    expect(LocalFlags.get('x'), isFalse);
    LocalFlags.set('x', true);
    expect(LocalFlags.get('x'), isTrue);
    LocalFlags.set('x', false);
    expect(LocalFlags.get('x'), isFalse);
    LocalFlags.set('x', true);
    LocalFlags.clear();
    expect(LocalFlags.get('x'), isFalse);
  });
}

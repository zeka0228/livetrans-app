import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:livetrans_app/core/api/rest_client.dart';
import 'package:livetrans_app/core/config/server_config.dart';
import 'package:livetrans_app/features/engines/engine_controller.dart';
import 'package:livetrans_app/features/engines/engine_picker.dart';

const catalogJson = {
  'stt': {
    'default': 'auto',
    'route_by_lang': {'ko': 'faster_whisper', 'ja': 'faster_whisper'},
    'engines': [
      {'name': 'dicow', 'model': 'BUT-FIT/DiCoW_v3_3', 'role': 'primary', 'languages': ['ko', 'en', 'ja'], 'speaker_mask': true},
      {'name': 'faster_whisper', 'model': 'large-v3', 'role': 'rescue', 'languages': ['ko', 'en', 'ja'], 'speaker_mask': false},
    ],
  },
  'mt': {
    'engine': 'ollama_llm',
    'default_model': 'gemma2:9b',
    'models': [
      {'name': 'gemma2:9b', 'size_mb': 5160},
      {'name': 'gemma3:12b-it-qat', 'size_mb': 8500},
    ],
  },
};

(Widget, ProviderContainer) harness(http.Client client, {bool enabled = true}) {
  final container = ProviderContainer(
    overrides: [
      restClientProvider.overrideWith(
        (ref) => RestClient(const ServerConfig(baseUrl: 'http://fake:1'), client: client),
      ),
    ],
  );
  addTearDown(container.dispose);
  final app = UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      home: Scaffold(body: ListView(children: [EnginePicker(enabled: enabled)])),
    ),
  );
  return (app, container);
}

void main() {
  testWidgets('구 서버(404)면 아무것도 그리지 않는다', (tester) async {
    final (app, _) = harness(MockClient((_) async => http.Response('Not Found', 404)));
    await tester.pumpWidget(app);
    await tester.pumpAndSettle();
    expect(find.byType(Card), findsNothing);
    expect(find.byKey(const Key('engine-picker-stt')), findsNothing);
  });

  testWidgets('카탈로그를 받으면 STT·번역 모델 드롭다운을 보여 주고, 고르면 선택값이 바뀐다', (tester) async {
    final (app, container) = harness(
      MockClient((_) async => http.Response(jsonEncode(catalogJson), 200)),
    );
    await tester.pumpWidget(app);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('engine-picker-stt')), findsOneWidget);
    expect(find.byKey(const Key('engine-picker-mt')), findsOneWidget);
    expect(find.textContaining('자동', findRichText: true), findsWidgets);
    expect(find.textContaining('서버 기본', findRichText: true), findsWidgets);

    // STT: 기본으로는 "자동"(권장)만. "엔진 직접 지정 전체 보기" 뒤 dicow 선택
    expect(find.text('권장'), findsWidgets);
    await tester.tap(find.byKey(const Key('engine-picker-stt')));
    await tester.pumpAndSettle();
    expect(find.textContaining('BUT-FIT/DiCoW_v3_3', findRichText: true), findsNothing);
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('engine-picker-stt-more')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('engine-picker-stt')));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('BUT-FIT/DiCoW_v3_3', findRichText: true).last);
    await tester.pumpAndSettle();
    expect(container.read(engineControllerProvider).selection.sttEngine, 'dicow');
    // 일본어 라우팅 안내
    expect(find.textContaining('방송 언어를 해당 언어로 지정'), findsOneWidget);

    // 번역 모델: 기본으로는 권장(서버 기본)만 보이고 gemma3 는 숨어 있다 → "전체 보기" 뒤 선택 → 모델 교체 안내
    await tester.tap(find.byKey(const Key('engine-picker-mt')));
    await tester.pumpAndSettle();
    expect(find.textContaining('gemma3:12b-it-qat', findRichText: true), findsNothing);
    await tester.tapAt(const Offset(5, 5)); // 메뉴 닫기
    await tester.pumpAndSettle();
    expect(find.textContaining('다른 모델 전체 보기 (1개 더)'), findsOneWidget);
    await tester.tap(find.byKey(const Key('engine-picker-mt-more')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('engine-picker-mt')));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('gemma3:12b-it-qat', findRichText: true).last);
    await tester.pumpAndSettle();
    final s = container.read(engineControllerProvider);
    expect(s.selection.mtModel, 'gemma3:12b-it-qat');
    expect(s.mtSwapExpected, isTrue);
    expect(find.textContaining('첫 세션 시작이 수 초~수십 초'), findsOneWidget);
  });

  testWidgets('목록 실패면 오류와 "다시 시도" 를 보여 준다', (tester) async {
    var calls = 0;
    final (app, container) = harness(MockClient((_) async {
      calls++;
      return calls == 1
          ? http.Response('{"detail":{"code":"E_X","message":"boom"}}', 500)
          : http.Response(jsonEncode(catalogJson), 200);
    }));
    await tester.pumpWidget(app);
    await tester.pumpAndSettle();
    expect(find.text('다시 시도'), findsOneWidget);
    expect(container.read(engineControllerProvider).status, EngineCatalogStatus.failed);

    await tester.tap(find.text('다시 시도'));
    await tester.pumpAndSettle();
    expect(container.read(engineControllerProvider).status, EngineCatalogStatus.ready);
    expect(find.byKey(const Key('engine-picker-stt')), findsOneWidget);
  });

  testWidgets('세션 중(enabled=false)에는 드롭다운이 잠긴다', (tester) async {
    final (app, _) = harness(
      MockClient((_) async => http.Response(jsonEncode(catalogJson), 200)),
      enabled: false,
    );
    await tester.pumpWidget(app);
    await tester.pumpAndSettle();
    final stt = tester.widget<DropdownButtonFormField<String>>(find.byKey(const Key('engine-picker-stt')));
    expect(stt.onChanged, isNull);
  });
}

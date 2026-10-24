import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:livetrans_app/core/api/rest_client.dart';
import 'package:livetrans_app/core/config/server_config.dart';
import 'package:livetrans_app/core/models/engines.dart';
import 'package:livetrans_app/core/models/session.dart';
import 'package:livetrans_app/features/engines/engine_controller.dart';
import 'package:livetrans_app/features/watch/watch_settings.dart';

/// API 계약 S-26 서버 통보 12 의 예시 응답.
const catalogJson = {
  'stt': {
    'default': 'auto',
    'route_by_lang': {'ko': 'faster_whisper', 'ja': 'faster_whisper'},
    'engines': [
      {
        'name': 'dicow',
        'model': 'BUT-FIT/DiCoW_v3_3',
        'role': 'primary',
        'languages': ['ko', 'en', 'ja'],
        'speaker_mask': true,
      },
      {
        'name': 'faster_whisper',
        'model': 'large-v3',
        'role': 'rescue',
        'languages': ['ko', 'en', 'ja'],
        'speaker_mask': false,
      },
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

ProviderContainer containerWith(http.Client client) {
  final container = ProviderContainer(
    overrides: [
      restClientProvider.overrideWith(
        (ref) => RestClient(const ServerConfig(baseUrl: 'http://fake:1'), client: client),
      ),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  group('EngineCatalog.fromJson (S-26)', () {
    test('STT 엔진·라우팅·번역 모델을 읽는다', () {
      final c = EngineCatalog.fromJson(catalogJson);
      expect(c.sttDefault, 'auto');
      expect(c.routeByLang, {'ko': 'faster_whisper', 'ja': 'faster_whisper'});
      expect(c.sttEngines.map((e) => e.name), ['dicow', 'faster_whisper']);
      expect(c.sttByName('dicow')!.speakerMask, isTrue);
      expect(c.sttByName('dicow')!.roleLabel, '기본');
      expect(c.sttByName('faster_whisper')!.roleLabel, '구조');
      expect(c.mtEngine, 'ollama_llm');
      expect(c.mtDefaultModel, 'gemma2:9b');
      expect(c.mtModels.map((m) => m.name), ['gemma2:9b', 'gemma3:12b-it-qat']);
      expect(c.mtByName('gemma2:9b')!.sizeLabel, '5.0 GB');
      expect(c.isEmpty, isFalse);
    });

    test('auto 설명은 언어별 라우팅과 기본 엔진을 묶어 보여 준다', () {
      final c = EngineCatalog.fromJson(catalogJson);
      expect(c.autoDescription, '언어별 (ko·ja → faster_whisper, 그 외 → dicow)');
    });

    test('번역 꺼진 서버(passthrough)·빈 목록도 깨지지 않는다', () {
      final c = EngineCatalog.fromJson({
        'stt': {'default': 'auto', 'route_by_lang': {}, 'engines': []},
        'mt': {'engine': 'passthrough', 'default_model': null, 'models': []},
      });
      expect(c.isEmpty, isTrue);
      expect(c.mtDefaultModel, isNull);
      expect(c.autoDescription, '서버가 고름');
      expect(EngineCatalog.fromJson(const {}).isEmpty, isTrue);
    });

    test('권장 = STT auto + 서버 기본 모델 (+ 서버 recommended 플래그)', () {
      final c = EngineCatalog.fromJson(catalogJson);
      expect(c.isSttRecommended('auto'), isTrue);
      expect(c.isSttRecommended('dicow'), isFalse);
      expect(c.recommendedSttEngines, isEmpty);
      expect(c.isMtRecommended('gemma2:9b'), isTrue); // default_model
      expect(c.isMtRecommended('gemma3:12b-it-qat'), isFalse);
      expect(c.recommendedMtModels.map((m) => m.name), ['gemma2:9b']);

      final flagged = EngineCatalog.fromJson({
        'stt': {
          'default': 'auto',
          'route_by_lang': {},
          'engines': [{'name': 'x', 'recommended': true}, {'name': 'y'}],
        },
        'mt': {
          'engine': 'ollama_llm',
          'default_model': 'a',
          'models': [{'name': 'a'}, {'name': 'b', 'recommended': true}, {'name': 'c'}],
        },
      });
      expect(flagged.isSttRecommended('x'), isTrue);
      expect(flagged.recommendedSttEngines.single.name, 'x');
      expect(flagged.recommendedMtModels.map((m) => m.name), ['a', 'b']);
    });

    test('routingHint: 언어별 라우팅이 있으면 언어 지정 안내, 없으면 null', () {
      final c = EngineCatalog.fromJson(catalogJson);
      expect(c.routingHint, contains("'한국어'(ko) → faster_whisper"));
      expect(c.routingHint, contains("'일본어'(ja) → faster_whisper"));
      expect(c.routingHint, contains('방송 언어를 해당 언어로 지정'));
      expect(EngineCatalog.fromJson(const {}).routingHint, isNull);
    });

    test('MtModelInfo.sizeLabel: 1 GB 미만은 MB, 모르면 null', () {
      expect(const MtModelInfo(name: 'x', sizeMb: 621).sizeLabel, '621 MB');
      expect(const MtModelInfo(name: 'x').sizeLabel, isNull);
    });
  });

  group('세션 요청의 stt.engine / mt.model (S-26)', () {
    test('기본 선택이면 요청 JSON 에 stt·mt 키가 없다 (구 서버와 같은 요청)', () {
      const sel = EngineSelection();
      expect(sel.isDefault, isTrue);
      expect(sel.sttEngineForRequest, isNull);
      final j = SessionRequest.mic(
        srcLang: 'ja',
        sttEngine: sel.sttEngineForRequest,
        mtModel: sel.mtModel,
      ).toJson();
      expect(j.containsKey('stt'), isFalse);
      expect(j.containsKey('mt'), isFalse);
    });

    test('엔진·모델을 고르면 stt: {engine}, mt: {model} 로 간다 — 모드 A·B·C 모두', () {
      const sel = EngineSelection(sttEngine: 'faster_whisper', mtModel: 'gemma3:12b-it-qat');
      final a = const WatchSettings(sourceKind: WatchSourceKind.obs)
          .toRequest(sttEngine: sel.sttEngineForRequest, mtModel: sel.mtModel)
          .toJson();
      final b = SessionRequest.broadcast(
        target: 'system',
        srcLang: 'auto',
        sttEngine: sel.sttEngineForRequest,
        mtModel: sel.mtModel,
      ).toJson();
      final c = SessionRequest.mic(
        srcLang: 'auto',
        sttEngine: sel.sttEngineForRequest,
        mtModel: sel.mtModel,
      ).toJson();
      for (final j in [a, b, c]) {
        expect(j['stt'], {'engine': 'faster_whisper'});
        expect(j['mt'], {'model': 'gemma3:12b-it-qat'});
      }
    });

    test('모델만 골라도 stt 는 생략되고 expectsModelSwap 이 참이다', () {
      final r = SessionRequest.mic(srcLang: 'ko', mtModel: 'gemma2:9b');
      final j = r.toJson();
      expect(j.containsKey('stt'), isFalse);
      expect(j['mt'], {'model': 'gemma2:9b'});
      expect(r.expectsModelSwap, isTrue);
      expect(SessionRequest.mic(srcLang: 'ko').expectsModelSwap, isFalse);
    });
  });

  group('EngineController', () {
    test('/api/engines 404 → unsupported, 선택 칸 숨김', () async {
      final container = containerWith(MockClient((req) async => http.Response('Not Found', 404)));
      await container.read(engineControllerProvider.notifier).load();
      final s = container.read(engineControllerProvider);
      expect(s.status, EngineCatalogStatus.unsupported);
      expect(s.showPicker, isFalse);
    });

    test('정상 응답 → ready, 선택은 기본(auto·null)', () async {
      final container = containerWith(
        MockClient((req) async => http.Response(jsonEncode(catalogJson), 200)),
      );
      await container.read(engineControllerProvider.notifier).load();
      final s = container.read(engineControllerProvider);
      expect(s.status, EngineCatalogStatus.ready);
      expect(s.showPicker, isTrue);
      expect(s.selection, const EngineSelection());
      expect(s.mtSwapExpected, isFalse);
    });

    test('선택 → 요청값, 기본 모델과 다르면 mtSwapExpected', () async {
      final container = containerWith(
        MockClient((req) async => http.Response(jsonEncode(catalogJson), 200)),
      );
      final ctrl = container.read(engineControllerProvider.notifier);
      await ctrl.load();
      ctrl.selectStt('dicow');
      ctrl.selectMt('gemma3:12b-it-qat');
      var s = container.read(engineControllerProvider);
      expect(s.selection.sttEngineForRequest, 'dicow');
      expect(s.selection.mtModel, 'gemma3:12b-it-qat');
      expect(s.mtSwapExpected, isTrue);

      ctrl.selectMt('gemma2:9b');
      expect(container.read(engineControllerProvider).mtSwapExpected, isFalse);
      ctrl.selectMt(null);
      s = container.read(engineControllerProvider);
      expect(s.selection.mtModel, isNull);
      expect(s.selection.isDefault, isFalse); // stt 는 아직 dicow
    });

    test('다시 받은 카탈로그에 없는 선택은 기본으로 돌아간다', () async {
      var body = catalogJson;
      final container = containerWith(
        MockClient((req) async => http.Response(jsonEncode(body), 200)),
      );
      final ctrl = container.read(engineControllerProvider.notifier);
      await ctrl.load();
      ctrl.selectStt('faster_whisper');
      ctrl.selectMt('gemma3:12b-it-qat');

      body = {
        'stt': {'default': 'auto', 'route_by_lang': {}, 'engines': [((catalogJson['stt'] as Map)['engines'] as List)[0]]},
        'mt': {'engine': 'ollama_llm', 'default_model': 'gemma2:9b', 'models': [{'name': 'gemma2:9b'}]},
      };
      await ctrl.load();
      final s = container.read(engineControllerProvider).selection;
      expect(s.sttEngine, 'auto');
      expect(s.mtModel, isNull);
    });

    test('500 → failed + 오류 문구', () async {
      final container = containerWith(
        MockClient((req) async => http.Response('{"detail":{"code":"E_X","message":"boom"}}', 500)),
      );
      await container.read(engineControllerProvider.notifier).load();
      final s = container.read(engineControllerProvider);
      expect(s.status, EngineCatalogStatus.failed);
      expect(s.error, contains('E_X'));
      expect(s.showPicker, isTrue); // 재시도 버튼을 보여 주기 위해 칸은 남긴다
    });
  });

  group('RestClient (S-26)', () {
    test('engines() 는 GET /api/engines 를 부른다', () async {
      Uri? called;
      final client = RestClient(
        const ServerConfig(baseUrl: 'http://fake:1'),
        client: MockClient((req) async {
          called = req.url;
          return http.Response(jsonEncode(catalogJson), 200);
        }),
      );
      final c = await client.engines();
      expect(called.toString(), 'http://fake:1/api/engines');
      expect(c.mtDefaultModel, 'gemma2:9b');
    });

    test('번역 모델을 바꾼 세션 생성은 긴 타임아웃을 쓴다', () async {
      final client = RestClient(
        const ServerConfig(baseUrl: 'http://fake:1'),
        timeout: const Duration(milliseconds: 50),
        modelSwapTimeout: const Duration(seconds: 5),
        client: MockClient((req) async {
          await Future<void>.delayed(const Duration(milliseconds: 200));
          return http.Response('{"session_id":"s1"}', 200);
        }),
      );
      // 기본 요청은 50 ms 에 타임아웃.
      await expectLater(
        client.createSession(SessionRequest.mic(srcLang: 'ko')),
        throwsA(isA<Object>()),
      );
      // 모델 교체 요청은 200 ms 를 기다려 준다.
      final info = await client.createSession(SessionRequest.mic(srcLang: 'ko', mtModel: 'gemma3:12b-it-qat'));
      expect(info.sessionId, 's1');
    });

    test('400 E_STT_ENGINE / E_MT_MODEL 은 사용자 문구로', () {
      final e1 = ApiException.fromResponse(http.Response.bytes(
        utf8.encode('{"detail":{"code":"E_STT_ENGINE","message":"STT 엔진 \'x\' 는 떠 있지 않습니다"}}'),
        400,
      ));
      expect(describeEngineError(e1), contains('STT 엔진이 서버에 떠 있지 않습니다'));
      final e2 = ApiException.fromResponse(http.Response.bytes(
        utf8.encode('{"detail":{"code":"E_MT_MODEL","message":"번역 모델 \'y\' 을 쓸 수 없습니다"}}'),
        400,
      ));
      expect(describeEngineError(e2), contains('번역 모델을 서버가 쓸 수 없습니다'));
      expect(describeEngineError(ApiException('x', code: 'E_OTHER')), isNull);
    });
  });
}

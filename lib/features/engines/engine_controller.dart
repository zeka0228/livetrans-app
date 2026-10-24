import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/rest_client.dart';
import '../../core/models/engines.dart';

/// `GET /api/engines` 상태. 구 서버(404·501)는 [unsupported] 로 두고 선택 UI 를 숨긴다.
enum EngineCatalogStatus { unknown, loading, unsupported, ready, failed }

class EngineState {
  const EngineState({
    this.status = EngineCatalogStatus.unknown,
    this.catalog,
    this.error,
    this.selection = const EngineSelection(),
  });

  final EngineCatalogStatus status;
  final EngineCatalog? catalog;
  final String? error;

  /// 세 화면(시청·방송·마이크)이 공유하는 선택값. 세션 중 변경은 미지원 → 다음 세션부터 (S-26).
  final EngineSelection selection;

  /// 선택 칸을 보여 줄지. 미지원·빈 카탈로그면 숨긴다.
  bool get showPicker => switch (status) {
        EngineCatalogStatus.unsupported => false,
        EngineCatalogStatus.ready => !(catalog?.isEmpty ?? true),
        _ => true,
      };

  /// 선택한 번역 모델이 서버 기본과 다르면 첫 세션 시작이 모델 교체(수 초~수십 초)만큼 늦다.
  bool get mtSwapExpected {
    final m = selection.mtModel;
    return m != null && m != catalog?.mtDefaultModel;
  }

  EngineState copyWith({
    EngineCatalogStatus? status,
    EngineCatalog? catalog,
    String? error,
    bool clearError = false,
    EngineSelection? selection,
  }) =>
      EngineState(
        status: status ?? this.status,
        catalog: catalog ?? this.catalog,
        error: clearError ? null : (error ?? this.error),
        selection: selection ?? this.selection,
      );
}

/// 엔진·모델 카탈로그를 한 번 받아 두고 세 화면이 같은 선택값을 쓴다 (API 계약 S-26).
class EngineController extends Notifier<EngineState> {
  @override
  EngineState build() => const EngineState();

  Future<void> load() async {
    if (state.status == EngineCatalogStatus.loading) return;
    state = state.copyWith(status: EngineCatalogStatus.loading, clearError: true);
    try {
      final catalog = await ref.read(restClientProvider).engines();
      state = state.copyWith(
        status: EngineCatalogStatus.ready,
        catalog: catalog,
        selection: _reconcile(state.selection, catalog),
      );
    } on ApiException catch (e) {
      if (e.statusCode == 404 || e.statusCode == 501 || e.code == 'E_NOT_IMPLEMENTED') {
        state = const EngineState(status: EngineCatalogStatus.unsupported);
        return;
      }
      state = state.copyWith(status: EngineCatalogStatus.failed, error: '서버 응답 오류: $e');
    } on TimeoutException {
      state = state.copyWith(status: EngineCatalogStatus.failed, error: '서버 응답 시간 초과');
    } catch (e) {
      state = state.copyWith(status: EngineCatalogStatus.failed, error: '연결 실패: $e');
    }
  }

  /// 서버 주소가 바뀌면 처음부터 다시. 선택은 새 카탈로그에 없으면 기본으로 돌아간다.
  Future<void> onServerChanged() async {
    state = EngineState(selection: state.selection);
    // restClientProvider 가 새 주소로 다시 만들어진 뒤에 읽도록 한 틱 미룬다.
    await Future<void>.delayed(Duration.zero);
    await load();
  }

  void selectStt(String engine) =>
      state = state.copyWith(selection: state.selection.copyWith(sttEngine: engine));

  /// null = 서버 기본 모델.
  void selectMt(String? model) => state = state.copyWith(
        selection: model == null
            ? state.selection.copyWith(clearMtModel: true)
            : state.selection.copyWith(mtModel: model),
      );

  /// 카탈로그에 없는 선택값은 기본으로 되돌린다 (서버 재기동으로 엔진 구성이 바뀐 경우).
  static EngineSelection _reconcile(EngineSelection s, EngineCatalog c) {
    final stt = s.sttEngine == 'auto' || c.sttByName(s.sttEngine) != null ? s.sttEngine : 'auto';
    final mt = s.mtModel == null || c.mtByName(s.mtModel!) != null ? s.mtModel : null;
    return EngineSelection(sttEngine: stt, mtModel: mt);
  }
}

final engineControllerProvider =
    NotifierProvider<EngineController, EngineState>(EngineController.new);

/// 세션 생성 400 오류를 사용자 문구로 (S-26 `E_STT_ENGINE`·`E_MT_MODEL`). 해당 없으면 null.
String? describeEngineError(ApiException e) => switch (e.code) {
      'E_STT_ENGINE' =>
        '선택한 STT 엔진이 서버에 떠 있지 않습니다. 엔진 목록을 새로 고친 뒤 다시 고르세요. (${e.message})',
      'E_MT_MODEL' =>
        '선택한 번역 모델을 서버가 쓸 수 없습니다 (Ollama 에 없거나 로드 실패). 다른 모델을 고르세요. (${e.message})',
      _ => null,
    };

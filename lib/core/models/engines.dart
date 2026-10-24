/// `GET /api/engines` (API 계약 S-26) — 세션에서 고를 수 있는 STT 엔진·번역 모델.
///
/// STT 는 서버에 **떠 있는** 엔진만, 번역 모델은 Ollama 에 **설치된** 것만 온다.
/// 세션 요청에는 `stt: {engine}` (`auto` 또는 [SttEngineInfo.name]) · `mt: {model}` (null = 서버 기본
/// 또는 [MtModelInfo.name]) 으로 넘긴다. 구 서버는 이 엔드포인트가 없어(404) 선택 UI 를 숨긴다.
class EngineCatalog {
  const EngineCatalog({
    this.sttDefault = 'auto',
    this.routeByLang = const {},
    this.sttEngines = const [],
    this.mtEngine = 'none',
    this.mtDefaultModel,
    this.mtModels = const [],
  });

  /// 서버 기본 STT 선택값 (지금은 항상 `auto`).
  final String sttDefault;

  /// `auto` 일 때 언어별로 가는 엔진 (`{"ko": "faster_whisper", "ja": "faster_whisper"}`).
  final Map<String, String> routeByLang;
  final List<SttEngineInfo> sttEngines;

  /// 번역 플러그인 이름 (`ollama_llm` · `passthrough` · `none`).
  final String mtEngine;

  /// 서버 기본 번역 모델. 번역이 꺼진 서버(passthrough)면 null.
  final String? mtDefaultModel;
  final List<MtModelInfo> mtModels;

  bool get hasStt => sttEngines.isNotEmpty;
  bool get hasMt => mtModels.isNotEmpty;

  /// 카탈로그가 비어 있으면(엔진 0·모델 0) 고를 것이 없다 → UI 를 숨긴다.
  bool get isEmpty => !hasStt && !hasMt;

  SttEngineInfo? sttByName(String name) {
    for (final e in sttEngines) {
      if (e.name == name) return e;
    }
    return null;
  }

  MtModelInfo? mtByName(String name) {
    for (final m in mtModels) {
      if (m.name == name) return m;
    }
    return null;
  }

  /// 권장 STT 선택: `auto`(서버가 언어별로 고름) + 서버가 `recommended: true` 로 표시한 엔진.
  bool isSttRecommended(String name) => name == 'auto' || (sttByName(name)?.recommended ?? false);

  /// 권장 번역 모델: 서버 기본 모델(백엔드 벤치로 정함) + 서버가 `recommended: true` 로 표시한 모델.
  bool isMtRecommended(String name) => name == mtDefaultModel || (mtByName(name)?.recommended ?? false);

  List<SttEngineInfo> get recommendedSttEngines => [for (final e in sttEngines) if (e.recommended) e];
  List<MtModelInfo> get recommendedMtModels => [for (final m in mtModels) if (isMtRecommended(m.name)) m];

  /// 언어별 라우팅 안내: "일본어 방송은 방송 언어를 '일본어'로 지정해야 첫 문장부터 faster_whisper 로 갑니다".
  /// 자동 감지면 기본 엔진이 언어를 오판해 라우팅이 안 걸릴 수 있다 (인수인계 (22) 백엔드 벤치).
  String? get routingHint {
    if (routeByLang.isEmpty) return null;
    final parts = [
      for (final e in routeByLang.entries) "'${_langLabel(e.key)}'(${e.key}) → ${e.value}",
    ];
    return '${parts.join(', ')} 로 가려면 방송 언어를 해당 언어로 지정하세요. "자동"이면 첫 문장이 기본 엔진으로 갈 수 있어요.';
  }

  static String _langLabel(String code) => switch (code) {
        'ko' => '한국어',
        'en' => '영어',
        'ja' => '일본어',
        _ => code,
      };

  /// `auto` 설명: "언어별 (ko·ja → faster_whisper, 그 외 → dicow)".
  String get autoDescription {
    if (routeByLang.isEmpty) return '서버가 고름';
    final groups = <String, List<String>>{};
    for (final e in routeByLang.entries) {
      groups.putIfAbsent(e.value, () => []).add(e.key);
    }
    final parts = [for (final g in groups.entries) '${g.value.join('·')} → ${g.key}'];
    final primary = sttEngines.where((e) => e.role == 'primary').map((e) => e.name).firstOrNull;
    if (primary != null && !groups.containsKey(primary)) parts.add('그 외 → $primary');
    return '언어별 (${parts.join(', ')})';
  }

  factory EngineCatalog.fromJson(Map<String, dynamic> j) {
    final stt = (j['stt'] as Map?)?.cast<String, dynamic>() ?? const {};
    final mt = (j['mt'] as Map?)?.cast<String, dynamic>() ?? const {};
    return EngineCatalog(
      sttDefault: stt['default']?.toString() ?? 'auto',
      routeByLang: {
        for (final e in ((stt['route_by_lang'] as Map?) ?? const {}).entries)
          e.key.toString(): e.value.toString(),
      },
      sttEngines: [
        for (final e in (stt['engines'] as List?) ?? const [])
          if (e is Map) SttEngineInfo.fromJson(e.cast<String, dynamic>()),
      ],
      mtEngine: mt['engine']?.toString() ?? 'none',
      mtDefaultModel: mt['default_model'] as String?,
      mtModels: [
        for (final m in (mt['models'] as List?) ?? const [])
          if (m is Map) MtModelInfo.fromJson(m.cast<String, dynamic>()),
      ],
    );
  }
}

class SttEngineInfo {
  const SttEngineInfo({
    required this.name,
    this.model,
    this.role = 'primary',
    this.languages = const [],
    this.speakerMask = false,
    this.recommended = false,
  });

  /// 세션 요청 `stt.engine` 에 넣는 값 (`dicow` · `faster_whisper`).
  final String name;

  /// 모델 ID (`BUT-FIT/DiCoW_v3_3` · `large-v3`).
  final String? model;

  /// `primary`(기본) · `rescue`(구조 엔진).
  final String role;
  final List<String> languages;

  /// 화자 마스크 디코딩 지원 — 겹치는 발화를 화자별로 받아 적을 수 있다 (DiCoW).
  final bool speakerMask;

  /// 서버가 권장으로 표시한 엔진 (선택 필드 `recommended`, 없으면 false).
  final bool recommended;

  String get roleLabel => switch (role) {
        'primary' => '기본',
        'rescue' => '구조',
        _ => role,
      };

  factory SttEngineInfo.fromJson(Map<String, dynamic> j) => SttEngineInfo(
        name: j['name'].toString(),
        model: j['model'] as String?,
        role: j['role']?.toString() ?? 'primary',
        languages: (j['languages'] as List?)?.map((e) => e.toString()).toList() ?? const [],
        speakerMask: j['speaker_mask'] == true,
        recommended: j['recommended'] == true,
      );
}

class MtModelInfo {
  const MtModelInfo({required this.name, this.sizeMb, this.recommended = false});

  /// Ollama 모델 이름 (`gemma2:9b` · `gemma3:12b-it-qat`). 세션 요청 `mt.model`.
  final String name;
  final int? sizeMb;

  /// 서버가 권장으로 표시한 모델 (선택 필드 `recommended`, 없으면 false). 서버 기본 모델은 항상 권장으로 본다.
  final bool recommended;

  /// "5.2 GB" 처럼 보여 준다. 크기를 모르면 null.
  String? get sizeLabel {
    final mb = sizeMb;
    if (mb == null) return null;
    return mb >= 1024 ? '${(mb / 1024).toStringAsFixed(1)} GB' : '$mb MB';
  }

  factory MtModelInfo.fromJson(Map<String, dynamic> j) => MtModelInfo(
        name: j['name'].toString(),
        sizeMb: (j['size_mb'] as num?)?.round(),
        recommended: j['recommended'] == true,
      );
}

/// 사용자가 고른 값. [sttEngine] 은 `auto` 또는 엔진 이름, [mtModel] 은 null(서버 기본) 또는 모델 이름.
class EngineSelection {
  const EngineSelection({this.sttEngine = 'auto', this.mtModel});

  final String sttEngine;
  final String? mtModel;

  bool get isDefault => sttEngine == 'auto' && mtModel == null;

  /// 세션 요청에 보낼 값. 기본값이면 null → 요청 JSON 에 `stt`/`mt` 를 넣지 않는다 (구 서버와 같은 요청).
  String? get sttEngineForRequest => sttEngine == 'auto' ? null : sttEngine;

  EngineSelection copyWith({String? sttEngine, String? mtModel, bool clearMtModel = false}) =>
      EngineSelection(
        sttEngine: sttEngine ?? this.sttEngine,
        mtModel: clearMtModel ? null : (mtModel ?? this.mtModel),
      );

  @override
  bool operator ==(Object other) =>
      other is EngineSelection && other.sttEngine == sttEngine && other.mtModel == mtModel;

  @override
  int get hashCode => Object.hash(sttEngine, mtModel);
}

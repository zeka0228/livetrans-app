import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/server_config.dart';
import '../../core/models/engines.dart';
import 'engine_controller.dart';

/// 세션 시작 전 STT 엔진·번역 모델 선택 (API 계약 S-26, 사용자 요청 2026-10-25).
///
/// - 서버가 `GET /api/engines` 를 주지 않으면(구 서버) 아무것도 그리지 않는다. 처음 보일 때 카탈로그를 받는다.
/// - **권장 항목만 기본으로 보인다**: STT 는 `auto`(서버가 언어별로 고름), 번역은 서버 기본 모델(백엔드 벤치로 정함).
///   나머지는 "전체 보기" 를 눌러야 목록에 들어온다. 권장 항목엔 "권장" 배지.
/// - [compact] 는 방송·마이크 화면처럼 세로 공간이 좁은 곳용 (설명 줄 생략).
class EnginePicker extends ConsumerStatefulWidget {
  const EnginePicker({super.key, required this.enabled, this.compact = false});

  final bool enabled;
  final bool compact;

  @override
  ConsumerState<EnginePicker> createState() => _EnginePickerState();
}

class _EnginePickerState extends ConsumerState<EnginePicker> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (ref.read(engineControllerProvider).status == EngineCatalogStatus.unknown) {
        ref.read(engineControllerProvider.notifier).load();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(engineControllerProvider);
    final controller = ref.read(engineControllerProvider.notifier);
    ref.listen(serverConfigProvider, (prev, next) {
      if (prev?.baseUrl != next.baseUrl) controller.onServerChanged();
    });
    if (!state.showPicker) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;

    final Widget body = switch (state.status) {
      EngineCatalogStatus.unknown || EngineCatalogStatus.loading => Row(
          children: [
            const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
            const SizedBox(width: 10),
            Text('서버의 엔진·모델 목록을 받는 중…',
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
          ],
        ),
      EngineCatalogStatus.failed => Row(
          children: [
            Icon(Icons.error_outline_rounded, size: 16, color: scheme.error),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                state.error ?? '엔진 목록을 가져오지 못했어요',
                style: TextStyle(fontSize: 12, color: scheme.error),
              ),
            ),
            TextButton(onPressed: controller.load, child: const Text('다시 시도')),
          ],
        ),
      EngineCatalogStatus.unsupported => const SizedBox.shrink(),
      EngineCatalogStatus.ready => _Dropdowns(
          catalog: state.catalog!,
          selection: state.selection,
          enabled: widget.enabled,
          swapExpected: state.mtSwapExpected,
          onStt: controller.selectStt,
          onMt: controller.selectMt,
        ),
    };

    return Card(
      child: Padding(
        padding: EdgeInsets.all(widget.compact ? 12 : 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!widget.compact) ...[
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '인식 엔진과 번역 모델을 세션마다 고를 수 있어요. 기본으로는 권장 항목만 보이고, 시작 뒤에는 바꿀 수 없습니다(다음 세션부터 적용).',
                      style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant, height: 1.4),
                    ),
                  ),
                  IconButton(
                    tooltip: '엔진 목록 새로 고침',
                    onPressed: widget.enabled && state.status != EngineCatalogStatus.loading
                        ? controller.load
                        : null,
                    icon: const Icon(Icons.refresh_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 6),
            ],
            body,
          ],
        ),
      ),
    );
  }
}

class _Dropdowns extends StatefulWidget {
  const _Dropdowns({
    required this.catalog,
    required this.selection,
    required this.enabled,
    required this.swapExpected,
    required this.onStt,
    required this.onMt,
  });

  final EngineCatalog catalog;
  final EngineSelection selection;
  final bool enabled;
  final bool swapExpected;
  final ValueChanged<String> onStt;
  final ValueChanged<String?> onMt;

  @override
  State<_Dropdowns> createState() => _DropdownsState();
}

class _DropdownsState extends State<_Dropdowns> {
  /// "전체 보기" 를 눌렀는가. 권장이 아닌 항목이 선택돼 있으면 자동으로 펼친다.
  bool _showAllStt = false;
  bool _showAllMt = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final c = widget.catalog;
    final sel = widget.selection;

    // ---- STT ----
    final sttSelectedIsRec = c.isSttRecommended(sel.sttEngine);
    final showAllStt = _showAllStt || !sttSelectedIsRec;
    final sttEngines = showAllStt ? c.sttEngines : c.recommendedSttEngines;
    final sttHidden = c.sttEngines.length - sttEngines.length;

    // ---- MT ---- ("서버 기본" 항목이 기본 모델을 대신하므로 목록에서 기본 모델은 뺀다)
    final mtSelected = sel.mtModel;
    final mtSelectedIsRec = mtSelected == null || c.isMtRecommended(mtSelected);
    final showAllMt = _showAllMt || !mtSelectedIsRec;
    final mtModels = [
      for (final m in c.mtModels)
        if (m.name != c.mtDefaultModel && (showAllMt || c.isMtRecommended(m.name))) m,
    ];
    final mtHidden = c.mtModels.where((m) => m.name != c.mtDefaultModel).length - mtModels.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (c.hasStt) ...[
          DropdownButtonFormField<String>(
            key: const Key('engine-picker-stt'),
            isExpanded: true,
            initialValue: sel.sttEngine,
            decoration: const InputDecoration(
              labelText: 'STT 엔진 (음성 인식)',
              prefixIcon: Icon(Icons.hearing_rounded),
              isDense: true,
            ),
            items: [
              DropdownMenuItem(
                value: 'auto',
                child: _ItemText(title: '자동', detail: c.autoDescription, recommended: true),
              ),
              for (final e in sttEngines)
                DropdownMenuItem(
                  value: e.name,
                  child: _ItemText(
                    title: e.name,
                    detail: [
                      if (e.model != null) e.model!,
                      e.roleLabel,
                      if (e.speakerMask) '화자 마스크',
                      if (e.languages.isNotEmpty) e.languages.join('·'),
                    ].join(' · '),
                    recommended: e.recommended,
                  ),
                ),
            ],
            onChanged: widget.enabled ? (v) => v == null ? null : widget.onStt(v) : null,
          ),
          _MoreRow(
            hidden: sttHidden,
            expanded: showAllStt,
            label: '엔진 직접 지정',
            keyName: 'engine-picker-stt-more',
            enabled: widget.enabled && sttSelectedIsRec,
            onToggle: () => setState(() => _showAllStt = !_showAllStt),
          ),
          if (c.routingHint != null) _Hint(icon: Icons.language_rounded, text: c.routingHint!),
          if (c.hasMt) const SizedBox(height: 10),
        ],
        if (c.hasMt) ...[
          DropdownButtonFormField<String>(
            key: const Key('engine-picker-mt'),
            isExpanded: true,
            // null(서버 기본)은 드롭다운 값으로 쓸 수 없어 빈 문자열로 표현한다.
            initialValue: mtSelected ?? '',
            decoration: const InputDecoration(
              labelText: '번역 모델 (Ollama)',
              prefixIcon: Icon(Icons.translate_rounded),
              isDense: true,
            ),
            items: [
              DropdownMenuItem(
                value: '',
                child: _ItemText(
                  title: '서버 기본',
                  detail: c.mtDefaultModel == null
                      ? '번역 꺼짐 (passthrough)'
                      : _mtDetail(c, c.mtDefaultModel!),
                  recommended: c.mtDefaultModel != null,
                ),
              ),
              for (final m in mtModels)
                DropdownMenuItem(
                  value: m.name,
                  child: _ItemText(
                    title: m.name,
                    detail: m.sizeLabel ?? '',
                    recommended: c.isMtRecommended(m.name),
                  ),
                ),
            ],
            onChanged: widget.enabled ? (v) => widget.onMt(v == null || v.isEmpty ? null : v) : null,
          ),
          _MoreRow(
            hidden: mtHidden,
            expanded: showAllMt,
            label: '다른 모델',
            keyName: 'engine-picker-mt-more',
            enabled: widget.enabled && mtSelectedIsRec,
            onToggle: () => setState(() => _showAllMt = !_showAllMt),
          ),
          if (showAllMt && c.mtDefaultModel != null)
            _Hint(
              icon: Icons.info_outline_rounded,
              text: '서버 기본 모델은 백엔드 벤치에서 품질·지연이 가장 좋았던 것입니다. 큰 모델(12B 급 이상)은 서버와 VRAM 을 나눠 오히려 느릴 수 있어요.',
            ),
          if (widget.swapExpected)
            _Hint(
              icon: Icons.schedule_rounded,
              color: scheme.tertiary,
              text: '기본과 다른 번역 모델은 Ollama 가 교체해 올리므로 첫 세션 시작이 수 초~수십 초 걸릴 수 있어요.',
            ),
        ],
      ],
    );
  }

  static String _mtDetail(EngineCatalog c, String name) {
    final size = c.mtByName(name)?.sizeLabel;
    return size == null ? name : '$name · $size';
  }
}

/// "전체 보기 (N개 더)" / "권장만 보기" 토글. 숨긴 것이 없으면 아무것도 그리지 않는다.
class _MoreRow extends StatelessWidget {
  const _MoreRow({
    required this.hidden,
    required this.expanded,
    required this.label,
    required this.keyName,
    required this.enabled,
    required this.onToggle,
  });

  final int hidden;
  final bool expanded;
  final String label;
  final String keyName;
  final bool enabled;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    if (hidden == 0 && !expanded) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.centerRight,
      child: TextButton.icon(
        key: Key(keyName),
        style: TextButton.styleFrom(visualDensity: VisualDensity.compact, foregroundColor: scheme.onSurfaceVariant),
        onPressed: enabled ? onToggle : null,
        icon: Icon(expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded, size: 16),
        label: Text(
          expanded ? '권장만 보기' : '$label 전체 보기 ($hidden개 더)',
          style: const TextStyle(fontSize: 11),
        ),
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint({required this.icon, required this.text, this.color});

  final IconData icon;
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 14, color: color ?? scheme.outline),
          const SizedBox(width: 6),
          Expanded(
            child: Text(text, style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant, height: 1.4)),
          ),
        ],
      ),
    );
  }
}

class _ItemText extends StatelessWidget {
  const _ItemText({required this.title, required this.detail, this.recommended = false});

  final String title;
  final String detail;
  final bool recommended;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        if (recommended) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              '권장',
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: scheme.onPrimaryContainer),
            ),
          ),
          const SizedBox(width: 6),
        ],
        Expanded(
          child: RichText(
            overflow: TextOverflow.ellipsis,
            text: TextSpan(
              style: DefaultTextStyle.of(context).style.copyWith(fontSize: 13),
              children: [
                TextSpan(text: title, style: const TextStyle(fontWeight: FontWeight.w600)),
                if (detail.isNotEmpty)
                  TextSpan(
                    text: '  $detail',
                    style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

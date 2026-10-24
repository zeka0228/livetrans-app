import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/server_config.dart';
import '../../core/models/engines.dart';
import 'engine_controller.dart';

/// 세션 시작 전 STT 엔진·번역 모델 선택 (API 계약 S-26, 사용자 요청 2026-10-25).
///
/// 서버가 `GET /api/engines` 를 주지 않으면(구 서버) 아무것도 그리지 않는다. 처음 보일 때 카탈로그를 받는다.
/// [compact] 는 방송·마이크 화면처럼 세로 공간이 좁은 곳용 (설명 줄 생략).
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
    final sel = state.selection;

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
          selection: sel,
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
                      '인식 엔진과 번역 모델을 세션마다 고를 수 있어요. 시작 뒤에는 바꿀 수 없고 다음 세션부터 적용됩니다.',
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

class _Dropdowns extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final c = catalog;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (c.hasStt) ...[
          DropdownButtonFormField<String>(
            key: const Key('engine-picker-stt'),
            isExpanded: true,
            initialValue: selection.sttEngine,
            decoration: const InputDecoration(
              labelText: 'STT 엔진 (음성 인식)',
              prefixIcon: Icon(Icons.hearing_rounded),
              isDense: true,
            ),
            items: [
              DropdownMenuItem(
                value: 'auto',
                child: _ItemText(title: '자동', detail: c.autoDescription),
              ),
              for (final e in c.sttEngines)
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
                  ),
                ),
            ],
            onChanged: enabled ? (v) => v == null ? null : onStt(v) : null,
          ),
          if (c.hasMt) const SizedBox(height: 10),
        ],
        if (c.hasMt)
          DropdownButtonFormField<String>(
            key: const Key('engine-picker-mt'),
            isExpanded: true,
            // null(서버 기본)은 드롭다운 값으로 쓸 수 없어 빈 문자열로 표현한다.
            initialValue: selection.mtModel ?? '',
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
                ),
              ),
              for (final m in c.mtModels)
                DropdownMenuItem(
                  value: m.name,
                  child: _ItemText(
                    title: m.name,
                    detail: [
                      if (m.sizeLabel != null) m.sizeLabel!,
                      if (m.name == c.mtDefaultModel) '서버 기본',
                    ].join(' · '),
                  ),
                ),
            ],
            onChanged: enabled ? (v) => onMt(v == null || v.isEmpty ? null : v) : null,
          ),
        if (swapExpected) ...[
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.schedule_rounded, size: 14, color: scheme.tertiary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '기본과 다른 번역 모델은 Ollama 가 교체해 올리므로 첫 세션 시작이 수 초~수십 초 걸릴 수 있어요. 12B 급 이상은 VRAM 사정에 따라 더 느려질 수 있습니다.',
                  style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant, height: 1.4),
                ),
              ),
            ],
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

class _ItemText extends StatelessWidget {
  const _ItemText({required this.title, required this.detail});

  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return RichText(
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
    );
  }
}

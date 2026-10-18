import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../transcript/transcript_entry.dart';
import '../transcript/transcript_list.dart';
import 'mic_controller.dart';

class MicScreen extends ConsumerWidget {
  const MicScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(micControllerProvider);
    final controller = ref.read(micControllerProvider.notifier);
    final locked = state.status == MicStatus.recording || state.isBusy;

    return Scaffold(
      appBar: AppBar(
        title: const Text('마이크 모드'),
        actions: [
          IconButton(
            tooltip: '기록 지우기',
            onPressed: state.entries.isEmpty ? null : controller.clearEntries,
            icon: const Icon(Icons.delete_sweep_outlined),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
            child: _LanguagePicker(
              selected: state.language,
              enabled: !locked,
              onChanged: controller.setLanguage,
            ),
          ),
          _StatusBar(state: state),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            alignment: Alignment.topCenter,
            child: state.partial == null
                ? const SizedBox(width: double.infinity)
                : _PartialBubble(text: state.partial!.text),
          ),
          Expanded(child: TranscriptList(entries: state.entries)),
          _RecordDock(
            state: state,
            onStart: controller.start,
            onStop: controller.stop,
          ),
        ],
      ),
    );
  }
}

class _LanguagePicker extends StatelessWidget {
  const _LanguagePicker({
    required this.selected,
    required this.enabled,
    required this.onChanged,
  });

  final String selected;
  final bool enabled;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          for (final e in micLanguages.entries)
            Expanded(
              child: _LangTab(
                label: e.value,
                active: e.key == selected,
                enabled: enabled,
                onTap: () => onChanged(e.key),
              ),
            ),
        ],
      ),
    );
  }
}

class _LangTab extends StatelessWidget {
  const _LangTab({
    required this.label,
    required this.active,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final bool active;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fg = active
        ? scheme.onPrimary
        : (enabled ? scheme.onSurfaceVariant : scheme.outline);
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: active ? scheme.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: fg,
            fontSize: 14,
            fontWeight: active ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

class _StatusBar extends StatelessWidget {
  const _StatusBar({required this.state});

  final MicState state;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (label, color) = switch (state.status) {
      MicStatus.idle => ('대기 중', scheme.outline),
      MicStatus.connecting => ('연결 중…', scheme.tertiary),
      MicStatus.recording => ('녹음 중', scheme.error),
      MicStatus.stopping => ('종료 중…', scheme.tertiary),
      MicStatus.error => ('오류', scheme.error),
    };
    final seconds = state.bytesSent / 32000;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _Dot(color: color, pulse: state.status == MicStatus.recording),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
              if (state.serverState != null) ...[
                const SizedBox(width: 8),
                _Tag(text: '서버 ${state.serverState}'),
              ],
              const Spacer(),
              if (state.status == MicStatus.recording)
                Text(
                  '${seconds.toStringAsFixed(1)} s 전송',
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurfaceVariant,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
            ],
          ),
          if (state.errorMessage != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    size: 15,
                    color: scheme.error,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      state.errorMessage!,
                      style: TextStyle(fontSize: 12, color: scheme.error),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
      ),
    );
  }
}

/// 상태 점. 녹음 중이면 천천히 깜빡인다.
class _Dot extends StatefulWidget {
  const _Dot({required this.color, required this.pulse});

  final Color color;
  final bool pulse;

  @override
  State<_Dot> createState() => _DotState();
}

class _DotState extends State<_Dot> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(covariant _Dot old) {
    super.didUpdateWidget(old);
    if (old.pulse != widget.pulse) _sync();
  }

  void _sync() {
    if (widget.pulse) {
      _c.repeat(reverse: true);
    } else {
      _c.stop();
      _c.value = 1;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween(begin: 0.35, end: 1.0).animate(_c),
      child: Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
      ),
    );
  }
}

class _PartialBubble extends StatelessWidget {
  const _PartialBubble({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        decoration: BoxDecoration(
          color: scheme.primaryContainer.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: scheme.primary.withValues(alpha: 0.25)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.graphic_eq_rounded, size: 14, color: scheme.primary),
                const SizedBox(width: 6),
                Text(
                  '듣는 중',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: scheme.primary,
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              text,
              style: TextStyle(
                fontSize: 16,
                height: 1.35,
                color: scheme.onPrimaryContainer,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RecordDock extends StatelessWidget {
  const _RecordDock({
    required this.state,
    required this.onStart,
    required this.onStop,
  });

  final MicState state;
  final Future<void> Function() onStart;
  final Future<void> Function() onStop;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final recording = state.status == MicStatus.recording;
    final accent = recording ? scheme.error : scheme.primary;
    final level = state.level.clamp(0.0, 1.0);
    final count = state.entries.length;
    final hint = state.entries.isEmpty
        ? '문장이 끝나면 아래 기록에 쌓입니다'
        : '문장 $count개 · 마지막 ${TranscriptEntry.formatMs(state.entries.last.tStartMs)}';

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 160,
                height: 160,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    _Ring(size: 96 + level * 64, color: accent, alpha: 0.10),
                    _Ring(size: 88 + level * 40, color: accent, alpha: 0.18),
                    Material(
                      color: accent,
                      shape: const CircleBorder(),
                      elevation: 6,
                      shadowColor: accent.withValues(alpha: 0.5),
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: state.isBusy
                            ? null
                            : (recording ? onStop : onStart),
                        child: SizedBox(
                          width: 80,
                          height: 80,
                          child: Center(
                            child: state.isBusy
                                ? const SizedBox(
                                    width: 26,
                                    height: 26,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 3,
                                      color: Colors.white,
                                    ),
                                  )
                                : Icon(
                                    recording
                                        ? Icons.stop_rounded
                                        : Icons.mic_rounded,
                                    size: 36,
                                    color: Colors.white,
                                  ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              Text(
                recording ? '탭하면 녹음을 끝냅니다' : '탭하면 녹음을 시작합니다',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 2),
              Text(hint, style: TextStyle(fontSize: 11, color: scheme.outline)),
            ],
          ),
        ),
      ),
    );
  }
}

class _Ring extends StatelessWidget {
  const _Ring({required this.size, required this.color, required this.alpha});

  final double size;
  final Color color;
  final double alpha;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 90),
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withValues(alpha: alpha),
      ),
    );
  }
}

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
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('마이크 모드 (STT)'),
        actions: [
          IconButton(
            tooltip: '기록 지우기',
            onPressed: state.entries.isEmpty ? null : controller.clearEntries,
            icon: const Icon(Icons.delete_sweep_outlined),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: SegmentedButton<String>(
              segments: [
                for (final e in micLanguages.entries)
                  ButtonSegment(value: e.key, label: Text(e.value)),
              ],
              selected: {state.language},
              onSelectionChanged: state.status == MicStatus.recording || state.isBusy
                  ? null
                  : (s) => controller.setLanguage(s.first),
            ),
          ),
          _StatusBar(state: state),
          if (state.partial != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: scheme.primaryContainer.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  state.partial!.text,
                  style: TextStyle(fontSize: 16, color: scheme.onPrimaryContainer),
                ),
              ),
            ),
          Expanded(child: TranscriptList(entries: state.entries)),
          _RecordButton(state: state, onStart: controller.start, onStop: controller.stop),
        ],
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
      MicStatus.idle => ('대기', scheme.outline),
      MicStatus.connecting => ('연결 중…', scheme.tertiary),
      MicStatus.recording => ('녹음 중', scheme.error),
      MicStatus.stopping => ('종료 중…', scheme.tertiary),
      MicStatus.error => ('오류', scheme.error),
    };
    final seconds = state.bytesSent / 32000;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.circle, size: 10, color: color),
              const SizedBox(width: 6),
              Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w600)),
              if (state.serverState != null) ...[
                const SizedBox(width: 10),
                Text('서버: ${state.serverState}',
                    style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
              ],
              const Spacer(),
              if (state.status == MicStatus.recording)
                Text('전송 ${seconds.toStringAsFixed(1)}s',
                    style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
            ],
          ),
          if (state.errorMessage != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(state.errorMessage!,
                  style: TextStyle(fontSize: 12, color: scheme.error)),
            ),
        ],
      ),
    );
  }
}

class _RecordButton extends StatelessWidget {
  const _RecordButton({
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
    final ringSize = 84 + (state.level * 60).clamp(0.0, 60.0);

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 150,
              height: 150,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 80),
                    width: ringSize,
                    height: ringSize,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: (recording ? scheme.error : scheme.primary)
                          .withValues(alpha: 0.18),
                    ),
                  ),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      shape: const CircleBorder(),
                      padding: const EdgeInsets.all(24),
                      backgroundColor: recording ? scheme.error : scheme.primary,
                    ),
                    onPressed: state.isBusy ? null : (recording ? onStop : onStart),
                    child: state.isBusy
                        ? const SizedBox(
                            width: 28,
                            height: 28,
                            child: CircularProgressIndicator(strokeWidth: 3, color: Colors.white),
                          )
                        : Icon(recording ? Icons.stop : Icons.mic, size: 32),
                  ),
                ],
              ),
            ),
            Text(
              recording ? '누르면 종료' : '누르면 녹음 시작',
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
            if (state.entries.isNotEmpty)
              Text(
                '마지막 문장 ${TranscriptEntry.formatMs(state.entries.last.tStartMs)}',
                style: TextStyle(fontSize: 11, color: scheme.outline),
              ),
          ],
        ),
      ),
    );
  }
}

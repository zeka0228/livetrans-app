import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/tts/tts_player.dart';
import '../transcript/session_widgets.dart';
import '../transcript/transcript_entry.dart';
import '../transcript/transcript_list.dart';
import '../transcript/tts_hooks.dart';
import 'mic_controller.dart';

class MicScreen extends ConsumerWidget {
  const MicScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(micControllerProvider);
    final controller = ref.read(micControllerProvider.notifier);
    final scheme = Theme.of(context).colorScheme;
    final locked = state.status == MicStatus.recording || state.isBusy;
    final tts = TranscriptTts(ref, 'mic');
    tts.listenErrors(context);
    final ttsState = ref.watch(ttsControllerProvider);
    final speakingKey = tts.speakingEntryKey(ttsState);
    final loadingKey = tts.loadingEntryKey(ttsState);

    final (label, color) = switch (state.status) {
      MicStatus.idle => ('대기 중', scheme.outline),
      MicStatus.connecting => ('연결 중…', scheme.tertiary),
      MicStatus.recording => ('녹음 중', scheme.error),
      MicStatus.stopping => ('마지막 문장 정리 중…', scheme.tertiary),
      MicStatus.error => ('오류', scheme.error),
    };
    final seconds = state.bytesSent / 32000;

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
            child: LanguagePicker(
              selected: state.language,
              enabled: !locked,
              onChanged: controller.setLanguage,
            ),
          ),
          SessionStatusBar(
            label: label,
            color: color,
            pulse: state.status == MicStatus.recording,
            serverState: state.serverState,
            trailing: state.status == MicStatus.recording
                ? '${seconds.toStringAsFixed(1)} s 전송'
                : null,
            errorMessage: state.errorMessage,
            warning: state.warning,
          ),
          PartialBubble(partials: state.partials),
          Expanded(
            child: TranscriptList(
              entries: state.entries,
              emptyHint: '녹음을 시작하고 말하면 문장 단위로 쌓입니다',
              onTapEntry: tts.toggle,
              speakingEntryKey: speakingKey,
              loadingEntryKey: loadingKey,
            ),
          ),
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

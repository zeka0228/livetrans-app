import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/capture_target.dart';
import '../../core/tts/tts_player.dart';
import '../transcript/session_widgets.dart';
import '../transcript/transcript_list.dart';
import '../transcript/tts_hooks.dart';
import 'broadcast_controller.dart';

/// 방송 자막 (모드 B): PC 에서 재생 중인 창을 골라 그 소리를 서버가 캡처 → 실시간 자막.
class BroadcastScreen extends ConsumerStatefulWidget {
  const BroadcastScreen({super.key});

  @override
  ConsumerState<BroadcastScreen> createState() => _BroadcastScreenState();
}

class _BroadcastScreenState extends ConsumerState<BroadcastScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(broadcastControllerProvider.notifier).refreshTargets();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(broadcastControllerProvider);
    final controller = ref.read(broadcastControllerProvider.notifier);
    final scheme = Theme.of(context).colorScheme;
    final locked = state.isRunning || state.isBusy;
    final tts = TranscriptTts(ref, 'broadcast');
    tts.listenErrors(context);
    final ttsState = ref.watch(ttsControllerProvider);
    final speakingKey = tts.speakingEntryKey(ttsState);
    final loadingKey = tts.loadingEntryKey(ttsState);

    final (label, color) = switch (state.status) {
      BroadcastStatus.idle => ('대기 중', scheme.outline),
      BroadcastStatus.loadingTargets => ('대상 목록 불러오는 중…', scheme.tertiary),
      BroadcastStatus.connecting => ('연결 중…', scheme.tertiary),
      BroadcastStatus.running => ('자막 중', scheme.error),
      BroadcastStatus.stopping => ('마지막 문장 정리 중…', scheme.tertiary),
      BroadcastStatus.error => ('오류', scheme.error),
    };

    return Scaffold(
      appBar: AppBar(
        title: const Text('방송 자막'),
        actions: [
          IconButton(
            tooltip: '대상 새로 고침',
            onPressed: state.status == BroadcastStatus.loadingTargets
                ? null
                : controller.refreshTargets,
            icon: const Icon(Icons.refresh_rounded),
          ),
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
            child: _TargetPicker(
              state: state,
              enabled: !locked,
              onSelect: controller.selectTarget,
              onRetry: controller.refreshTargets,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
            child: LanguagePicker(
              selected: state.language,
              enabled: !locked,
              onChanged: controller.setLanguage,
            ),
          ),
          SessionStatusBar(
            label: label,
            color: color,
            pulse: state.isRunning,
            serverState: state.serverState,
            trailing: state.isRunning && state.startedAt != null
                ? _Elapsed(since: state.startedAt!).text()
                : null,
            errorMessage: state.errorMessage,
            warning: state.warning,
          ),
          PartialBubble(text: state.partial?.text),
          Expanded(
            child: TranscriptList(
              entries: state.entries,
              emptyHint: '자막을 시작하면 방송의 문장이 여기에 쌓입니다',
              onTapEntry: tts.toggle,
              speakingEntryKey: speakingKey,
              loadingEntryKey: loadingKey,
            ),
          ),
          _StartDock(
            state: state,
            onStart: controller.start,
            onStop: controller.stop,
          ),
        ],
      ),
    );
  }
}

class _Elapsed {
  const _Elapsed({required this.since});

  final DateTime since;

  String text() {
    final d = DateTime.now().difference(since);
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s 경과';
  }
}

/// 캡처 대상 선택. 현재 선택을 한 줄로 보여주고, 누르면 목록 시트가 열린다.
class _TargetPicker extends StatelessWidget {
  const _TargetPicker({
    required this.state,
    required this.enabled,
    required this.onSelect,
    required this.onRetry,
  });

  final BroadcastState state;
  final bool enabled;
  final ValueChanged<String> onSelect;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final selected = state.selectedTarget;
    final loading = state.status == BroadcastStatus.loadingTargets;

    final String title;
    final String subtitle;
    final IconData icon;
    if (state.targetsError != null) {
      icon = Icons.error_outline_rounded;
      title = '대상 목록을 가져오지 못했어요';
      subtitle = state.targetsError!;
    } else if (!state.captureAvailable) {
      icon = Icons.build_circle_outlined;
      title = '서버에 캡처 도구가 없어요';
      subtitle = r'서버 PC 에서 scripts\build_wincap.bat 을 실행한 뒤 새로 고침하세요';
    } else if (loading && state.targets.isEmpty) {
      icon = Icons.hourglass_top_rounded;
      title = '대상 목록 불러오는 중…';
      subtitle = '서버에 캡처 가능한 창을 묻고 있어요';
    } else if (selected == null) {
      icon = Icons.help_outline_rounded;
      title = '캡처할 대상을 고르세요';
      subtitle = state.targets.isEmpty ? '목록이 비어 있어요' : '${state.targets.length}개 중 선택';
    } else {
      icon = selected.isSystem
          ? Icons.speaker_rounded
          : Icons.web_asset_rounded;
      title = selected.title;
      subtitle = selected.isSystem
          ? 'PC 전체 소리'
          : '${selected.process ?? '앱'}'
              '${selected.windows.length > 1 ? ' · 창 ${selected.windows.length}개' : ''}'
              ' · 같은 프로그램의 다른 탭 소리도 함께 잡혀요';
    }

    return Material(
      color: scheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: !enabled
            ? null
            : (state.targetsError != null || !state.captureAvailable)
                ? onRetry
                : () => _openSheet(context),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: scheme.primaryContainer.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: scheme.primary, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                enabled ? Icons.expand_more_rounded : Icons.lock_outline_rounded,
                color: scheme.outline,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openSheet(BuildContext context) async {
    final id = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => _TargetSheet(
        targets: state.targets,
        selectedId: state.selectedTargetId,
        appCaptureSupported: state.appCaptureSupported,
      ),
    );
    if (id != null) onSelect(id);
  }
}

class _TargetSheet extends StatelessWidget {
  const _TargetSheet({
    required this.targets,
    required this.selectedId,
    required this.appCaptureSupported,
  });

  final List<CaptureTarget> targets;
  final String? selectedId;
  final bool appCaptureSupported;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Row(
              children: [
                const Text(
                  '캡처할 대상',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                Text(
                  '${targets.length}개',
                  style: TextStyle(fontSize: 12, color: scheme.outline),
                ),
              ],
            ),
          ),
          if (!appCaptureSupported)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                '이 PC 에서는 창별 캡처를 지원하지 않아 PC 전체 소리만 고를 수 있어요',
                style: TextStyle(fontSize: 12, color: scheme.tertiary),
              ),
            ),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: targets.length,
              itemBuilder: (ctx, i) {
                final t = targets[i];
                final disabled = !appCaptureSupported && !t.isSystem;
                final active = t.id == selectedId;
                return ListTile(
                  enabled: !disabled,
                  selected: active,
                  leading: Icon(
                    t.isSystem ? Icons.speaker_rounded : Icons.web_asset_rounded,
                  ),
                  title: Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                  isThreeLine: !t.isSystem && t.windows.length > 1,
                  subtitle: Text(
                    t.isSystem
                        ? '모든 프로그램의 소리'
                        : [
                            '${t.process ?? ''}${t.pid != null ? ' · pid ${t.pid}' : ''}',
                            if (t.windows.length > 1)
                              '창 ${t.windows.length}개: ${t.windows.skip(1).join(' / ')}',
                          ].join('\n'),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: active
                      ? Icon(Icons.check_circle_rounded, color: scheme.primary)
                      : null,
                  onTap: () => Navigator.of(ctx).pop(t.id),
                );
              },
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _StartDock extends StatelessWidget {
  const _StartDock({
    required this.state,
    required this.onStart,
    required this.onStop,
  });

  final BroadcastState state;
  final Future<void> Function() onStart;
  final Future<void> Function() onStop;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final running = state.isRunning;
    final canStart = !state.isBusy && state.selectedTargetId != null;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: running ? scheme.error : scheme.primary,
                ),
                onPressed: state.isBusy
                    ? null
                    : running
                        ? onStop
                        : (canStart ? onStart : null),
                icon: state.isBusy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Icon(running ? Icons.stop_rounded : Icons.subtitles_rounded),
                label: Text(running ? '자막 정지' : '자막 시작'),
              ),
              const SizedBox(height: 8),
              Text(
                running
                    ? '창의 소리를 서버가 듣고 있어요. 앱은 오디오를 보내지 않습니다'
                    : 'PC 에서 방송을 재생한 뒤, 그 창을 고르고 시작하세요',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, color: scheme.outline),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

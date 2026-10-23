import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/tts/tts_player.dart';
import '../transcript/transcript_entry.dart';
import '../transcript/transcript_list.dart';
import '../transcript/tts_hooks.dart';
import 'player_surface.dart';
import 'watch_controller.dart';
import 'watch_setup_screen.dart';
import 'watch_timeline.dart';

/// 동기 시청 플레이어 (명세 §8.2 "플레이어 (A)").
///
/// 세로: 위 16:9 영상 영역(자막·상태 오버레이·컨트롤) + 아래 자막 기록.
/// 전체화면: 가로 고정 + 몰입 모드, 컨트롤은 3 s 뒤 자동 숨김, 탭으로 토글.
class WatchPlayerScreen extends ConsumerStatefulWidget {
  const WatchPlayerScreen({super.key});

  @override
  ConsumerState<WatchPlayerScreen> createState() => _WatchPlayerScreenState();
}

class _WatchPlayerScreenState extends ConsumerState<WatchPlayerScreen> {
  Timer? _clock;
  Timer? _hideControls;
  bool _fullscreen = false;
  bool _controlsVisible = true;
  bool _showMetrics = false;
  int _nowMs = DateTime.now().millisecondsSinceEpoch;

  @override
  void initState() {
    super.initState();
    // 재생 위치·카운트다운은 서버 이벤트가 아니라 시계로 움직이므로 화면에서 직접 돈다.
    _clock = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (mounted) setState(() => _nowMs = DateTime.now().millisecondsSinceEpoch);
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    _hideControls?.cancel();
    if (_fullscreen) unawaited(_applyFullscreen(false));
    super.dispose();
  }

  Future<void> _applyFullscreen(bool on) async {
    if (on) {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    } else {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      await SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    }
  }

  void _toggleFullscreen() {
    setState(() {
      _fullscreen = !_fullscreen;
      _controlsVisible = true;
    });
    unawaited(_applyFullscreen(_fullscreen));
    _scheduleHide();
  }

  void _scheduleHide() {
    _hideControls?.cancel();
    if (!_fullscreen) return;
    _hideControls = Timer(const Duration(seconds: 3), () {
      if (mounted && _fullscreen) setState(() => _controlsVisible = false);
    });
  }

  void _onSurfaceTap() {
    if (!_fullscreen) return;
    setState(() => _controlsVisible = !_controlsVisible);
    _scheduleHide();
  }

  Future<bool> _onWillPop() async {
    if (_fullscreen) {
      _toggleFullscreen();
      return false;
    }
    final state = ref.read(watchControllerProvider);
    if (!state.isLive && !state.phase.isBusy) {
      await ref.read(watchControllerProvider.notifier).leave();
      return true;
    }
    final leave = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('시청을 끝낼까요?'),
        content: const Text('세션이 정지되고 지연 버퍼가 비워집니다. 설정 화면으로 돌아가도 재생은 계속할 수 있어요.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('계속 재생')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('정지하고 나가기')),
        ],
      ),
    );
    if (leave == true) {
      await ref.read(watchControllerProvider.notifier).leave();
      return true;
    }
    // 재생은 두고 화면만 뒤로.
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(watchControllerProvider);
    final controller = ref.read(watchControllerProvider.notifier);
    final tts = TranscriptTts(ref, 'watch');
    tts.listenErrors(context);
    final ttsState = ref.watch(ttsControllerProvider);

    ref.listen<WatchState>(watchControllerProvider, (prev, next) {
      if (next.warning != null && next.warningSeq != (prev?.warningSeq ?? 0)) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(next.warning!)));
      }
    });

    final playhead = state.clock.playheadMs(_nowMs);
    final cues = playhead == null || state.phase != WatchPhase.playing
        ? const <TranscriptEntry>[]
        : activeCues(state.entries, playhead);
    final landscape = MediaQuery.of(context).orientation == Orientation.landscape;
    final immersive = _fullscreen || landscape;
    // 세로 화면에서는 영상 영역(16:9)이 낮아 오류·종료 화면은 화면 전체를 덮는다.
    final terminal = state.phase == WatchPhase.error || state.phase == WatchPhase.ended;
    final overlayInVideo = immersive || !terminal;

    Future<void> close() async {
      if (_fullscreen) _toggleFullscreen();
      await controller.leave();
      if (context.mounted) Navigator.of(context).pop();
    }

    final phaseOverlay = _PhaseOverlay(
      state: state,
      nowMs: _nowMs,
      compact: !immersive,
      onRetry: controller.retry,
      onClose: close,
    );

    final video = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _onSurfaceTap,
      child: Stack(
        fit: StackFit.expand,
        children: [
          PlayerSurface(
            hlsUrl: state.hlsUrl,
            audioOnly: !state.hasVideo,
            playing: state.phase == WatchPhase.playing,
            muted: state.muted,
            volume: state.originalVolume,
          ),
          _SubtitleOverlay(
            cues: cues,
            mode: state.subtitleMode,
            showSpeaker: state.settings.showSpeaker,
            bottomInset: _controlsVisible ? 64 : 16,
          ),
          if (overlayInVideo) phaseOverlay,
          AnimatedOpacity(
            opacity: _controlsVisible ? 1 : 0,
            duration: const Duration(milliseconds: 200),
            child: IgnorePointer(
              ignoring: !_controlsVisible,
              child: _ControlsLayer(
                state: state,
                nowMs: _nowMs,
                fullscreen: _fullscreen,
                showMetrics: _showMetrics,
                onBack: () async {
                  if (await _onWillPop() && context.mounted) Navigator.of(context).pop();
                },
                onFullscreen: _toggleFullscreen,
                onMetrics: () => setState(() => _showMetrics = !_showMetrics),
                onSubtitleMode: controller.cycleSubtitleMode,
                onVolume: () => _openVolumeSheet(context, controller),
                onStop: controller.stop,
                onTranscript: immersive ? () => _openTranscriptSheet(context, state, tts, ttsState) : null,
              ),
            ),
          ),
          if (_showMetrics) Positioned(top: 56, right: 12, child: _MetricsPanel(state: state)),
        ],
      ),
    );

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _onWillPop() && context.mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: immersive
            ? video
            : SafeArea(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Column(
                      children: [
                        AspectRatio(aspectRatio: 16 / 9, child: video),
                        Expanded(
                          child: _TranscriptPanel(
                            state: state,
                            playhead: playhead,
                            tts: tts,
                            ttsState: ttsState,
                          ),
                        ),
                      ],
                    ),
                    if (!overlayInVideo) phaseOverlay,
                  ],
                ),
              ),
      ),
    );
  }

  Future<void> _openVolumeSheet(BuildContext context, WatchController controller) {
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => Consumer(
        builder: (ctx, ref, _) {
          final s = ref.watch(watchControllerProvider);
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text('음량', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                      const Spacer(),
                      IconButton.filledTonal(
                        tooltip: s.muted ? '음소거 해제' : '음소거',
                        onPressed: () => controller.setVolumes(muted: !s.muted),
                        icon: Icon(s.muted ? Icons.volume_off_rounded : Icons.volume_up_rounded),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _VolumeRow(
                    icon: Icons.music_note_rounded,
                    label: '원음',
                    value: s.originalVolume,
                    enabled: !s.muted,
                    onChanged: (v) => controller.setVolumes(original: v),
                  ),
                  _VolumeRow(
                    icon: Icons.record_voice_over_rounded,
                    label: '번역 음성',
                    value: s.ttsVolume,
                    enabled: !s.muted && s.settings.ttsEnabled,
                    onChanged: (v) => controller.setVolumes(tts: v),
                  ),
                  if (!s.settings.ttsEnabled)
                    Text(
                      '이 세션은 번역 음성이 꺼져 있어요',
                      style: TextStyle(fontSize: 11, color: Theme.of(ctx).colorScheme.outline),
                    ),
                  const SizedBox(height: 4),
                  Text(
                    '번역 음성이 나올 때 원음은 자동으로 −12 dB 줄어듭니다 (덕킹)',
                    style: TextStyle(fontSize: 11, color: Theme.of(ctx).colorScheme.outline),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _openTranscriptSheet(
    BuildContext context,
    WatchState state,
    TranscriptTts tts,
    TtsState ttsState,
  ) {
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => Consumer(
        builder: (ctx, ref, _) {
          final s = ref.watch(watchControllerProvider);
          final t = ref.watch(ttsControllerProvider);
          return SizedBox(
            height: MediaQuery.of(ctx).size.height * 0.7,
            child: _TranscriptPanel(
              state: s,
              playhead: s.clock.playheadMs(DateTime.now().millisecondsSinceEpoch),
              tts: tts,
              ttsState: t,
            ),
          );
        },
      ),
    );
  }
}

class _VolumeRow extends StatelessWidget {
  const _VolumeRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final IconData icon;
  final String label;
  final double value;
  final bool enabled;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, size: 20, color: enabled ? scheme.primary : scheme.outline),
        const SizedBox(width: 8),
        SizedBox(width: 64, child: Text(label, style: const TextStyle(fontSize: 13))),
        Expanded(
          child: Slider(
            value: value,
            onChanged: enabled ? onChanged : null,
          ),
        ),
        SizedBox(
          width: 40,
          child: Text(
            '${(value * 100).round()}%',
            textAlign: TextAlign.end,
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
        ),
      ],
    );
  }
}

/// 영상 위 자막. 번역/원문/둘 다, 화자 라벨.
class _SubtitleOverlay extends StatelessWidget {
  const _SubtitleOverlay({
    required this.cues,
    required this.mode,
    required this.showSpeaker,
    required this.bottomInset,
  });

  final List<TranscriptEntry> cues;
  final SubtitleMode mode;
  final bool showSpeaker;
  final double bottomInset;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 16,
      right: 16,
      bottom: bottomInset,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 150),
        child: cues.isEmpty
            ? const SizedBox.shrink(key: ValueKey('none'))
            : Column(
                key: ValueKey(cues.map((c) => '${c.segId}:${c.speaker}').join(',')),
                mainAxisSize: MainAxisSize.min,
                children: [for (final c in cues) _CueBox(cue: c, mode: mode, showSpeaker: showSpeaker)],
              ),
      ),
    );
  }
}

class _CueBox extends StatelessWidget {
  const _CueBox({required this.cue, required this.mode, required this.showSpeaker});

  final TranscriptEntry cue;
  final SubtitleMode mode;
  final bool showSpeaker;

  @override
  Widget build(BuildContext context) {
    final translation = cue.translation;
    final primary = switch (mode) {
      SubtitleMode.translation => translation ?? cue.text,
      SubtitleMode.original => cue.text,
      SubtitleMode.both => translation ?? cue.text,
    };
    final secondary = switch (mode) {
      SubtitleMode.both when translation != null => cue.text,
      _ => null,
    };
    final speaker = showSpeaker ? cue.speaker : null;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.62),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text.rich(
              TextSpan(
                children: [
                  if (speaker != null)
                    TextSpan(
                      text: '$speaker  ',
                      style: TextStyle(
                        color: _speakerColor(speaker),
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                  TextSpan(text: primary),
                ],
              ),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 19,
                height: 1.3,
                fontWeight: FontWeight.w600,
                shadows: [Shadow(blurRadius: 4, color: Colors.black)],
              ),
            ),
            if (secondary != null)
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Text(
                  secondary,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 14, height: 1.3),
                ),
              ),
          ],
        ),
      ),
    );
  }

  static Color _speakerColor(String speaker) {
    const palette = [Color(0xFF8AB4F8), Color(0xFFFFB86C), Color(0xFF7EE787), Color(0xFFF78CDB)];
    final n = int.tryParse(speaker.replaceAll(RegExp('[^0-9]'), '')) ?? 0;
    return palette[n % palette.length];
  }
}

/// 상태별 전체 오버레이: 연결/보정/버퍼링(카운트다운)/오류/종료.
///
/// [compact] 는 세로 화면의 낮은 영상 영역용 — 아이콘·글자를 줄이고 위아래 컨트롤 바 높이만큼 비운다.
class _PhaseOverlay extends StatelessWidget {
  const _PhaseOverlay({
    required this.state,
    required this.nowMs,
    required this.compact,
    required this.onRetry,
    required this.onClose,
  });

  final WatchState state;
  final int nowMs;
  final bool compact;
  final Future<void> Function() onRetry;
  final Future<void> Function() onClose;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ring = compact ? 56.0 : 96.0;
    switch (state.phase) {
      case WatchPhase.playing:
      case WatchPhase.idle:
        return const SizedBox.shrink();
      case WatchPhase.connecting:
      case WatchPhase.starting:
      case WatchPhase.calibrating:
      case WatchPhase.stopping:
        return _Scrim(
          child: _Centered(
            compact: compact,
            icon: SizedBox(
              width: compact ? 32 : 44,
              height: compact ? 32 : 44,
              child: const CircularProgressIndicator(strokeWidth: 3, color: Colors.white),
            ),
            title: state.phase.label,
            subtitle: switch (state.phase) {
              WatchPhase.connecting => '세션을 만들고 서버에 연결하는 중',
              WatchPhase.starting => '캡처·모델을 준비하는 중',
              WatchPhase.calibrating => '샘플을 돌려 권장 지연을 재는 중 (최대 1~2분)',
              WatchPhase.stopping => '남은 문장을 인식해 기록에 넣는 중',
              _ => '',
            },
          ),
        );
      case WatchPhase.buffering:
        final remaining = state.clock.remainingMs(nowMs);
        final progress = state.clock.bufferProgress(nowMs);
        final delay = state.delayS;
        return _Scrim(
          child: _Centered(
            compact: compact,
            icon: SizedBox(
              width: ring,
              height: ring,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CircularProgressIndicator(
                    value: progress,
                    strokeWidth: compact ? 4 : 6,
                    color: Colors.white,
                    backgroundColor: Colors.white24,
                  ),
                  Center(
                    child: Text(
                      remaining == null ? '…' : '${(remaining / 1000).ceil()}',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: compact ? 20 : 32,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            title: delay == null ? '지연 버퍼를 채우는 중' : '$delay초 지연 버퍼를 채우는 중',
            subtitle: delay == null
                ? '서버가 지연 시간을 정하는 중'
                : compact
                    ? '준비된 자막 ${state.entries.length}개 · 그 사이 인식·번역이 먼저 끝나요'
                    : '방송을 $delay초 늦춰 재생합니다. 그 사이 인식·번역이 먼저 끝나요 · 준비된 자막 ${state.entries.length}개',
          ),
        );
      case WatchPhase.error:
        final err = state.error ?? const WatchError(code: 'E_UNKNOWN', message: '');
        return _Scrim(
          color: const Color(0xCC3A0B0B),
          child: _Centered(
            icon: Icon(Icons.error_outline_rounded, size: 56, color: scheme.errorContainer),
            title: err.title,
            subtitle: err.hint,
            footer: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SelectableText(
                  '${err.code}${err.message.isNotEmpty && err.message != err.hint ? ' · ${err.message}' : ''}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white54, fontSize: 11),
                ),
                const SizedBox(height: 14),
                _OverlayActions(
                  secondaryIcon: Icons.close_rounded,
                  secondaryLabel: '닫기',
                  onSecondary: onClose,
                  primaryIcon: Icons.refresh_rounded,
                  primaryLabel: '다시 시작',
                  onPrimary: onRetry,
                ),
              ],
            ),
          ),
        );
      case WatchPhase.ended:
        final dur = state.startedAt == null || state.endedAt == null
            ? null
            : state.endedAt!.difference(state.startedAt!);
        return _Scrim(
          child: _Centered(
            icon: const Icon(Icons.check_circle_outline_rounded, size: 56, color: Colors.white),
            title: '시청을 마쳤어요',
            subtitle: [
              if (dur != null) '${formatClock(dur.inMilliseconds)} 시청',
              '자막 ${state.entries.length}개',
              '지연 미스 ${state.deadlines.total}건',
            ].join(' · '),
            footer: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (state.settings.isolationDeviceId != null)
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: Theme(
                      data: Theme.of(context).copyWith(brightness: Brightness.dark),
                      child: RestoreGuideBox(text: state.restoreGuide),
                    ),
                  ),
                const SizedBox(height: 14),
                _OverlayActions(
                  secondaryIcon: Icons.arrow_back_rounded,
                  secondaryLabel: '설정으로',
                  onSecondary: onClose,
                  primaryIcon: Icons.replay_rounded,
                  primaryLabel: '같은 설정으로 다시',
                  onPrimary: onRetry,
                ),
              ],
            ),
          ),
        );
    }
  }
}

class _OverlayActions extends StatelessWidget {
  const _OverlayActions({
    required this.secondaryIcon,
    required this.secondaryLabel,
    required this.onSecondary,
    required this.primaryIcon,
    required this.primaryLabel,
    required this.onPrimary,
  });

  final IconData secondaryIcon;
  final String secondaryLabel;
  final Future<void> Function() onSecondary;
  final IconData primaryIcon;
  final String primaryLabel;
  final Future<void> Function() onPrimary;

  @override
  Widget build(BuildContext context) {
    // 테마의 FilledButton 은 폭이 무한(fromHeight)이라 여기서는 내용 폭으로 되돌린다.
    const size = Size(0, 44);
    return Wrap(
      spacing: 10,
      runSpacing: 8,
      alignment: WrapAlignment.center,
      children: [
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            minimumSize: size,
            foregroundColor: Colors.white,
            side: const BorderSide(color: Colors.white54),
          ),
          onPressed: onSecondary,
          icon: Icon(secondaryIcon),
          label: Text(secondaryLabel),
        ),
        FilledButton.icon(
          style: FilledButton.styleFrom(minimumSize: size),
          onPressed: onPrimary,
          icon: Icon(primaryIcon),
          label: Text(primaryLabel),
        ),
      ],
    );
  }
}

class _Scrim extends StatelessWidget {
  const _Scrim({required this.child, this.color = const Color(0xB3000000)});

  final Widget child;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(color: color, alignment: Alignment.center, child: child);
}

class _Centered extends StatelessWidget {
  const _Centered({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.footer,
    this.compact = false,
  });

  final Widget icon;
  final String title;
  final String subtitle;
  final Widget? footer;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      // compact: 위 상태줄(48)·아래 컨트롤 바(56) 와 겹치지 않게 비운다.
      padding: compact ? const EdgeInsets.fromLTRB(16, 48, 16, 56) : const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          icon,
          SizedBox(height: compact ? 8 : 14),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white, fontSize: compact ? 14 : 18, fontWeight: FontWeight.w800),
          ),
          SizedBox(height: compact ? 2 : 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Text(
              subtitle,
              textAlign: TextAlign.center,
              maxLines: compact ? 1 : null,
              overflow: compact ? TextOverflow.ellipsis : null,
              style: TextStyle(color: Colors.white70, fontSize: compact ? 11 : 13, height: 1.45),
            ),
          ),
          if (footer != null) ...[const SizedBox(height: 14), footer!],
        ],
      ),
    );
  }
}

/// 상단 상태줄 + 하단 컨트롤 바.
class _ControlsLayer extends StatelessWidget {
  const _ControlsLayer({
    required this.state,
    required this.nowMs,
    required this.fullscreen,
    required this.showMetrics,
    required this.onBack,
    required this.onFullscreen,
    required this.onMetrics,
    required this.onSubtitleMode,
    required this.onVolume,
    required this.onStop,
    this.onTranscript,
  });

  final WatchState state;
  final int nowMs;
  final bool fullscreen;
  final bool showMetrics;
  final VoidCallback onBack;
  final VoidCallback onFullscreen;
  final VoidCallback onMetrics;
  final VoidCallback onSubtitleMode;
  final VoidCallback onVolume;
  final Future<void> Function() onStop;
  final VoidCallback? onTranscript;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final playhead = state.clock.playheadMs(nowMs);
    final live = state.phase == WatchPhase.playing;
    final misses = state.deadlines;

    return Column(
      children: [
        // 상단
        Container(
          padding: const EdgeInsets.fromLTRB(4, 4, 8, 8),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xAA000000), Colors.transparent],
            ),
          ),
          child: Row(
            children: [
              IconButton(onPressed: onBack, icon: const Icon(Icons.arrow_back_rounded, color: Colors.white)),
              _StatusChip(
                color: live ? const Color(0xFFE53935) : (state.phase == WatchPhase.error ? scheme.error : Colors.white24),
                text: live && state.delayS != null ? 'LIVE −${state.delayS}s' : state.phase.label,
                pulse: live,
              ),
              const SizedBox(width: 8),
              if (playhead != null && playhead >= 0)
                Text(
                  formatClock(playhead),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              const Spacer(),
              if (misses.total > 0)
                Tooltip(
                  message: 'L1 ${misses.l1} · L2 ${misses.l2} · L3 ${misses.l3}',
                  child: _StatusChip(
                    color: misses.l3 > 0 ? scheme.error : const Color(0xFFB08A00),
                    text: '지연 ${misses.total}',
                    icon: Icons.timer_off_outlined,
                  ),
                ),
              IconButton(
                tooltip: '지표',
                onPressed: onMetrics,
                icon: Icon(showMetrics ? Icons.insights_rounded : Icons.insights_outlined, color: Colors.white),
              ),
              IconButton(
                tooltip: fullscreen ? '전체화면 해제' : '전체화면',
                onPressed: onFullscreen,
                icon: Icon(fullscreen ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded, color: Colors.white),
              ),
            ],
          ),
        ),
        const Spacer(),
        // 하단
        Container(
          padding: const EdgeInsets.fromLTRB(8, 10, 8, 6),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              colors: [Color(0xBB000000), Colors.transparent],
            ),
          ),
          child: Row(
            children: [
              IconButton(
                tooltip: '음량',
                onPressed: onVolume,
                icon: Icon(state.muted ? Icons.volume_off_rounded : Icons.volume_up_rounded, color: Colors.white),
              ),
              TextButton.icon(
                style: TextButton.styleFrom(foregroundColor: Colors.white),
                onPressed: onSubtitleMode,
                icon: const Icon(Icons.subtitles_rounded, size: 20),
                label: Text('자막: ${state.subtitleMode.label}'),
              ),
              if (onTranscript != null)
                IconButton(
                  tooltip: '자막 기록',
                  onPressed: onTranscript,
                  icon: const Icon(Icons.list_alt_rounded, color: Colors.white),
                ),
              const Spacer(),
              if (state.recommendedNextDelayS != null)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: _StatusChip(
                    color: const Color(0xFFB08A00),
                    text: '다음엔 ${state.recommendedNextDelayS}s 권장',
                    icon: Icons.lightbulb_outline_rounded,
                  ),
                ),
              if (state.isLive)
                FilledButton.tonalIcon(
                  style: FilledButton.styleFrom(
                    backgroundColor: scheme.error.withValues(alpha: 0.9),
                    foregroundColor: Colors.white,
                    minimumSize: const Size(0, 40),
                  ),
                  onPressed: onStop,
                  icon: const Icon(Icons.stop_rounded),
                  label: const Text('정지'),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.color, required this.text, this.icon, this.pulse = false});

  final Color color;
  final String text;
  final IconData? icon;
  final bool pulse;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(999)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 13, color: Colors.white), const SizedBox(width: 4)],
          if (pulse) ...[
            const _Blink(child: Icon(Icons.circle, size: 8, color: Colors.white)),
            const SizedBox(width: 6),
          ],
          Text(text, style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

class _Blink extends StatefulWidget {
  const _Blink({required this.child});

  final Widget child;

  @override
  State<_Blink> createState() => _BlinkState();
}

class _BlinkState extends State<_Blink> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      FadeTransition(opacity: Tween(begin: 0.3, end: 1.0).animate(_c), child: widget.child);
}

/// 지표 패널 (명세 §8.2 "지표"): 단계별 p50/p99, 미스율, 큐, GPU.
class _MetricsPanel extends StatelessWidget {
  const _MetricsPanel({required this.state});

  final WatchState state;

  @override
  Widget build(BuildContext context) {
    final m = state.metrics;
    const stages = {'sep': '분리', 'diar': '화자', 'stt': 'STT', 'mt': '번역', 'tts': 'TTS'};
    TextStyle s([Color c = Colors.white70]) => TextStyle(color: c, fontSize: 11, fontFeatures: const [FontFeature.tabularFigures()]);
    return Container(
      width: 220,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: const Color(0xDD101418), borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('지표', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13)),
          const SizedBox(height: 6),
          if (m == null)
            Text('아직 서버 지표가 없어요 (2 s 마다 수신)', style: s())
          else ...[
            Row(children: [
              Expanded(child: Text('단계', style: s())),
              SizedBox(width: 52, child: Text('p50', textAlign: TextAlign.end, style: s())),
              SizedBox(width: 52, child: Text('p99', textAlign: TextAlign.end, style: s())),
            ]),
            for (final e in stages.entries)
              if (m.p50Ms.containsKey(e.key) || m.p99Ms.containsKey(e.key))
                Row(children: [
                  Expanded(child: Text(e.value, style: s(Colors.white))),
                  SizedBox(width: 52, child: Text('${m.p50Ms[e.key] ?? '-'}', textAlign: TextAlign.end, style: s(Colors.white))),
                  SizedBox(width: 52, child: Text('${m.p99Ms[e.key] ?? '-'}', textAlign: TextAlign.end, style: s(Colors.white))),
                ]),
            const Divider(color: Colors.white24, height: 14),
            Text('미스율 ${(m.missRate * 100).toStringAsFixed(1)}%  ·  큐 ${m.queueDepth}', style: s(Colors.white)),
            Text(
              'GPU ${m.gpuMemUsedMb} MB'
              '${m.gpuUtilStream != null ? '  ·  상시 점유 ${(m.gpuUtilStream! * 100).round()}%' : ''}',
              style: s(Colors.white),
            ),
          ],
          const Divider(color: Colors.white24, height: 14),
          Text(
            '데드라인 L1 ${state.deadlines.l1} · L2 ${state.deadlines.l2} · L3 ${state.deadlines.l3}',
            style: s(Colors.white),
          ),
          if (state.deadlines.lastLevel != null)
            Text('최근: ${DeadlineStats.describe(state.deadlines.lastLevel!)} (+${state.deadlines.lastLateMs} ms)', style: s()),
          if (state.clock.skewSamples > 0) Text('시계 보정 ${state.clock.skewMs} ms', style: s()),
          if (state.sessionId != null) Text('세션 ${state.sessionId}', style: s()),
        ],
      ),
    );
  }
}

/// 아래쪽 자막 기록: 재생 위치 기준으로 "이미 지나간 문장 / 아직 안 나온 문장" 을 나눠 보여준다.
class _TranscriptPanel extends StatelessWidget {
  const _TranscriptPanel({
    required this.state,
    required this.playhead,
    required this.tts,
    required this.ttsState,
  });

  final WatchState state;
  final int? playhead;
  final TranscriptTts tts;
  final TtsState ttsState;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final shown = playhead == null
        ? state.entries
        : state.entries.where((e) => e.tStartMs <= playhead!).toList();
    final pending = playhead == null ? 0 : pendingCueCount(state.entries, playhead!);
    return Container(
      color: scheme.surface,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 12, 6),
            child: Row(
              children: [
                Text('자막 기록', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: scheme.onSurface)),
                const SizedBox(width: 8),
                Text('${shown.length}개', style: TextStyle(fontSize: 12, color: scheme.outline)),
                const Spacer(),
                if (pending > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: scheme.primaryContainer,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '준비된 자막 $pending개 (재생 대기)',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: scheme.onPrimaryContainer),
                    ),
                  ),
              ],
            ),
          ),
          if (state.deadlines.l3 > 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
              child: Row(
                children: [
                  Icon(Icons.timer_off_outlined, size: 14, color: scheme.error),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '${state.deadlines.l3}개 문장이 늦어 재생에 못 실렸어요 (기록에는 남음)',
                      style: TextStyle(fontSize: 11.5, color: scheme.error),
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: TranscriptList(
              entries: shown,
              emptyHint: state.phase == WatchPhase.buffering
                  ? '지연 버퍼가 차면 재생 위치에 맞춰 여기에 쌓입니다'
                  : '재생이 시작되면 문장이 여기에 쌓입니다',
              onTapEntry: tts.toggle,
              speakingEntryKey: tts.speakingEntryKey(ttsState),
              loadingEntryKey: tts.loadingEntryKey(ttsState),
            ),
          ),
        ],
      ),
    );
  }
}

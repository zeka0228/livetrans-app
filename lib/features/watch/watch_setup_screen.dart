import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/server_config.dart';
import '../engines/engine_controller.dart';
import '../engines/engine_picker.dart';
import '../transcript/session_widgets.dart';
import 'watch_controller.dart';
import 'watch_player_screen.dart';
import 'watch_settings.dart';

/// 동기 시청(모드 A) 시작 화면 — 명세 §8.2 "세션 시작" + "소리 격리 점검".
class WatchSetupScreen extends ConsumerStatefulWidget {
  const WatchSetupScreen({super.key});

  @override
  ConsumerState<WatchSetupScreen> createState() => _WatchSetupScreenState();
}

class _WatchSetupScreenState extends ConsumerState<WatchSetupScreen> {
  late final TextEditingController _obsUrl;

  @override
  void initState() {
    super.initState();
    _obsUrl = TextEditingController(text: ref.read(watchControllerProvider).settings.obsUrl);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(watchControllerProvider.notifier).loadDevices();
    });
  }

  @override
  void dispose() {
    _obsUrl.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    final controller = ref.read(watchControllerProvider.notifier);
    controller.updateSettings((s) => s.copyWith(obsUrl: _obsUrl.text.trim()));
    // 연결 과정(연결 중 → 보정 → 버퍼링)을 플레이어 화면에서 바로 보여주기 위해 기다리지 않는다.
    unawaited(controller.start());
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const WatchPlayerScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(watchControllerProvider);
    final controller = ref.read(watchControllerProvider.notifier);
    final s = state.settings;
    final scheme = Theme.of(context).colorScheme;
    final locked = state.isLive || state.phase.isBusy;
    ref.listen(serverConfigProvider, (prev, next) {
      if (prev?.baseUrl != next.baseUrl) unawaited(controller.onServerChanged());
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('동기 시청'),
        actions: [
          if (state.isLive)
            TextButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const WatchPlayerScreen()),
              ),
              icon: const Icon(Icons.play_circle_fill_rounded),
              label: const Text('재생 화면'),
            ),
          const SizedBox(width: 4),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        children: [
          _IntroCard(state: state),
          const SizedBox(height: 16),
          _SectionTitle('입력'),
          _SourceCard(
            settings: s,
            enabled: !locked,
            obsUrl: _obsUrl,
            onKind: (k) => controller.updateSettings((x) => x.copyWith(sourceKind: k)),
          ),
          const SizedBox(height: 16),
          _SectionTitle('소리 격리 점검'),
          _RouteCard(
            state: state,
            enabled: !locked,
            onReload: controller.loadDevices,
            onSelect: (id) => controller.updateSettings((x) => x.copyWith(isolationDeviceId: id)),
            onCheck: controller.runRouteCheck,
          ),
          const SizedBox(height: 16),
          _SectionTitle('언어'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _FieldLabel('방송 언어 (원어)'),
                  const SizedBox(height: 6),
                  LanguagePicker(
                    selected: s.srcLang,
                    enabled: !locked,
                    onChanged: (v) => controller.updateSettings((x) => x.copyWith(srcLang: v)),
                  ),
                  const SizedBox(height: 12),
                  _FieldLabel('번역할 언어 (대상어)'),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final e in watchTargetLanguages.entries)
                        ChoiceChip(
                          label: Text(e.value),
                          selected: s.tgtLang == e.key,
                          onSelected: locked
                              ? null
                              : (_) => controller.updateSettings((x) => x.copyWith(tgtLang: e.key)),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          _EngineSection(enabled: !locked),
          _SectionTitle('지연 (D)'),
          _DelayCard(
            state: state,
            enabled: !locked,
            onAuto: (v) => controller.updateSettings((x) => x.copyWith(autoDelay: v)),
            onManual: (v) => controller.updateSettings((x) => x.copyWith(manualDelayS: v)),
            onCalibrate: controller.runCalibrate,
          ),
          const SizedBox(height: 16),
          _SectionTitle('출력·처리'),
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  title: const Text('번역 음성 (TTS)'),
                  subtitle: const Text('원음을 줄이고 번역 음성을 얹습니다'),
                  value: s.ttsEnabled,
                  onChanged: locked ? null : (v) => controller.updateSettings((x) => x.copyWith(ttsEnabled: v)),
                ),
                SwitchListTile(
                  title: const Text('원문 자막도 표시'),
                  value: s.showOriginal,
                  onChanged: locked ? null : (v) => controller.updateSettings((x) => x.copyWith(showOriginal: v)),
                ),
                SwitchListTile(
                  title: const Text('화자 표시'),
                  subtitle: const Text('화자 분할이 켜져 있을 때 S0·S1 로 구분'),
                  value: s.showSpeaker,
                  onChanged: locked ? null : (v) => controller.updateSettings((x) => x.copyWith(showSpeaker: v)),
                ),
                const Divider(height: 1),
                SwitchListTile(
                  title: const Text('음성 전처리 (BGM·효과음 분리)'),
                  subtitle: const Text('판단용 분석 트랙 생성 · 지연이 길어집니다'),
                  value: s.enhance,
                  onChanged: locked ? null : (v) => controller.updateSettings((x) => x.copyWith(enhance: v)),
                ),
                SwitchListTile(
                  title: const Text('화자 분할'),
                  subtitle: const Text('누가 말했는지 구분해 화자별로 인식'),
                  value: s.diarize,
                  onChanged: locked ? null : (v) => controller.updateSettings((x) => x.copyWith(diarize: v)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: locked || state.route.blocksStart ? null : _start,
            icon: const Icon(Icons.play_arrow_rounded),
            label: Text(state.isLive ? '재생 중…' : '시청 시작'),
          ),
          const SizedBox(height: 8),
          Text(
            state.route.blocksStart
                ? '소리 격리 점검을 통과해야 시작할 수 있어요'
                : '시작하면 ${s.autoDelay ? '서버 권장' : '${s.manualDelayS}초'} 지연 뒤부터 자막·음성이 맞춰진 영상이 나옵니다',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, color: state.route.blocksStart ? scheme.error : scheme.outline),
          ),
        ],
      ),
    );
  }
}

/// 엔진 선택 섹션 (API 계약 S-26). 서버가 `/api/engines` 를 안 주면 제목까지 통째로 숨긴다.
class _EngineSection extends ConsumerWidget {
  const _EngineSection({required this.enabled});

  final bool enabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final show = ref.watch(engineControllerProvider.select((s) => s.showPicker));
    if (!show) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle('엔진 (인식·번역)'),
        EnginePicker(enabled: enabled),
        const SizedBox(height: 16),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 2),
      child: Text(
        text,
        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: scheme.onSurfaceVariant),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Text(text, style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant));
  }
}

class _IntroCard extends StatelessWidget {
  const _IntroCard({required this.state});

  final WatchState state;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final last = state.phase == WatchPhase.ended || state.phase == WatchPhase.error;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [scheme.primary, scheme.primary.withValues(alpha: 0.75)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.slow_motion_video_rounded, color: scheme.onPrimary),
              const SizedBox(width: 8),
              Text(
                '지연 동기 재생',
                style: TextStyle(color: scheme.onPrimary, fontWeight: FontWeight.w800, fontSize: 16),
              ),
              const Spacer(),
              if (state.isLive)
                _Pill(text: state.phase.label, color: scheme.onPrimary),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '방송을 D초 늦춰 재생하는 동안 인식·번역·합성을 끝내, 자막과 번역 음성이 원래 발화 타이밍에 맞춰 나옵니다. 재생은 멈추지 않습니다.',
            style: TextStyle(color: scheme.onPrimary.withValues(alpha: 0.92), fontSize: 13, height: 1.45),
          ),
          if (last && state.startedAt != null) ...[
            const SizedBox(height: 10),
            Text(
              '지난 세션: ${state.phase == WatchPhase.error ? '오류로 종료' : '정상 종료'} · 자막 ${state.entries.length}개 · 지연 미스 ${state.deadlines.total}건',
              style: TextStyle(color: scheme.onPrimary.withValues(alpha: 0.85), fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        border: Border.all(color: color.withValues(alpha: 0.7)),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(text, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700)),
    );
  }
}

class _SourceCard extends StatelessWidget {
  const _SourceCard({
    required this.settings,
    required this.enabled,
    required this.obsUrl,
    required this.onKind,
  });

  final WatchSettings settings;
  final bool enabled;
  final TextEditingController obsUrl;
  final ValueChanged<WatchSourceKind> onKind;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SegmentedButton<WatchSourceKind>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(
                  value: WatchSourceKind.audioOnly,
                  icon: Icon(Icons.headphones_rounded),
                  label: Text('소리만 (격리 장치)'),
                ),
                ButtonSegment(
                  value: WatchSourceKind.obs,
                  icon: Icon(Icons.videocam_rounded),
                  label: Text('OBS 영상+소리'),
                ),
              ],
              selected: {settings.sourceKind},
              onSelectionChanged: enabled ? (v) => onKind(v.first) : null,
            ),
            const SizedBox(height: 10),
            if (settings.sourceKind == WatchSourceKind.obs) ...[
              TextField(
                controller: obsUrl,
                enabled: enabled,
                decoration: const InputDecoration(
                  labelText: '서버가 받을 SRT 주소',
                  prefixIcon: Icon(Icons.link_rounded),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'OBS: 창 캡처 + 오디오 소스는 격리 장치. 출력 → 녹화 대신 "사용자 지정 출력(FFmpeg)" 으로 SRT 송출, 키프레임 1초.',
                style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant, height: 1.4),
              ),
            ] else
              Text(
                '격리 장치로 나가는 소리만 서버가 캡처합니다. 영상은 없고 자막·번역 음성만 지연 재생돼요. 서버 모드 A 가 영상(HLS)을 주기 전까지의 기본값입니다.',
                style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant, height: 1.4),
              ),
          ],
        ),
      ),
    );
  }
}

class _RouteCard extends StatelessWidget {
  const _RouteCard({
    required this.state,
    required this.enabled,
    required this.onReload,
    required this.onSelect,
    required this.onCheck,
  });

  final WatchState state;
  final bool enabled;
  final VoidCallback onReload;
  final ValueChanged<String> onSelect;
  final VoidCallback onCheck;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final route = state.route;
    final devices = route.devices;

    Widget statusLine() {
      final (icon, color, text) = switch (route.status) {
        RouteCheckStatus.unknown || RouteCheckStatus.loadingDevices => (
            Icons.hourglass_top_rounded,
            scheme.tertiary,
            '출력 장치 목록을 서버에 묻는 중…',
          ),
        RouteCheckStatus.unsupported => (
            Icons.info_outline_rounded,
            scheme.outline,
            '이 서버는 아직 소리 격리 점검(/api/audio/*)을 지원하지 않아요. 점검 없이 시작할 수 있지만, 원본 소리는 그대로 들립니다.',
          ),
        RouteCheckStatus.idle => (
            Icons.radio_button_unchecked_rounded,
            scheme.onSurfaceVariant,
            route.devicesError ?? route.error ?? '아직 점검하지 않았어요',
          ),
        RouteCheckStatus.checking => (Icons.hourglass_top_rounded, scheme.tertiary, '점검 중…'),
        RouteCheckStatus.passed => (
            Icons.check_circle_rounded,
            scheme.primary,
            '통과 — 원본 소리는 격리 장치로만 나가고 사용자에게는 지연 출력만 들립니다',
          ),
        RouteCheckStatus.failed => (Icons.cancel_rounded, scheme.error, '격리되지 않았어요'),
      };
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: TextStyle(fontSize: 12, color: color, height: 1.4))),
        ],
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '브라우저 소리를 "격리 장치"로 보내고, 서버는 그 장치를 캡처합니다. 사용자 스피커로는 우리 앱의 지연 출력만 나갑니다.',
                    style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant, height: 1.4),
                  ),
                ),
                IconButton(
                  tooltip: '장치 목록 새로 고침',
                  onPressed: enabled && route.status != RouteCheckStatus.loadingDevices ? onReload : null,
                  icon: const Icon(Icons.refresh_rounded),
                ),
              ],
            ),
            if (devices != null && route.status != RouteCheckStatus.unsupported) ...[
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: state.settings.isolationDeviceId,
                decoration: const InputDecoration(
                  labelText: '격리 장치 (사용자가 듣지 않는 출력 장치)',
                  prefixIcon: Icon(Icons.speaker_group_outlined),
                ),
                items: [
                  for (final d in devices.devices)
                    DropdownMenuItem(
                      value: d.id,
                      enabled: !d.isDefault && d.active,
                      child: Text(
                        '${d.name}${d.isDefault ? ' (기본 — 선택 불가)' : ''}${!d.active ? ' (연결 끊김)' : ''}',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: !d.isDefault && d.active ? null : scheme.outline,
                        ),
                      ),
                    ),
                ],
                onChanged: enabled ? (v) => v == null ? null : onSelect(v) : null,
              ),
              if (devices.defaultDevice != null) ...[
                const SizedBox(height: 6),
                Text(
                  '내 스피커(기본 장치): ${devices.defaultDevice!.name}',
                  style: TextStyle(fontSize: 11, color: scheme.outline),
                ),
              ],
              if (devices.candidates.isEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  '격리에 쓸 수 있는 다른 출력 장치가 없어요. 스피커 없는 모니터의 HDMI 오디오를 켜거나 가상 오디오 케이블을 설치하세요.',
                  style: TextStyle(fontSize: 11, color: scheme.error, height: 1.4),
                ),
              ],
            ],
            const SizedBox(height: 10),
            statusLine(),
            if (route.result != null && route.result!.problems.isNotEmpty) ...[
              const SizedBox(height: 6),
              for (final p in route.result!.problems)
                Padding(
                  padding: const EdgeInsets.only(left: 26, top: 2),
                  child: Text('• $p', style: TextStyle(fontSize: 12, color: scheme.error)),
                ),
            ],
            if (route.result?.setupGuide != null) ...[
              const SizedBox(height: 8),
              _GuideBox(text: route.result!.setupGuide!),
            ] else if (route.status == RouteCheckStatus.idle || route.status == RouteCheckStatus.failed) ...[
              const SizedBox(height: 8),
              const _GuideBox(
                text: 'Windows 설정 → 시스템 → 소리 → 볼륨 믹서에서 브라우저의 "출력 장치"만 격리 장치로 바꾸세요. 우리 앱은 평소 스피커 그대로 둡니다.',
              ),
            ],
            if (route.status != RouteCheckStatus.unsupported &&
                route.status != RouteCheckStatus.unknown &&
                route.status != RouteCheckStatus.loadingDevices) ...[
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: enabled && state.settings.isolationDeviceId != null && route.status != RouteCheckStatus.checking
                    ? onCheck
                    : null,
                icon: route.status == RouteCheckStatus.checking
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.fact_check_outlined),
                label: Text(route.status == RouteCheckStatus.passed ? '다시 점검' : '격리 점검 실행'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _GuideBox extends StatelessWidget {
  const _GuideBox({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.tips_and_updates_outlined, size: 16, color: scheme.tertiary),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant, height: 1.45))),
        ],
      ),
    );
  }
}

class _DelayCard extends StatelessWidget {
  const _DelayCard({
    required this.state,
    required this.enabled,
    required this.onAuto,
    required this.onManual,
    required this.onCalibrate,
  });

  final WatchState state;
  final bool enabled;
  final ValueChanged<bool> onAuto;
  final ValueChanged<int> onManual;
  final VoidCallback onCalibrate;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final s = state.settings;
    final cal = state.calibrate;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SegmentedButton<bool>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: true, label: Text('서버 권장값'), icon: Icon(Icons.auto_awesome_rounded)),
                ButtonSegment(value: false, label: Text('직접 지정'), icon: Icon(Icons.tune_rounded)),
              ],
              selected: {s.autoDelay},
              onSelectionChanged: enabled ? (v) => onAuto(v.first) : null,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Text(
                  s.autoDelay ? '자동' : '${s.manualDelayS}초',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    color: scheme.primary,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    s.autoDelay
                        ? '세션 시작 시 서버가 측정한 권장 지연을 씁니다 (최악 가정 기본 36초)'
                        : '길수록 안전하고(미스↓) 짧을수록 실시간에 가깝습니다. 세션 중에는 바꿀 수 없어요',
                    style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant, height: 1.4),
                  ),
                ),
              ],
            ),
            Slider(
              value: s.manualDelayS.toDouble(),
              min: WatchSettings.minDelayS.toDouble(),
              max: WatchSettings.maxDelayS.toDouble(),
              divisions: WatchSettings.maxDelayS - WatchSettings.minDelayS,
              label: '${s.manualDelayS}초',
              onChanged: enabled && !s.autoDelay ? (v) => onManual(v.round()) : null,
            ),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: enabled && cal.status != CalibrateStatus.running ? onCalibrate : null,
                  icon: cal.status == CalibrateStatus.running
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.speed_rounded),
                  label: Text(cal.status == CalibrateStatus.running ? '측정 중 (최대 90초)…' : '권장 지연 측정'),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    switch (cal.status) {
                      CalibrateStatus.idle => '샘플을 실시간 속도로 돌려 종단 지연 P99 를 잽니다',
                      CalibrateStatus.running => '서버 GPU 부하를 측정하는 중',
                      CalibrateStatus.done =>
                        '권장 ${cal.result!.recommendedDelayS}초'
                            '${cal.result!.gpuUtil != null ? ' · GPU 점유율 ${(cal.result!.gpuUtil! * 100).round()}%' : ''}'
                            '${(cal.result!.gpuUtil ?? 0) > 0.7 ? ' ⚠️ 0.7 초과' : ''}',
                      CalibrateStatus.failed => cal.error ?? '측정 실패',
                      CalibrateStatus.unsupported => '서버가 아직 /api/calibrate 를 지원하지 않아요',
                    },
                    style: TextStyle(
                      fontSize: 11,
                      height: 1.4,
                      color: cal.status == CalibrateStatus.failed
                          ? scheme.error
                          : cal.status == CalibrateStatus.done
                              ? scheme.primary
                              : scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 설정 화면 밖(플레이어 종료 화면)에서도 복구 안내를 같은 모양으로 쓰기 위한 export.
class RestoreGuideBox extends StatelessWidget {
  const RestoreGuideBox({super.key, this.text});

  final String? text;

  @override
  Widget build(BuildContext context) => _GuideBox(
        text: text ??
            '시청을 마쳤으면 Windows 볼륨 믹서에서 브라우저의 출력 장치를 원래 스피커로 되돌리세요. 안 하면 다음에 브라우저 소리가 안 들립니다.',
      );
}


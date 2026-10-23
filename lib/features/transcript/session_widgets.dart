import 'package:flutter/material.dart';

import 'transcript_entry.dart';
import 'transcript_list.dart';

/// STT 원어 선택지. `auto` 는 서버 자동 감지 (API 계약 Q-API-1).
const sttLanguages = <String, String>{
  'auto': '자동',
  'ko': '한국어',
  'en': '영어',
  'ja': '일본어',
};

/// 세그먼트 형태의 언어 선택 탭.
class LanguagePicker extends StatelessWidget {
  const LanguagePicker({
    super.key,
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
          for (final e in sttLanguages.entries)
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

/// 세션 상태 줄: 상태 점 + 라벨 + 서버 상태 태그 + 오른쪽 보조 텍스트 + 오류/경고 문구.
class SessionStatusBar extends StatelessWidget {
  const SessionStatusBar({
    super.key,
    required this.label,
    required this.color,
    this.pulse = false,
    this.serverState,
    this.trailing,
    this.errorMessage,
    this.warning,
  });

  final String label;
  final Color color;
  final bool pulse;
  final String? serverState;
  final String? trailing;
  final String? errorMessage;
  final String? warning;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              StatusDot(color: color, pulse: pulse),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
              if (serverState != null) ...[
                const SizedBox(width: 8),
                _Tag(text: '서버 $serverState'),
              ],
              const Spacer(),
              if (trailing != null)
                Text(
                  trailing!,
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurfaceVariant,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
            ],
          ),
          if (errorMessage != null)
            _Notice(icon: Icons.warning_amber_rounded, text: errorMessage!, color: scheme.error),
          if (warning != null && errorMessage == null)
            _Notice(icon: Icons.info_outline_rounded, text: warning!, color: scheme.tertiary),
        ],
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.text, required this.color});

  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Text(text, style: TextStyle(fontSize: 12, color: color)),
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

/// 상태 점. [pulse] 면 천천히 깜빡인다.
class StatusDot extends StatefulWidget {
  const StatusDot({super.key, required this.color, required this.pulse});

  final Color color;
  final bool pulse;

  @override
  State<StatusDot> createState() => _StatusDotState();
}

class _StatusDotState extends State<StatusDot>
    with SingleTickerProviderStateMixin {
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
  void didUpdateWidget(covariant StatusDot old) {
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

/// "듣는 중" 중간 결과 버블. 화자 레인(S-19)마다 하나씩, [partials] 가 비면 높이 0 으로 접힌다.
class PartialBubble extends StatelessWidget {
  const PartialBubble({super.key, required this.partials});

  final List<TranscriptEntry> partials;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      alignment: Alignment.topCenter,
      child: partials.isEmpty
          ? const SizedBox(width: double.infinity)
          : Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Column(
                children: [
                  for (final p in partials) ...[
                    _PartialTile(entry: p, scheme: scheme),
                    if (p != partials.last) const SizedBox(height: 6),
                  ],
                ],
              ),
            ),
    );
  }
}

class _PartialTile extends StatelessWidget {
  const _PartialTile({required this.entry, required this.scheme});

  final TranscriptEntry entry;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    final speaker = entry.speaker;
    final lane = speaker == null ? null : speakerLaneColors(scheme, speaker);
    final accent = lane?.bar ?? scheme.primary;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: (lane?.bg ?? scheme.primaryContainer).withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accent.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.graphic_eq_rounded, size: 14, color: accent),
              const SizedBox(width: 6),
              Text(
                speaker == null ? '듣는 중' : '${TranscriptEntry.speakerLabel(speaker)} 듣는 중',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: accent,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            entry.text,
            style: TextStyle(
              fontSize: 16,
              height: 1.35,
              color: lane?.fg ?? scheme.onPrimaryContainer,
            ),
          ),
        ],
      ),
    );
  }
}

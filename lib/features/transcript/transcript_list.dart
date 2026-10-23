import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'transcript_entry.dart';

/// 자막 기록 목록. 탭 = 기기 음성으로 읽기(상위에서 처리), 길게 누르기·복사 버튼 = 클립보드.
class TranscriptList extends StatelessWidget {
  const TranscriptList({
    super.key,
    required this.entries,
    this.emptyHint = '시작하고 말하면 문장 단위로 쌓입니다',
    this.onTapEntry,
    this.speakingEntryKey,
    this.loadingEntryKey,
  });

  final List<TranscriptEntry> entries;
  final String emptyHint;
  final ValueChanged<TranscriptEntry>? onTapEntry;

  /// 지금 재생 중인 항목의 `TranscriptEntry.key` (없으면 null).
  final String? speakingEntryKey;

  /// 서버 합성을 기다리는 항목의 `TranscriptEntry.key`.
  final String? loadingEntryKey;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) return _EmptyState(hint: emptyHint);
    return ListView.separated(
      reverse: true,
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
      itemCount: entries.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final entry = entries[entries.length - 1 - i];
        return TranscriptTile(
          entry: entry,
          speaking: speakingEntryKey != null && entry.key == speakingEntryKey,
          loading: loadingEntryKey != null && entry.key == loadingEntryKey,
          onTap: onTapEntry == null ? null : () => onTapEntry!(entry),
        );
      },
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.hint});

  final String hint;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: scheme.primaryContainer.withValues(alpha: 0.5),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.subtitles_outlined,
              size: 34,
              color: scheme.primary,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            '아직 인식된 문장이 없어요',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Text(hint, style: TextStyle(fontSize: 12, color: scheme.outline)),
        ],
      ),
    );
  }
}

class TranscriptTile extends StatelessWidget {
  const TranscriptTile({
    super.key,
    required this.entry,
    this.speaking = false,
    this.loading = false,
    this.onTap,
  });

  final TranscriptEntry entry;
  final bool speaking;
  final bool loading;
  final VoidCallback? onTap;

  Future<void> _copy(BuildContext context) async {
    final text = entry.translation == null
        ? entry.text
        : '${entry.text}\n${entry.translation}';
    await Clipboard.setData(ClipboardData(text: text));
    if (context.mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('복사했습니다'),
            duration: Duration(seconds: 1),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final start = TranscriptEntry.formatMs(entry.tStartMs);
    final time = entry.tEndMs == null
        ? start
        : '$start – ${TranscriptEntry.formatMs(entry.tEndMs!)}';

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: speaking || loading ? scheme.primary : Colors.transparent,
          width: 1.5,
        ),
      ),
      child: Material(
        color: speaking || loading
            ? scheme.primaryContainer.withValues(alpha: 0.35)
            : scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          onLongPress: () => _copy(context),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 10, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (entry.speaker != null) ...[
                      _SpeakerBadge(speaker: entry.speaker!),
                      const SizedBox(width: 6),
                    ],
                    _LangBadge(code: entry.lang, prob: entry.langProb),
                    const SizedBox(width: 8),
                    Text(
                      time,
                      style: TextStyle(
                        fontSize: 11,
                        color: scheme.onSurfaceVariant,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    if (entry.sttMs != null) ...[
                      const SizedBox(width: 8),
                      Icon(Icons.bolt_rounded, size: 13, color: scheme.outline),
                      Text(
                        '${entry.sttMs} ms',
                        style: TextStyle(fontSize: 11, color: scheme.outline),
                      ),
                    ],
                    if (entry.forcedCut) ...[
                      const SizedBox(width: 8),
                      Icon(
                        Icons.content_cut_rounded,
                        size: 12,
                        color: scheme.tertiary,
                      ),
                    ],
                    const Spacer(),
                    if (onTap != null)
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        iconSize: 18,
                        tooltip: speaking || loading ? '정지' : '읽기',
                        color: speaking || loading ? scheme.primary : scheme.outline,
                        onPressed: onTap,
                        icon: loading
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : Icon(
                                speaking
                                    ? Icons.stop_circle_rounded
                                    : Icons.volume_up_rounded,
                              ),
                      ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      iconSize: 18,
                      tooltip: '복사',
                      color: scheme.outline,
                      onPressed: () => _copy(context),
                      icon: const Icon(Icons.copy_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Text(
                    entry.text,
                    style: const TextStyle(fontSize: 16, height: 1.4),
                  ),
                ),
                if (entry.translation != null) ...[
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                    decoration: BoxDecoration(
                      color: scheme.primaryContainer.withValues(alpha: 0.45),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      entry.translation!,
                      style: TextStyle(
                        fontSize: 15,
                        height: 1.4,
                        color: scheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                ],
                if (speaking || loading) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(Icons.graphic_eq_rounded, size: 13, color: scheme.primary),
                      const SizedBox(width: 4),
                      Text(
                        loading ? '서버에서 음성 만드는 중…' : '음성 재생 중 · 탭하면 정지',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: scheme.primary,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 화자 배지 (`S0` → `화자 1`). 화자마다 색을 달리해 같은 문장 안의 두 화자를 구분한다.
class _SpeakerBadge extends StatelessWidget {
  const _SpeakerBadge({required this.speaker});

  final String speaker;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final n = int.tryParse(speaker.replaceFirst(RegExp('^S'), '')) ?? 0;
    final (bg, fg) = switch (n % 4) {
      0 => (scheme.primaryContainer, scheme.onPrimaryContainer),
      1 => (scheme.tertiaryContainer, scheme.onTertiaryContainer),
      2 => (scheme.errorContainer, scheme.onErrorContainer),
      _ => (scheme.surfaceContainerHighest, scheme.onSurface),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.person_rounded, size: 12, color: fg),
          const SizedBox(width: 3),
          Text(
            TranscriptEntry.speakerLabel(speaker),
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: fg),
          ),
        ],
      ),
    );
  }
}

class _LangBadge extends StatelessWidget {
  const _LangBadge({required this.code, this.prob});

  final String code;
  final double? prob;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final label = TranscriptEntry.langLabel(code);
    final pct = prob == null ? null : (prob! * 100).round();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        pct == null ? label : '$label $pct%',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: scheme.onSecondaryContainer,
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'transcript_entry.dart';

class TranscriptList extends StatelessWidget {
  const TranscriptList({super.key, required this.entries});

  final List<TranscriptEntry> entries;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) return const _EmptyState();
    return ListView.separated(
      reverse: true,
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
      itemCount: entries.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, i) =>
          TranscriptTile(entry: entries[entries.length - 1 - i]),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

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
          Text(
            '녹음을 시작하고 말하면 문장 단위로 쌓입니다',
            style: TextStyle(fontSize: 12, color: scheme.outline),
          ),
        ],
      ),
    );
  }
}

class TranscriptTile extends StatelessWidget {
  const TranscriptTile({super.key, required this.entry});

  final TranscriptEntry entry;

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

    return Material(
      color: scheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onLongPress: () => _copy(context),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 10, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
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
            ],
          ),
        ),
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

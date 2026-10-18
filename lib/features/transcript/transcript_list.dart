import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'transcript_entry.dart';

class TranscriptList extends StatelessWidget {
  const TranscriptList({super.key, required this.entries});

  final List<TranscriptEntry> entries;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return const Center(
        child: Text('아직 인식된 문장이 없습니다', style: TextStyle(color: Colors.grey)),
      );
    }
    return ListView.separated(
      reverse: true,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: entries.length,
      separatorBuilder: (_, _) => const SizedBox(height: 6),
      itemBuilder: (context, i) => TranscriptTile(entry: entries[entries.length - 1 - i]),
    );
  }
}

class TranscriptTile extends StatelessWidget {
  const TranscriptTile({super.key, required this.entry});

  final TranscriptEntry entry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final meta = <String>[
      TranscriptEntry.formatMs(entry.tStartMs),
      if (entry.tEndMs != null) '→ ${TranscriptEntry.formatMs(entry.tEndMs!)}',
      TranscriptEntry.langLabel(entry.lang),
      if (entry.langProb != null) '${(entry.langProb! * 100).round()}%',
      if (entry.sttMs != null) 'STT ${entry.sttMs}ms',
      if (entry.forcedCut) '강제분할',
    ].join(' · ');

    return Material(
      color: scheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onLongPress: () async {
          final text = entry.translation == null
              ? entry.text
              : '${entry.text}\n${entry.translation}';
          await Clipboard.setData(ClipboardData(text: text));
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('복사했습니다'), duration: Duration(seconds: 1)),
            );
          }
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(meta, style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
              const SizedBox(height: 4),
              Text(entry.text, style: const TextStyle(fontSize: 16)),
              if (entry.translation != null) ...[
                const SizedBox(height: 4),
                Text(entry.translation!,
                    style: TextStyle(fontSize: 15, color: scheme.primary)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

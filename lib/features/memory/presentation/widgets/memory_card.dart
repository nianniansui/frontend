import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class MemoryCard extends StatelessWidget {
  final Map<String, dynamic> memory;

  const MemoryCard({super.key, required this.memory});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final createdAt = DateTime.tryParse(memory['created_at'] ?? '');
    final timeStr = createdAt != null
        ? DateFormat('MM-dd HH:mm').format(createdAt.toLocal())
        : '';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (memory['summary'] != null && (memory['summary'] as String).isNotEmpty)
              Text(
                memory['summary'] as String,
                style: theme.textTheme.bodyLarge,
              )
            else
              Text(
                memory['raw_text'] as String? ?? '',
                style: theme.textTheme.bodyLarge,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            const SizedBox(height: 8),
            if (memory['summary'] != null && (memory['summary'] as String).isNotEmpty)
              Text(
                memory['raw_text'] as String? ?? '',
                style: theme.textTheme.bodyMedium,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            const SizedBox(height: 6),
            Text(timeStr, style: theme.textTheme.labelSmall),
          ],
        ),
      ),
    );
  }
}

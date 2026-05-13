import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../../core/services/audio_player_service.dart';
import '../../../../core/services/audio_storage.dart';

/// 记忆卡片，支持：
/// - 点击播放原音
/// - 长按 / 更多按钮：编辑摘要、删除
class MemoryCard extends StatefulWidget {
  final Map<String, dynamic> memory;
  final Future<void> Function(Map<String, dynamic> memory)? onDelete;
  final Future<void> Function(Map<String, dynamic> memory, String newSummary)?
      onEditSummary;

  const MemoryCard({
    super.key,
    required this.memory,
    this.onDelete,
    this.onEditSummary,
  });

  @override
  State<MemoryCard> createState() => _MemoryCardState();
}

class _MemoryCardState extends State<MemoryCard> {
  final _player = AudioPlayerService.instance;
  bool _audioExists = false;

  @override
  void initState() {
    super.initState();
    _player.addListener(_onPlayerChanged);
    _checkAudio();
  }

  @override
  void didUpdateWidget(covariant MemoryCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.memory['audio_path'] != widget.memory['audio_path']) {
      _checkAudio();
    }
  }

  @override
  void dispose() {
    _player.removeListener(_onPlayerChanged);
    super.dispose();
  }

  Future<void> _checkAudio() async {
    final stored = widget.memory['audio_path'] as String?;
    if (kIsWeb || stored == null || stored.isEmpty) {
      if (mounted && _audioExists) setState(() => _audioExists = false);
      return;
    }
    final exists = await AudioStorage.exists(stored);
    if (!mounted) return;
    if (exists != _audioExists) setState(() => _audioExists = exists);
  }

  void _onPlayerChanged() {
    if (mounted) setState(() {});
  }

  String get _id => widget.memory['id'] as String? ?? '';
  String? get _stored => widget.memory['audio_path'] as String?;
  bool get _hasAudio => _audioExists;

  Future<void> _togglePlay() async {
    if (!_hasAudio) return;
    try {
      final resolved = await AudioStorage.resolve(_stored!);
      await _player.toggle(id: _id, path: resolved);
    } catch (_) {
      // 播放失败多半是文件已消失，静默隐藏按钮即可
      if (mounted) setState(() => _audioExists = false);
    }
  }

  Future<void> _showActions() async {
    final result = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.onEditSummary != null)
                ListTile(
                  leading: const Icon(Icons.edit_note_outlined),
                  title: const Text('修改摘要'),
                  onTap: () => Navigator.pop(ctx, 'edit'),
                ),
              if (widget.onDelete != null)
                ListTile(
                  leading: const Icon(Icons.delete_outline, color: Colors.redAccent),
                  title: const Text('删除', style: TextStyle(color: Colors.redAccent)),
                  onTap: () => Navigator.pop(ctx, 'delete'),
                ),
              ListTile(
                leading: const Icon(Icons.close),
                title: const Text('取消'),
                onTap: () => Navigator.pop(ctx),
              ),
            ],
          ),
        );
      },
    );
    if (!mounted) return;
    if (result == 'delete') {
      await _confirmDelete();
    } else if (result == 'edit') {
      await _editSummary();
    }
  }

  Future<void> _confirmDelete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除这条记忆？'),
        content: const Text('删除后无法恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (ok == true && widget.onDelete != null) {
      await widget.onDelete!(widget.memory);
    }
  }

  Future<void> _editSummary() async {
    final current = (widget.memory['summary'] as String?) ?? '';
    final controller = TextEditingController(text: current);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('修改摘要'),
        content: TextField(
          controller: controller,
          maxLines: 3,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '用一句话概括这条记忆',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (result != null && result != current && widget.onEditSummary != null) {
      await widget.onEditSummary!(widget.memory, result);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final createdAt = DateTime.tryParse(widget.memory['created_at'] ?? '');
    final timeStr = createdAt != null
        ? DateFormat('MM-dd HH:mm').format(createdAt.toLocal())
        : '';
    final summary = widget.memory['summary'] as String?;
    final rawText = widget.memory['raw_text'] as String? ?? '';
    final playing = _player.isPlayingId(_id);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: _hasAudio ? _togglePlay : null,
        onLongPress: (widget.onDelete == null && widget.onEditSummary == null)
            ? null
            : _showActions,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (summary != null && summary.isNotEmpty)
                Text(summary, style: theme.textTheme.bodyLarge)
              else
                Text(
                  rawText,
                  style: theme.textTheme.bodyLarge,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              const SizedBox(height: 8),
              if (summary != null && summary.isNotEmpty)
                Text(
                  rawText,
                  style: theme.textTheme.bodyMedium,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              const SizedBox(height: 6),
              Row(
                children: [
                  if (_hasAudio) ...[
                    Icon(
                      playing ? Icons.pause_circle_filled : Icons.play_circle_fill,
                      size: 18,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      playing ? '播放中' : '听原音',
                      style: theme.textTheme.labelSmall
                          ?.copyWith(color: theme.colorScheme.primary),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Text(timeStr, style: theme.textTheme.labelSmall),
                  const Spacer(),
                  if (widget.onDelete != null || widget.onEditSummary != null)
                    InkWell(
                      onTap: _showActions,
                      borderRadius: BorderRadius.circular(16),
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Icon(
                          Icons.more_horiz,
                          size: 18,
                          color: theme.textTheme.labelSmall?.color,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

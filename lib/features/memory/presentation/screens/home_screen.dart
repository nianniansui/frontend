import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../../core/services/api_service.dart';
import '../../../../core/services/notification_service.dart';
import '../../../../core/services/share_ingest_service.dart';
import '../../../../core/services/theme_service.dart';
import '../../../../core/services/user_service.dart';
import '../../../../core/services/voice_record_service.dart';
import '../../../../core/services/widget_bridge.dart';
import '../../../../core/db/memory_cache.dart';
import '../../../../main.dart' show pendingNotificationPayload;
import '../widgets/record_button.dart';
import '../widgets/memory_card.dart';
import '../../../search/presentation/search_screen.dart';
import '../../../settings/presentation/settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  static const _pageSize = 20;
  /// 与原生层共享的 deep link channel：widget / 通知点击会推过来
  static const _deepLinkChannel = MethodChannel('com.xiaosui.xiaosui/deeplink');

  List<Map<String, dynamic>> _memories = [];
  bool _loading = false;
  bool _loadingMore = false;
  bool _hasMore = true;
  bool _isOffline = false;
  final _cache = MemoryCache();
  final _scroll = ScrollController();
  final _searchCtrl = TextEditingController();
  StreamSubscription<List<Map<String, dynamic>>>? _ingestSub;
  StreamSubscription<String>? _diagSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scroll.addListener(_onScroll);
    pendingNotificationPayload.addListener(_onPendingPayloadChanged);

    final share = context.read<ShareIngestService>();

    // 监听 Share Ingest 流：原生层主动推过来的也能即时入流
    _ingestSub = share.ingestStream.listen((added) {
      if (added.isEmpty || !mounted) return;
      setState(() {
        _memories = [...added.reversed, ..._memories];
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已收下 ${added.length} 条分享')),
      );
      // 用最新一条更新 widget
      final newest = added.last;
      final preview =
          (newest['summary'] as String?)?.trim().isNotEmpty == true
              ? newest['summary'] as String
              : (newest['raw_text'] as String? ?? '');
      if (preview.isNotEmpty) {
        unawaited(WidgetBridge.updateLatestSummary(preview));
      }
      // share 摄入也可能产生提醒
      unawaited(_syncNotifications());
    });

    // 诊断流：把 share 链路的每一步显示为 Snackbar，方便真机定位
    _diagSub = share.diagStream.listen((msg) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 2),
          content: Text('share · $msg'),
        ),
      );
    });

    // 原生 deep link → "widget tap → 立即录音" / "通知点击 → 跳到对应记忆"
    _deepLinkChannel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'openRecord':
          if (mounted) await _startQuickRecord();
          break;
        case 'openMemory':
          final id = call.arguments as String?;
          if (id != null && mounted) _openMemory(id);
          break;
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await _loadMemories();
      if (!mounted) return;
      await _drainShareQueue();
      if (!mounted) return;
      await _syncNotifications();
      if (!mounted) return;
      _onPendingPayloadChanged(); // 若冷启动是通知点开的，立刻消费
      // 原生进来的初始 deep link（widget tap 冷启动）
      try {
        final initial = await _deepLinkChannel.invokeMethod<String>('initialLink');
        if (initial == 'record' && mounted) {
          await _startQuickRecord();
        }
      } on MissingPluginException {
        // 还没注册原生端，忽略
      }
    });
  }

  @override
  void dispose() {
    _ingestSub?.cancel();
    _diagSub?.cancel();
    pendingNotificationPayload.removeListener(_onPendingPayloadChanged);
    WidgetsBinding.instance.removeObserver(this);
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _drainShareQueue();
      _syncNotifications();
      _onPendingPayloadChanged();
    }
  }

  void _onPendingPayloadChanged() {
    final payload = pendingNotificationPayload.value;
    if (payload == null) return;
    pendingNotificationPayload.value = null; // 消费一次
    if (payload.startsWith('memory:')) {
      _openMemory(payload.substring('memory:'.length));
    }
  }

  Future<void> _syncNotifications() async {
    final api = context.read<ApiService>();
    final userService = context.read<UserService>();
    await userService.init();
    if (userService.userId.isEmpty) return;
    await NotificationService.instance.syncFromServer(
      api: api,
      userId: userService.userId,
    );
  }

  /// widget / 通知点击触发的快速录音。直接驱动 VoiceRecordService 进入录音态。
  Future<void> _startQuickRecord() async {
    final voice = context.read<VoiceRecordService>();
    final userService = context.read<UserService>();
    await userService.init();
    if (voice.state == RecordingState.recording) return;
    if (voice.state == RecordingState.processing) return;
    await voice.startRecording();
    if (!mounted) return;
    if (voice.lastError != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(voice.lastError!)),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          duration: Duration(seconds: 1),
          content: Text('正在录音，说完后再点中央按钮停止'),
        ),
      );
    }
  }

  /// 通知点击 / 搜索结果跳转：滚动到对应记忆并高亮（简化为 Snackbar 提示）
  void _openMemory(String id) {
    final idx = _memories.indexWhere((m) => m['id'] == id);
    if (idx < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('找不到这条记忆，可能已被删除')),
      );
      return;
    }
    // 滚到对应位置（粗略：每张卡片 96px）
    if (_scroll.hasClients) {
      _scroll.animateTo(
        (idx * 96).toDouble(),
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  /// 主动拉一次。原生层 sharesAvailable 的回调也会触发 processPending，
  /// 但 URL scheme 唤起时的回调时序不稳，多调一次确保不漏。
  Future<void> _drainShareQueue() async {
    final share = context.read<ShareIngestService>();
    final userService = context.read<UserService>();
    // user 还没 init 完时直接 await，确保 userId 拿到
    await userService.init();
    final userId = userService.userId;
    if (userId.isEmpty) return;
    await share.processPending(userId);
    // 注意：UI 更新走 _ingestSub 流，避免和 sharesAvailable 重复 setState
  }

  void _onScroll() {
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 240) {
      _loadMore();
    }
  }

  Future<void> _loadMemories() async {
    if (mounted) setState(() => _loading = true);

    final api = context.read<ApiService>();
    final userService = context.read<UserService>();
    await userService.init();
    if (!mounted) return;

    final userId = userService.userId;

    // 先读缓存，立即渲染
    final cached = await _cache.getMemories(userId, limit: _pageSize);
    if (cached.isNotEmpty && mounted) {
      setState(() {
        _memories = cached;
        _loading = false;
      });
    }

    try {
      final data = await api
          .listMemories(userId: userId, limit: _pageSize)
          .timeout(const Duration(seconds: 6));
      for (final m in data) {
        await _cache.upsertMemory({...m, 'user_id': userId});
      }
      if (!mounted) return;
      // 合并本地独有字段（audio_path 只存在缓存中）
      final merged = await _mergeAudioPaths(data, userId);
      setState(() {
        _memories = merged;
        _loading = false;
        _isOffline = false;
        _hasMore = data.length >= _pageSize;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _isOffline = true;
          _hasMore = false;
        });
      }
    }
  }

  /// 后端返回的数据没有 audio_path（原音只在本地），从缓存里补齐
  Future<List<Map<String, dynamic>>> _mergeAudioPaths(
    List<Map<String, dynamic>> server,
    String userId,
  ) async {
    final cached = await _cache.getMemories(userId, limit: 200);
    final byId = {for (final m in cached) m['id'] as String: m};
    return server.map((m) {
      final local = byId[m['id']];
      if (local != null && local['audio_path'] != null) {
        return {...m, 'audio_path': local['audio_path']};
      }
      return m;
    }).toList();
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore || _memories.isEmpty || _isOffline) return;
    setState(() => _loadingMore = true);

    final api = context.read<ApiService>();
    final userId = context.read<UserService>().userId;
    final last = _memories.last['created_at'] as String?;
    if (last == null) {
      setState(() => _loadingMore = false);
      return;
    }

    try {
      final data = await api
          .listMemories(userId: userId, limit: _pageSize, before: last)
          .timeout(const Duration(seconds: 6));
      for (final m in data) {
        await _cache.upsertMemory({...m, 'user_id': userId});
      }
      if (!mounted) return;
      final merged = await _mergeAudioPaths(data, userId);
      setState(() {
        _memories = [..._memories, ...merged];
        _hasMore = data.length >= _pageSize;
        _loadingMore = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() => _loadingMore = false);
      }
    }
  }

  void _onRecordComplete(Map<String, dynamic> memory) async {
    final userId = context.read<UserService>().userId;
    await _cache.upsertMemory({...memory, 'user_id': userId});
    if (!mounted) return;
    setState(() => _memories.insert(0, memory));
    // 推到 Widget App Group：让主屏 widget 立刻显示这条
    final preview =
        (memory['summary'] as String?)?.trim().isNotEmpty == true
            ? memory['summary'] as String
            : (memory['raw_text'] as String? ?? '');
    if (preview.isNotEmpty) {
      unawaited(WidgetBridge.updateLatestSummary(preview));
    }
    // 录音也可能挟带未来事件，刷一次通知队列
    unawaited(_syncNotifications());
  }

  Future<void> _onDelete(Map<String, dynamic> memory) async {
    final id = memory['id'] as String;
    final userId = context.read<UserService>().userId;
    final api = context.read<ApiService>();
    // 乐观删除
    setState(() => _memories.removeWhere((m) => m['id'] == id));
    try {
      await api.deleteMemory(memoryId: id, userId: userId);
      await _cache.deleteMemory(id);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('删除失败：$e')),
      );
      // 回滚
      setState(() => _memories.insert(0, memory));
    }
  }

  Future<void> _onEditSummary(
    Map<String, dynamic> memory,
    String newSummary,
  ) async {
    final id = memory['id'] as String;
    final userId = context.read<UserService>().userId;
    final api = context.read<ApiService>();
    final old = memory['summary'];
    setState(() {
      final idx = _memories.indexWhere((m) => m['id'] == id);
      if (idx >= 0) {
        _memories[idx] = {..._memories[idx], 'summary': newSummary};
      }
    });
    try {
      await api.updateMemory(memoryId: id, userId: userId, summary: newSummary);
      await _cache.updateFields(id, summary: newSummary);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('保存失败：$e')),
      );
      setState(() {
        final idx = _memories.indexWhere((m) => m['id'] == id);
        if (idx >= 0) {
          _memories[idx] = {..._memories[idx], 'summary': old};
        }
      });
    }
  }

  void _openSearch({String? initialQuery}) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SearchScreen(initialQuery: initialQuery),
      ),
    );
  }

  /// 底部"文字"按钮：弹底部 sheet 输入文字记忆，确认后走 /add_memory_text
  Future<void> _showTextInputSheet() async {
    final controller = TextEditingController();
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        final inset = MediaQuery.of(ctx).viewInsets.bottom;
        return Padding(
          padding: EdgeInsets.fromLTRB(16, 8, 16, 16 + inset),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '随手记一笔',
                style: Theme.of(ctx).textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: controller,
                autofocus: true,
                maxLines: 5,
                minLines: 3,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  hintText: '车牌号、密码、停车位置…什么都行',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('取消'),
                  ),
                  const Spacer(),
                  FilledButton.icon(
                    icon: const Icon(Icons.check),
                    label: const Text('记入'),
                    onPressed: () =>
                        Navigator.pop(ctx, controller.text.trim()),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
    if (result != null && result.isNotEmpty) {
      await _addMemoryFromText(result);
    }
  }

  /// "+ 文字" 按钮 → 弹底部输入框 → /add_memory_text
  Future<void> _addMemoryFromText(String text) async {
    final t = text.trim();
    if (t.isEmpty) return;
    final api = context.read<ApiService>();
    final userService = context.read<UserService>();
    await userService.init();
    if (!mounted) return;
    final userId = userService.userId;
    if (userId.isEmpty) return;

    // 占位卡片，让用户即时感知到记入成功
    final placeholderId = 'local-${DateTime.now().microsecondsSinceEpoch}';
    final placeholder = {
      'id': placeholderId,
      'raw_text': t,
      'summary': null,
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'user_id': userId,
      '_pending': true,
    };
    setState(() => _memories = [placeholder, ..._memories]);

    try {
      final memory = await api.addMemoryText(text: t, userId: userId);
      await _cache.upsertMemory({...memory, 'user_id': userId});
      if (!mounted) return;
      setState(() {
        final idx = _memories.indexWhere((m) => m['id'] == placeholderId);
        if (idx >= 0) {
          _memories[idx] = memory;
        }
      });
      // 推到 Widget App Group
      final preview =
          (memory['summary'] as String?)?.trim().isNotEmpty == true
              ? memory['summary'] as String
              : (memory['raw_text'] as String? ?? t);
      unawaited(WidgetBridge.updateLatestSummary(preview));
      // 录新记忆后顺便刷新一次本地通知队列（可能新增了提醒）
      unawaited(_syncNotifications());
    } catch (e) {
      if (!mounted) return;
      setState(() => _memories.removeWhere((m) => m['id'] == placeholderId));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('记入失败：$e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final themeSvc = context.watch<ThemeService>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('小碎'),
        actions: [
          IconButton(
            tooltip: '切换主题',
            icon: Icon(switch (themeSvc.mode) {
              ThemeMode.light => Icons.light_mode_outlined,
              ThemeMode.dark => Icons.dark_mode_outlined,
              ThemeMode.system => Icons.brightness_auto_outlined,
            }),
            onPressed: () {
              final next = switch (themeSvc.mode) {
                ThemeMode.system => ThemeMode.light,
                ThemeMode.light => ThemeMode.dark,
                ThemeMode.dark => ThemeMode.system,
              };
              themeSvc.setMode(next);
            },
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_isOffline)
            Container(
              width: double.infinity,
              color: Colors.orange.withValues(alpha: 0.15),
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
              child: Row(
                children: [
                  const Icon(Icons.cloud_off, size: 14, color: Colors.orange),
                  const SizedBox(width: 6),
                  Text(
                    '离线模式',
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: Colors.orange),
                  ),
                ],
              ),
            ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _memories.isEmpty
                    ? _EmptyState(onTryExample: (text) {
                        _openSearch(initialQuery: text);
                      })
                    : RefreshIndicator(
                        onRefresh: _loadMemories,
                        child: ListView.builder(
                          controller: _scroll,
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 140),
                          itemCount: _memories.length + 1,
                          itemBuilder: (_, i) {
                            if (i == _memories.length) {
                              return _Footer(
                                loading: _loadingMore,
                                hasMore: _hasMore,
                              );
                            }
                            return MemoryCard(
                              memory: _memories[i],
                              onDelete: _onDelete,
                              onEditSummary: _onEditSummary,
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: _BottomActionRow(
        onAsk: () => _openSearch(),
        onAddText: () => _showTextInputSheet(),
        onRecordComplete: _onRecordComplete,
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  final bool loading;
  final bool hasMore;
  const _Footer({required this.loading, required this.hasMore});

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 20),
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    if (!hasMore) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: Text(
            '— 到底了 —',
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ),
      );
    }
    return const SizedBox.shrink();
  }
}

class _EmptyState extends StatelessWidget {
  final void Function(String text)? onTryExample;
  const _EmptyState({this.onTryExample});

  static const _examples = [
    ('🗝️', '剪刀放在厨房第二个抽屉'),
    ('📅', '下周三下午三点和王老师开会'),
    ('🔒', '家里网关密码是 1234abcd'),
    ('🎁', '给妈妈买的生日礼物放在衣柜顶层'),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 160),
      children: [
        const SizedBox(height: 24),
        Center(
          child: Icon(
            Icons.mic_none,
            size: 56,
            color: theme.textTheme.labelSmall?.color,
          ),
        ),
        const SizedBox(height: 12),
        Center(
          child: Text(
            '按住下方按钮说话，随口一记',
            style: theme.textTheme.bodyLarge,
          ),
        ),
        const SizedBox(height: 4),
        Center(
          child: Text(
            '之后想找的时候，直接问它',
            style: theme.textTheme.bodyMedium,
          ),
        ),
        const SizedBox(height: 28),
        Text(
          '试试这样记',
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 10),
        ..._examples.map(
          (e) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: theme.dividerColor.withValues(alpha: 0.2),
                ),
              ),
              child: Row(
                children: [
                  Text(e.$1, style: const TextStyle(fontSize: 20)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '"${e.$2}"',
                      style: theme.textTheme.bodyLarge,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 18),
        Text(
          '之后可以这样找',
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            '剪刀在哪？',
            '下周有什么安排？',
            '网关密码是多少？',
          ].map((q) {
            return ActionChip(
              label: Text(q),
              onPressed: onTryExample == null ? null : () => onTryExample!(q),
            );
          }).toList(),
        ),
      ],
    );
  }
}

/// 底部三按钮：副(问) + 主(录音) + 副(文字)。
/// 录音按钮自身的录音状态由 [RecordButton] 内部用 Provider 管理，
/// 这里只负责把它放进一个对称的横排里。
class _BottomActionRow extends StatelessWidget {
  final VoidCallback onAsk;
  final VoidCallback onAddText;
  final void Function(Map<String, dynamic> memory) onRecordComplete;

  const _BottomActionRow({
    required this.onAsk,
    required this.onAddText,
    required this.onRecordComplete,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _SideActionButton(
          icon: Icons.search,
          label: '问',
          onTap: onAsk,
        ),
        const SizedBox(width: 32),
        RecordButton(onRecordComplete: onRecordComplete),
        const SizedBox(width: 32),
        _SideActionButton(
          icon: Icons.edit_note_outlined,
          label: '文字',
          onTap: onAddText,
        ),
      ],
    );
  }
}

/// 录音按钮两侧的副操作按钮：48 圆形 + 下方文字标签。
class _SideActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _SideActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: theme.colorScheme.primary.withValues(alpha: 0.12),
              border: Border.all(
                color: theme.colorScheme.primary.withValues(alpha: 0.3),
              ),
            ),
            child: Icon(
              icon,
              size: 22,
              color: theme.colorScheme.primary,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.primary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

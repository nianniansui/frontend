import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/services/api_service.dart';
import '../../../../core/services/theme_service.dart';
import '../../../../core/services/user_service.dart';
import '../../../../core/db/memory_cache.dart';
import '../widgets/record_button.dart';
import '../widgets/memory_card.dart';
import '../../../search/presentation/search_screen.dart';
import '../../../settings/presentation/settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const _pageSize = 20;

  List<Map<String, dynamic>> _memories = [];
  bool _loading = false;
  bool _loadingMore = false;
  bool _hasMore = true;
  bool _isOffline = false;
  final _cache = MemoryCache();
  final _scroll = ScrollController();
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadMemories();
    });
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    _searchCtrl.dispose();
    super.dispose();
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
          // 顶部大搜索框——把"找回"放到和"记"同等的位置
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: GestureDetector(
              onTap: () => _openSearch(),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: theme.dividerColor.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(Icons.search, size: 20, color: theme.textTheme.bodyMedium?.color),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '问一问，比如"剪刀在哪"',
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                    Icon(Icons.mic_none, size: 20, color: theme.textTheme.bodyMedium?.color),
                  ],
                ),
              ),
            ),
          ),
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
      floatingActionButton: RecordButton(onRecordComplete: _onRecordComplete),
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

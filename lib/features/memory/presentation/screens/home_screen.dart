import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/services/api_service.dart';
import '../../../../core/services/user_service.dart';
import '../../../../core/db/memory_cache.dart';
import '../widgets/record_button.dart';
import '../widgets/memory_card.dart';
import '../../../search/presentation/search_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Map<String, dynamic>> _memories = [];
  bool _loading = true;
  bool _isOffline = false;
  final _cache = MemoryCache();

  @override
  void initState() {
    super.initState();
    _loadMemories();
  }

  Future<void> _loadMemories() async {
    final api = context.read<ApiService>();
    final userId = context.read<UserService>().userId;

    // 先读缓存，立即渲染
    final cached = await _cache.getMemories(userId);
    if (cached.isNotEmpty && mounted) {
      setState(() { _memories = cached; _loading = false; });
    }

    // 再请求 API 更新
    try {
      final data = await api.listMemories(userId: userId);
      for (final m in data) {
        await _cache.upsertMemory({...m, 'user_id': userId});
      }
      if (mounted) {
        setState(() { _memories = data; _loading = false; _isOffline = false; });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _isOffline = _memories.isNotEmpty;
        });
      }
    }
  }

  void _onRecordComplete(Map<String, dynamic> memory) async {
    final userId = context.read<UserService>().userId;
    await _cache.upsertMemory({...memory, 'user_id': userId});
    setState(() => _memories.insert(0, memory));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('小碎'),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SearchScreen()),
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
                    style: Theme.of(context)
                        .textTheme
                        .labelSmall
                        ?.copyWith(color: Colors.orange),
                  ),
                ],
              ),
            ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _memories.isEmpty
                    ? const _EmptyState()
                    : RefreshIndicator(
                        onRefresh: _loadMemories,
                        child: ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
                          itemCount: _memories.length,
                          itemBuilder: (_, i) => MemoryCard(memory: _memories[i]),
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

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.mic_none, size: 64, color: Colors.white24),
          const SizedBox(height: 16),
          Text('按下按钮，随口一记', style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }
}

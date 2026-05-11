import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/services/api_service.dart';
import '../../../core/services/user_service.dart';
import '../../../core/services/voice_record_service.dart';
import '../../../shared/widgets/permission_dialogs.dart';
import '../../memory/presentation/widgets/memory_card.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _controller = TextEditingController();
  bool _loading = false;
  String? _answer;
  List<Map<String, dynamic>> _sources = [];
  String? _error;

  Future<void> _search(String query) async {
    if (query.trim().isEmpty) return;
    setState(() { _loading = true; _error = null; _answer = null; _sources = []; });

    try {
      final api = context.read<ApiService>();
      final userId = context.read<UserService>().userId;
      final result = await api.search(query: query.trim(), userId: userId);
      setState(() {
        _answer = result['answer'] as String?;
        _sources = (result['sources'] as List? ?? []).cast<Map<String, dynamic>>();
      });
    } catch (e) {
      setState(() => _error = '搜索失败: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _handleVoiceTap() async {
    final voiceSvc = context.read<VoiceRecordService>();

    if (voiceSvc.state == RecordingState.idle) {
      await voiceSvc.startRecording();
      if (voiceSvc.lastError != null && mounted) {
        await showPermissionHelpDialog(
          context: context,
          title: '需要麦克风权限',
          message: '请允许小碎使用麦克风，这样才能录制语音提问。如果系统没有弹出授权框，可能是之前已经拒绝过，需要到设置里重新开启。',
        );
      }
      return;
    }

    if (voiceSvc.state == RecordingState.recording) {
      final userId = context.read<UserService>().userId;
      final result = await voiceSvc.stopAndUpload(userId: userId);
      if (result != null) {
        final text = result['raw_text'] as String? ?? '';
        _controller.text = text;
        _search(text);
      }
      if (voiceSvc.lastError != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(voiceSvc.lastError!)),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final voiceSvc = context.watch<VoiceRecordService>();

    return Scaffold(
      appBar: AppBar(title: const Text('找记忆')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: '问一问，比如"剪刀在哪"',
                      hintStyle: theme.textTheme.bodyMedium,
                      filled: true,
                      fillColor: theme.colorScheme.surface,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                    onSubmitted: _search,
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: voiceSvc.state == RecordingState.processing
                      ? null
                      : _handleVoiceTap,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: voiceSvc.isRecording
                          ? theme.colorScheme.primary
                          : theme.colorScheme.surface,
                    ),
                    child: Icon(
                      voiceSvc.isRecording ? Icons.stop : Icons.mic,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.search, color: Colors.white),
                  onPressed: () => _search(_controller.text),
                ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(child: Text(_error!, style: theme.textTheme.bodyMedium))
                    : _answer == null
                        ? Center(
                            child: Text('输入问题或按麦克风语音提问', style: theme.textTheme.bodyMedium),
                          )
                        : ListView(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            children: [
                              Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.primary.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: theme.colorScheme.primary.withValues(alpha: 0.4),
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Icon(Icons.auto_awesome, size: 16, color: theme.colorScheme.primary),
                                        const SizedBox(width: 6),
                                        Text('AI 回答', style: TextStyle(color: theme.colorScheme.primary, fontWeight: FontWeight.w600)),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Text(_answer!, style: theme.textTheme.bodyLarge),
                                  ],
                                ),
                              ),
                              if (_sources.isNotEmpty) ...[
                                const SizedBox(height: 16),
                                Text('相关记录', style: theme.textTheme.bodyMedium),
                                const SizedBox(height: 8),
                                ..._sources.map((m) => MemoryCard(memory: m)),
                              ],
                            ],
                          ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}

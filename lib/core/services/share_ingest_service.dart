import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'api_service.dart';
import '../db/memory_cache.dart';

/// 对接 iOS Share Extension。Share Extension 会把用户分享的文字
/// 写入共享 App Group 的 UserDefaults，然后尝试打开主应用的
/// URL scheme 唤起。主应用这边通过 platform channel 把队列取出来，
/// 挨个调用 /add_memory_text。
class ShareIngestService extends ChangeNotifier {
  static const _channel = MethodChannel('com.xiaosui.xiaosui/share');

  final ApiService _api;
  final MemoryCache _cache;
  final List<Map<String, dynamic>> _ingested = [];
  bool _processing = false;

  ShareIngestService(this._api, this._cache) {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'sharesAvailable') {
        // 扩展写完数据后，主应用被唤起时原生层会通知一次
        await processPending(userIdProvider?.call() ?? 'default');
      }
    });
  }

  /// 允许宿主在用户登录后注入 user id 取得函数
  String Function()? userIdProvider;

  bool get isProcessing => _processing;
  List<Map<String, dynamic>> get ingested => List.unmodifiable(_ingested);

  Future<List<String>> _fetchPending() async {
    if (!defaultTargetPlatform.name.contains('iOS') && !_isIOS()) return [];
    try {
      final result =
          await _channel.invokeMethod<List<dynamic>>('fetchPending');
      return (result ?? []).map((e) => e.toString()).toList();
    } on MissingPluginException {
      return [];
    } catch (_) {
      return [];
    }
  }

  bool _isIOS() {
    // kIsWeb 在 web 下为 true，其它平台用 defaultTargetPlatform
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.iOS;
  }

  /// 将共享队列中的文字逐条提交到后端，并写入本地缓存。
  /// 返回新增的记忆列表（已按提交顺序）。
  Future<List<Map<String, dynamic>>> processPending(String userId) async {
    if (_processing) return const [];
    _processing = true;
    notifyListeners();

    final texts = await _fetchPending();
    final results = <Map<String, dynamic>>[];
    try {
      for (final t in texts) {
        final text = t.trim();
        if (text.isEmpty) continue;
        try {
          final memory = await _api.addMemoryText(text: text, userId: userId);
          await _cache.upsertMemory({...memory, 'user_id': userId});
          results.add(memory);
        } catch (_) {
          // 单条失败不影响后续；失败数据已在 UserDefaults 里被消费了，
          // 为了不让同一条反复失败，先按"尽力而为"丢弃。
        }
      }
      _ingested.addAll(results);
    } finally {
      _processing = false;
      notifyListeners();
    }
    return results;
  }
}

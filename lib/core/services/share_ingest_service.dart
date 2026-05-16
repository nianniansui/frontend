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

  /// 当原生层 / 宿主调用 processPending 写入新记忆时通知 UI
  final StreamController<List<Map<String, dynamic>>> _ingestStream =
      StreamController.broadcast();

  /// 诊断事件流：每一步发生了什么 —— 用于在 UI 上即时弹 Snackbar，
  /// 不用 Mac Console 也能看到 share 链路卡在哪一步。
  final StreamController<String> _diagStream =
      StreamController.broadcast();

  String? lastDiag;

  Stream<List<Map<String, dynamic>>> get ingestStream => _ingestStream.stream;
  Stream<String> get diagStream => _diagStream.stream;

  void _diag(String msg) {
    lastDiag = msg;
    // ignore: avoid_print
    print('[ShareIngest] $msg');
    if (!_diagStream.isClosed) _diagStream.add(msg);
  }

  ShareIngestService(this._api, this._cache) {
    if (_isIOS()) {
      _channel.setMethodCallHandler((call) async {
        _diag('原生回调: ${call.method}');
        if (call.method == 'sharesAvailable') {
          final userId = userIdProvider?.call() ?? '';
          if (userId.isEmpty) {
            _diag('sharesAvailable 但 userId 还没就绪');
            return;
          }
          await processPending(userId);
        }
      });
      _diag('Channel 已注册');
    }
  }

  /// 允许宿主在用户登录后注入 user id 取得函数
  String Function()? userIdProvider;

  bool get isProcessing => _processing;
  List<Map<String, dynamic>> get ingested => List.unmodifiable(_ingested);

  Future<List<String>> _fetchPending() async {
    if (!_isIOS()) return [];
    try {
      final result =
          await _channel.invokeMethod<List<dynamic>>('fetchPending');
      return (result ?? []).map((e) => e.toString()).toList();
    } on MissingPluginException {
      _diag('Channel 还没注册（fetchPending）');
      return [];
    } catch (e) {
      _diag('fetchPending 失败: $e');
      return [];
    }
  }

  bool _isIOS() {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.iOS;
  }

  /// 将共享队列中的文字逐条提交到后端，并写入本地缓存。
  /// 返回新增的记忆列表（已按提交顺序）。
  Future<List<Map<String, dynamic>>> processPending(String userId) async {
    if (_processing) {
      _diag('processPending 已在处理，跳过');
      return const [];
    }
    _processing = true;
    notifyListeners();

    final texts = await _fetchPending();
    _diag('共享队列里有 ${texts.length} 条');
    final results = <Map<String, dynamic>>[];
    try {
      for (final t in texts) {
        final text = t.trim();
        if (text.isEmpty) continue;
        try {
          _diag('上传中: ${_preview(text)}');
          final memory = await _api.addMemoryText(text: text, userId: userId);
          await _cache.upsertMemory({...memory, 'user_id': userId});
          results.add(memory);
        } catch (e) {
          _diag('上传失败: $e');
        }
      }
      _ingested.addAll(results);
      if (results.isNotEmpty) {
        _ingestStream.add(results);
      } else if (texts.isNotEmpty) {
        _diag('队列里 ${texts.length} 条全部上传失败');
      }
    } finally {
      _processing = false;
      notifyListeners();
    }
    return results;
  }

  String _preview(String s) =>
      s.length <= 20 ? s : '${s.substring(0, 20)}…';

  @override
  void dispose() {
    _ingestStream.close();
    _diagStream.close();
    super.dispose();
  }
}

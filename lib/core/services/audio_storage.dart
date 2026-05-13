import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// 统一管理原音文件的存储位置。
///
/// 在 iOS 上，App 沙盒容器的 UUID 会在重装 / 系统更新时变化，
/// 绝对路径会失效。因此数据库里只存文件名，
/// 播放时再用当前 Documents 目录拼出绝对路径。
class AudioStorage {
  static Future<String> audioDir() async {
    final dir = await getApplicationDocumentsDirectory();
    final d = Directory('${dir.path}/audio');
    if (!await d.exists()) {
      await d.create(recursive: true);
    }
    return d.path;
  }

  /// 生成一条新录音的文件名（不带路径）
  static String newFileName() =>
      'xiaosui_${DateTime.now().millisecondsSinceEpoch}.wav';

  /// 根据存储值解析出当前有效的绝对路径。
  /// 兼容历史数据：如果存的是绝对路径，fallback 用 basename 重新拼。
  static Future<String> resolve(String stored) async {
    if (kIsWeb || stored.isEmpty) return stored;
    if (stored.startsWith('/')) {
      if (await File(stored).exists()) return stored;
      final base = stored.split('/').last;
      return '${await audioDir()}/$base';
    }
    return '${await audioDir()}/$stored';
  }

  /// 存储值对应的文件是否还在
  static Future<bool> exists(String stored) async {
    if (kIsWeb || stored.isEmpty) return false;
    final path = await resolve(stored);
    return File(path).exists();
  }
}

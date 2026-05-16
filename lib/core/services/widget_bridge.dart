import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 把"最近一条记忆"推到 App Group UserDefaults，给 iOS Widget 显示。
///
/// 通过自定义 method channel 直接调原生方法，避免再引入第三方插件。
class WidgetBridge {
  static const _channel = MethodChannel('com.xiaosui.xiaosui/widget');
  static const _kindMain = 'XiaosuiWidget';

  static Future<void> updateLatestSummary(String text) async {
    if (kIsWeb) return;
    if (defaultTargetPlatform != TargetPlatform.iOS) return;
    final clean = text.trim();
    if (clean.isEmpty) return;
    try {
      await _channel.invokeMethod('updateLatestSummary', {
        'text': clean.length > 120 ? clean.substring(0, 120) : clean,
        'kind': _kindMain,
      });
    } on MissingPluginException {
      // 老版本 Runner 还没注册原生 handler 时静默
    } catch (e) {
      debugPrint('[WidgetBridge] update failed: $e');
    }
  }
}

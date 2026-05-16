import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'api_service.dart';

/// 通道编号的命名规则：
/// - reminders 通道：从用户记忆里抽出来的"未来事件"
/// - recap     通道：每日早晨的"那年今日"回顾
///
/// 提醒走本地通知（不需要付费 Apple Developer）。代价是：用户至少
/// 每周打开一次 App，预定的通知队列才会续上。这刚好和我们想推动的
/// 留存目标一致。
class NotificationService {
  static const _channelReminders = 'reminders';
  static const _channelRecap = 'recap';

  /// 用户记忆里抽出的提醒走 1xxxx；recap 走 2xxxx。
  /// 不能用普通字符串 hash —— iOS 通知 id 只接受 32 位 int。
  static const _idBaseReminder = 10000;
  static const _idRecapDaily = 20001;

  static const _prefsLastSyncKey = 'notif_last_sync_iso';
  static const _prefsRecapEnabled = 'notif_recap_enabled';
  static const _prefsRecapHour = 'notif_recap_hour';
  static const _prefsRecapMinute = 'notif_recap_minute';

  static final NotificationService instance = NotificationService._();
  NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  /// 通知点击的回调。MainApp 设置一次，由 deep link 处理打开记忆/录音页
  void Function(String? payload)? onNotificationTap;

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    tzdata.initializeTimeZones();
    // iOS 没有 timezone API，只能猜本地区。多数中文用户在 Asia/Shanghai
    tz.setLocalLocation(tz.getLocation('Asia/Shanghai'));

    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _plugin.initialize(
      const InitializationSettings(iOS: iosInit, android: androidInit),
      onDidReceiveNotificationResponse: (resp) {
        onNotificationTap?.call(resp.payload);
      },
    );
  }

  /// 申请权限。返回 true 表示用户允许通知。
  Future<bool> requestPermission() async {
    if (!_initialized) await init();
    if (kIsWeb) return false;
    final ios = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    if (ios != null) {
      return await ios.requestPermissions(alert: true, badge: true, sound: true) ??
          false;
    }
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      return await android.requestNotificationsPermission() ?? false;
    }
    return false;
  }

  /// 同步：拉后端 upcoming + recap，预定到本地。
  /// 失败安静吞掉，不能影响主流程。
  Future<void> syncFromServer({
    required ApiService api,
    required String userId,
  }) async {
    if (!_initialized) await init();
    if (userId.isEmpty || kIsWeb) return;

    // 频控：6 小时内不重复同步
    final prefs = await SharedPreferences.getInstance();
    final last = prefs.getString(_prefsLastSyncKey);
    if (last != null) {
      final lastDt = DateTime.tryParse(last);
      if (lastDt != null &&
          DateTime.now().difference(lastDt) < const Duration(hours: 6)) {
        return;
      }
    }

    try {
      // 1) 提醒
      final reminders = await api.upcomingReminders(userId: userId, days: 7);
      await _scheduleReminders(reminders);
      // 2) recap：每天早上 9:00（默认）
      if (prefs.getBool(_prefsRecapEnabled) ?? true) {
        final hour = prefs.getInt(_prefsRecapHour) ?? 9;
        final minute = prefs.getInt(_prefsRecapMinute) ?? 7;  // 错峰，避开整点拥堵
        final recap = await api.recapToday(userId: userId);
        await _scheduleDailyRecap(
          hour: hour,
          minute: minute,
          recap: recap,
        );
      }
      await prefs.setString(_prefsLastSyncKey, DateTime.now().toIso8601String());
    } catch (e) {
      debugPrint('[Notif] sync failed: $e');
    }
  }

  Future<void> _scheduleReminders(List<Map<String, dynamic>> reminders) async {
    // 先取消旧的 reminder 通道，避免堆积
    final pending = await _plugin.pendingNotificationRequests();
    for (final p in pending) {
      if (p.id >= _idBaseReminder && p.id < _idBaseReminder + 9999) {
        await _plugin.cancel(p.id);
      }
    }

    int slot = 0;
    for (final r in reminders) {
      final triggerStr = r['trigger_at'] as String?;
      final title = r['title'] as String? ?? '提醒';
      final memoryId = r['memory_id'] as String?;
      if (triggerStr == null) continue;
      final dt = DateTime.tryParse(triggerStr);
      if (dt == null) continue;
      // 已过的丢弃；30 秒内的也丢弃（可能 race）
      if (dt.isBefore(DateTime.now().add(const Duration(seconds: 30)))) continue;

      final tzDt = tz.TZDateTime.from(dt.toLocal(), tz.local);
      final id = _idBaseReminder + slot;
      slot++;

      await _plugin.zonedSchedule(
        id,
        '小碎',
        title,
        tzDt,
        NotificationDetails(
          iOS: const DarwinNotificationDetails(
            categoryIdentifier: _channelReminders,
            interruptionLevel: InterruptionLevel.timeSensitive,
          ),
          android: AndroidNotificationDetails(
            _channelReminders,
            '提醒',
            channelDescription: '从你的记录中识别出的未来事件',
            importance: Importance.high,
            priority: Priority.high,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        payload: memoryId == null ? null : 'memory:$memoryId',
      );
    }
    debugPrint('[Notif] scheduled $slot reminders');
  }

  Future<void> _scheduleDailyRecap({
    required int hour,
    required int minute,
    required Map<String, dynamic>? recap,
  }) async {
    await _plugin.cancel(_idRecapDaily);

    final body = (recap?['body'] as String?)?.trim();
    if (body == null || body.isEmpty) return;
    final title = (recap?['title'] as String?)?.trim() ?? '翻翻你的记忆';
    final memoryId = recap?['memory_id'] as String?;

    final now = tz.TZDateTime.now(tz.local);
    var fire = tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    if (!fire.isAfter(now)) {
      fire = fire.add(const Duration(days: 1));
    }

    await _plugin.zonedSchedule(
      _idRecapDaily,
      title,
      body,
      fire,
      NotificationDetails(
        iOS: const DarwinNotificationDetails(
          categoryIdentifier: _channelRecap,
          interruptionLevel: InterruptionLevel.passive,
        ),
        android: AndroidNotificationDetails(
          _channelRecap,
          '每日回顾',
          channelDescription: '每天早晨从你的记忆中挑一条回看',
          importance: Importance.defaultImportance,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time,
      payload: memoryId == null ? null : 'memory:$memoryId',
    );
    debugPrint('[Notif] daily recap scheduled at ${fire.toIso8601String()}');
  }

  /// 设置页关闭/开启每日回顾
  Future<void> setRecapEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsRecapEnabled, enabled);
    if (!enabled) {
      await _plugin.cancel(_idRecapDaily);
      // 同时把上次同步时间清空，下次启动会重新同步状态
      await prefs.remove(_prefsLastSyncKey);
    }
  }

  Future<bool> isRecapEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefsRecapEnabled) ?? true;
  }
}

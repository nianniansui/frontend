import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'core/db/memory_cache.dart';
import 'core/services/api_service.dart';
import 'core/services/notification_service.dart';
import 'core/services/share_ingest_service.dart';
import 'core/services/theme_service.dart';
import 'core/services/user_service.dart';
import 'core/services/voice_record_service.dart';
import 'features/memory/presentation/screens/home_screen.dart';
import 'shared/theme/app_theme.dart';

/// 通知点击时携带的全局意图，由 HomeScreen 在 didChangeAppLifecycleState 里消费。
final ValueNotifier<String?> pendingNotificationPayload =
    ValueNotifier<String?>(null);

void main() {
  // 把所有 zone 未处理异常 / Flutter framework 异常捕住，避免冷启动栈顶异常秒崩
  runZonedGuarded<void>(() async {
    WidgetsFlutterBinding.ensureInitialized();

    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      debugPrint('[XiaoSui] FlutterError: ${details.exceptionAsString()}\n${details.stack}');
    };

    final userService = UserService();
    final themeService = ThemeService();

    // NotificationService 初始化必须在 runApp 前（点击通知冷启动时要拿到 payload）
    final notif = NotificationService.instance;
    await notif.init();
    notif.onNotificationTap = (payload) {
      pendingNotificationPayload.value = payload;
    };

    runApp(XiaoSuiApp(userService: userService, themeService: themeService));
    unawaited(userService.init());
    unawaited(themeService.load());
  }, (error, stack) {
    // 捕住最后一道防线：异步路径里抛出的未 catch 异常
    debugPrint('[XiaoSui] Uncaught zone error: $error\n$stack');
  });
}

class XiaoSuiApp extends StatelessWidget {
  final UserService userService;
  final ThemeService themeService;
  const XiaoSuiApp({
    super.key,
    required this.userService,
    required this.themeService,
  });

  @override
  Widget build(BuildContext context) {
    final api = ApiService(
      baseUrl: kIsWeb ? '' : 'http://101.35.55.189:8000',
    );
    final shareIngest = ShareIngestService(api, MemoryCache())
      ..userIdProvider = () => userService.userId;

    return MultiProvider(
      providers: [
        Provider<ApiService>.value(value: api),
        ChangeNotifierProvider<UserService>.value(value: userService),
        ChangeNotifierProvider<ThemeService>.value(value: themeService),
        ChangeNotifierProvider<ShareIngestService>.value(value: shareIngest),
        ChangeNotifierProvider(
          create: (_) => VoiceRecordService(api),
        ),
      ],
      child: Consumer<ThemeService>(
        builder: (_, theme, _) => MaterialApp(
          title: '小碎',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          themeMode: theme.mode,
          home: const HomeScreen(),
        ),
      ),
    );
  }
}

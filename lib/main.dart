import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'core/services/api_service.dart';
import 'core/services/theme_service.dart';
import 'core/services/user_service.dart';
import 'core/services/voice_record_service.dart';
import 'features/memory/presentation/screens/home_screen.dart';
import 'shared/theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final userService = UserService();
  final themeService = ThemeService();
  runApp(XiaoSuiApp(userService: userService, themeService: themeService));
  unawaited(userService.init());
  unawaited(themeService.load());
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

    return MultiProvider(
      providers: [
        Provider<ApiService>.value(value: api),
        ChangeNotifierProvider<UserService>.value(value: userService),
        ChangeNotifierProvider<ThemeService>.value(value: themeService),
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

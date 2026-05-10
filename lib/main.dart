import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'core/services/api_service.dart';
import 'core/services/user_service.dart';
import 'core/services/voice_record_service.dart';
import 'features/memory/presentation/screens/home_screen.dart';
import 'shared/theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final userService = UserService();
  await userService.init();
  runApp(XiaoSuiApp(userService: userService));
}

class XiaoSuiApp extends StatelessWidget {
  final UserService userService;
  const XiaoSuiApp({super.key, required this.userService});

  @override
  Widget build(BuildContext context) {
    final api = ApiService(
      baseUrl: kIsWeb ? '' : 'http://localhost:8000',
    );

    return MultiProvider(
      providers: [
        Provider<ApiService>.value(value: api),
        ChangeNotifierProvider<UserService>.value(value: userService),
        ChangeNotifierProvider(
          create: (_) => VoiceRecordService(api),
        ),
      ],
      child: MaterialApp(
        title: '小碎',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.dark,
        home: const HomeScreen(),
      ),
    );
  }
}

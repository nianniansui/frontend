import 'package:flutter_test/flutter_test.dart';
import 'package:xiaosui/core/services/theme_service.dart';
import 'package:xiaosui/core/services/user_service.dart';
import 'package:xiaosui/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    final userService = UserService();
    await userService.init();
    final themeService = ThemeService();
    await tester.pumpWidget(
      XiaoSuiApp(userService: userService, themeService: themeService),
    );
    expect(find.byType(XiaoSuiApp), findsOneWidget);
  });
}

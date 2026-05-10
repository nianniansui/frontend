import 'package:flutter_test/flutter_test.dart';
import 'package:xiaosui/core/services/user_service.dart';
import 'package:xiaosui/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    final userService = UserService();
    await userService.init();
    await tester.pumpWidget(XiaoSuiApp(userService: userService));
    expect(find.byType(XiaoSuiApp), findsOneWidget);
  });
}

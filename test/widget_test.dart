import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:glowblast/data/repositories/app_repository.dart';
import 'package:glowblast/main.dart';
import 'package:glowblast/features/auth/screens/landing_screen.dart';
import 'package:glowblast/features/main_nav/main_navigation_screen.dart';

void main() {
  testWidgets('GlowBlast first launch shows LandingScreen when no profile exists', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final repository = AppRepository();
    await repository.init();

    await tester.pumpWidget(GlowBlastApp(repository: repository));
    expect(find.byType(GlowBlastApp), findsOneWidget);

    // Advance past splash animation & timer
    await tester.pump(const Duration(milliseconds: 2500));
    await tester.pumpAndSettle();

    // Verify LandingScreen is shown
    expect(find.byType(LandingScreen), findsOneWidget);
    expect(find.text('Get Started'), findsOneWidget);
  });

  testWidgets('GlowBlast relaunch skips LandingScreen and goes to MainNavigationScreen when profile is set', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final repository = AppRepository();
    await repository.init();

    await repository.updateSettings(
      repository.settings.copyWith(
        fullName: 'Pooja Sharma',
        businessName: 'Aura Wellness',
        phone: '+91 98765 43210',
      ),
    );

    await tester.pumpWidget(GlowBlastApp(repository: repository));
    await tester.pump(const Duration(milliseconds: 2500));
    await tester.pumpAndSettle();

    // Verify MainNavigationScreen is shown
    expect(find.byType(MainNavigationScreen), findsOneWidget);
    expect(find.text('Pooja Sharma'), findsOneWidget);
    expect(find.text('Aura Wellness'), findsOneWidget);
  });
}

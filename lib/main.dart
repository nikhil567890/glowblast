import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'core/theme/app_theme.dart';
import 'core/constants/app_strings.dart';
import 'data/repositories/app_repository.dart';
import 'features/auth/screens/splash_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Set preferred orientation for mobile UX
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  final repository = AppRepository();
  await repository.init();

  runApp(GlowBlastApp(repository: repository));
}

class GlowBlastApp extends StatelessWidget {
  final AppRepository repository;

  const GlowBlastApp({super.key, required this.repository});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: repository,
      builder: (context, _) {
        final themeModeStr = repository.settings.themeMode;
        ThemeMode themeMode = ThemeMode.system;
        if (themeModeStr == 'light') themeMode = ThemeMode.light;
        if (themeModeStr == 'dark') themeMode = ThemeMode.dark;

        return MaterialApp(
          title: AppStrings.appName,
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: themeMode,
          home: SplashScreen(repository: repository),
        );
      },
    );
  }
}

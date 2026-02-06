import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'services/notification_service.dart';

import 'core/theme/app_theme.dart';
import 'core/services/theme_service.dart';
import 'features/auth/screens/login_page.dart';
import 'core/config/app_config.dart';
import 'core/di/service_locator.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Inicializar locale para formatação de datas
  await initializeDateFormatting('pt_BR', null);

  // Inicializar Supabase
  await Supabase.initialize(
    url: AppConfig.supabaseUrl,
    anonKey: AppConfig.supabaseAnonKey,
  );

  // Inicializar serviços
  await NotificationService().initialize();
  await ThemeService().loadTheme();
  
  // Setup Service Locator (Mock or Real)
  ServiceLocator.setup();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeService().themeMode,
      builder: (context, currentMode, _) {
        return MaterialApp(
          title: 'Gestão de Estacionamentos',
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: currentMode,
          home: const LoginPage(),
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [
            Locale('pt', 'BR'),
          ],
          debugShowCheckedModeBanner: false,
        );
      },
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/app_config.dart';
import 'core/theme.dart';
import 'providers/lookup_provider.dart';
import 'providers/settings_provider.dart';
import 'screens/home_screen.dart';
import 'services/notification_service.dart';
import 'services/when_is_bins_api.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load();

  final prefs = await SharedPreferences.getInstance();
  final api = WhenIsBinsApi(
    client: http.Client(),
    baseUrl: AppConfig.baseUrl,
    token: AppConfig.apiToken,
  );
  final notificationService = NotificationService();
  await notificationService.init();

  runApp(
    MultiProvider(
      providers: [
        Provider<WhenIsBinsApi>.value(value: api),
        Provider<NotificationService>.value(value: notificationService),
        ChangeNotifierProvider(
          create: (_) => LookupProvider(api: api),
        ),
        ChangeNotifierProvider(
          create: (_) => SettingsProvider(prefs),
        ),
      ],
      child: const WhenIsBinApp(),
    ),
  );
}

class WhenIsBinApp extends StatelessWidget {
  const WhenIsBinApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'When is bin day',
      theme: AppTheme.light,
      home: const HomeScreen(),
    );
  }
}

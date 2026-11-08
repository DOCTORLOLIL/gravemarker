import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'data.dart';
import 'l10n/app_localizations.dart';
import 'screens/search.dart';
import 'screens/welcome.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(url: supabaseUrl, anonKey: supabaseKey);
  final prefs = await SharedPreferences.getInstance();
  final blessed = prefs.getInt('blessed') ?? 0;
  final showWelcome = DateTime.now().millisecondsSinceEpoch - blessed > const Duration(days: 30).inMilliseconds;
  runApp(GraveMarkerApp(showWelcome: showWelcome));
}

const teal = Color(0xFF1F5B57);

class GraveMarkerApp extends StatelessWidget {
  final bool showWelcome;
  const GraveMarkerApp({super.key, required this.showWelcome});

  ThemeData _theme(Brightness b) {
    final dark = b == Brightness.dark;
    final scheme = ColorScheme.fromSeed(seedColor: teal, brightness: b, primary: dark ? const Color(0xFF5FB3AA) : teal);
    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      scaffoldBackgroundColor: dark ? const Color(0xFF15181B) : const Color(0xFFF4F1EC),
      cardTheme: CardThemeData(
        color: dark ? const Color(0xFF1E2226) : const Color(0xFFFFFDF9),
        elevation: 0,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: dark ? const Color(0xFF30353A) : const Color(0xFFE2DDD4))),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      onGenerateTitle: (c) => AppLocalizations.of(c).appTitle,
      debugShowCheckedModeBanner: false,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      locale: const Locale('he'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: showWelcome ? const WelcomeScreen() : const SearchScreen(),
    );
  }
}

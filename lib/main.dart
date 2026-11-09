import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'data.dart';
import 'l10n/app_localizations.dart';
import 'lang.dart';
import 'reminders.dart';
import 'screens/detail.dart';
import 'screens/search.dart';
import 'screens/welcome.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(url: supabaseUrl, publishableKey: supabaseKey);
  final prefs = await SharedPreferences.getInstance();
  appLang.value = prefs.getString('lang');
  final blessed = prefs.getInt('blessed') ?? 0;
  final showWelcome = DateTime.now().millisecondsSinceEpoch - blessed > const Duration(days: 30).inMilliseconds;
  try {
    await Reminders.init();
    Reminders.reschedule();
  } catch (_) {}
  runApp(GraveMarkerApp(showWelcome: showWelcome));
}

const teal = Color(0xFF1F5B57);
final navKey = GlobalKey<NavigatorState>();


void _open(int id, String cem) {
  final nav = navKey.currentState;
  if (nav != null) openFromReminder(nav, id, cem, (d, c) => DetailScreen(deceased: d, cemetery: c));
}

class GraveMarkerApp extends StatefulWidget {
  final bool showWelcome;
  const GraveMarkerApp({super.key, required this.showWelcome});
  @override
  State<GraveMarkerApp> createState() => _GraveMarkerAppState();
}

class _GraveMarkerAppState extends State<GraveMarkerApp> {
  @override
  void initState() {
    super.initState();
    Reminders.onOpen = _open;
    final l = Reminders.launchedFrom;
    if (l != null) WidgetsBinding.instance.addPostFrameCallback((_) => _open(l.$1, l.$2));
  }

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
    return ValueListenableBuilder<String?>(valueListenable: appLang, builder: (context, lang, _) => MaterialApp(
      navigatorKey: navKey,
      onGenerateTitle: (c) => AppLocalizations.of(c).appTitle,
      debugShowCheckedModeBanner: false,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      locale: lang == null ? null : Locale(lang),
      localeResolutionCallback: (device, supported) =>
          langs.contains(device?.languageCode) ? Locale(device!.languageCode) : const Locale('he'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: widget.showWelcome ? const WelcomeScreen() : const SearchScreen(),
    ));
  }
}

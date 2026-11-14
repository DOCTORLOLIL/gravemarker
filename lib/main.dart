import 'dart:async';
import 'dart:ui' show PlatformDispatcher;

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'data.dart';
import 'l10n/app_localizations.dart';
import 'lang.dart';
import 'reminders.dart';
import 'routes.dart';
import 'screens/azkara.dart';
import 'screens/route.dart';
import 'shabbat.dart';
import 'stats.dart';
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
  // ספירת התקנה כבר בפתיחה, גם אם המשתמש עוד במסך הפתיחה
  pingInstall(appLang.value ?? PlatformDispatcher.instance.locale.languageCode);
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
  Future<void> _openRoute(Uri u) async {
    final nav = navKey.currentState;
    if (nav == null) return;
    final a = Azkara.fromUri(u);
    if (a != null) return AzkaraInviteScreen.open(nav, a);
    final r = VisitRoute.fromUri(u);
    if (r == null) return;
    await RouteStore.setActive(r);
    nav.push(MaterialPageRoute(builder: (_) => RouteScreen(route: r)));
  }

  DateTime? _shabbatEnd = Shabbat.end();
  Timer? _shabbatTimer;

  @override
  void dispose() {
    _shabbatTimer?.cancel();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _shabbatTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      final e = Shabbat.end();
      if (e != _shabbatEnd) setState(() => _shabbatEnd = e);
    });
    Reminders.onOpen = _open;
    // קישור למסלול ששותף (gravemarker.bulu.ltd/r/...)
    final links = AppLinks();
    links.getInitialLink().then((u) {
      if (u != null) WidgetsBinding.instance.addPostFrameCallback((_) => _openRoute(u));
    });
    links.uriLinkStream.listen(_openRoute);
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
      // בשבת: מסך שבת מעל כל האפליקציה
      builder: (context, child) => Stack(children: [
        if (child != null) child,
        if (_shabbatEnd != null) ShabbatScreen(until: _shabbatEnd!),
      ]),
    ));
  }
}


class ShabbatScreen extends StatelessWidget {
  final DateTime until;
  const ShabbatScreen({super.key, required this.until});
  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Material(
      color: teal,
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text('🕯️🕯️', style: TextStyle(fontSize: 56)),
              const SizedBox(height: 14),
              Text(t.shabbatMsg,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold, height: 1.4)),
              const SizedBox(height: 18),
              Text(t.shabbatBack(Shabbat.hhmm(until)),
                  textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70, fontSize: 16)),
              const SizedBox(height: 28),
              Text(t.shabbatShalom, style: const TextStyle(color: Colors.white60, fontSize: 14)),
            ]),
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/app_localizations.dart';
import '../translit.dart';
import 'search.dart';

class WelcomeScreen extends StatelessWidget {
  /// popOnly: נפתח מתוך האפליקציה (קישור "ברכת הרואה קברים") – חוזרים אחורה במקום להחליף מסך
  final bool popOnly;
  const WelcomeScreen({super.key, this.popOnly = false});

  Future<void> _enter(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('blessed', DateTime.now().millisecondsSinceEpoch);
    if (!context.mounted) return;
    if (popOnly) {
      Navigator.of(context).pop();
    } else {
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const SearchScreen()));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final mute = Theme.of(context).colorScheme.onSurfaceVariant;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(t.welcome, style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  Text(t.beforeEntering, style: TextStyle(color: mute)),
                  const SizedBox(height: 22),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        Text(t.blessing,
                            textDirection: TextDirection.rtl,
                            textAlign: TextAlign.justify,
                            style: const TextStyle(fontSize: 20, height: 1.9)),
                        // מי שהאפליקציה שלו לא בעברית – מקבל גם תעתיק
                        if (Localizations.localeOf(context).languageCode != 'he') ...[
                          const Divider(height: 24),
                          Text(
                            translit(t.blessing, Localizations.localeOf(context).languageCode == 'ru' ? 'cyr' : 'lat'),
                            textDirection: TextDirection.ltr,
                            style: TextStyle(fontSize: 16, height: 1.6, color: mute),
                          ),
                        ],
                      ]),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(t.blessingNote, style: TextStyle(color: mute, fontSize: 13)),
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: () => _enter(context),
                    style: FilledButton.styleFrom(minimumSize: const Size(160, 48)),
                    child: Text(t.enter),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

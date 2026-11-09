import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'reminders.dart';

/// שפה שנבחרה בתפריט (null = לפי שפת הטלפון)
final appLang = ValueNotifier<String?>(null);
const langs = ['he', 'en', 'fr', 'ru', 'am'];

Future<void> setLang(String? code) async {
  final prefs = await SharedPreferences.getInstance();
  code == null ? await prefs.remove('lang') : await prefs.setString('lang', code);
  appLang.value = code;
  Reminders.reschedule();
}

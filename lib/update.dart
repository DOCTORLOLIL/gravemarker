import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

/// מספר הגרסה של האפליקציה (נקבע בבנייה)
const appBuild = int.fromEnvironment('BUILD');

const _versionUrl = 'https://github.com/DOCTORLOLIL/gravemarker/releases/download/test-build/version.json';

/// מחזיר קישור לעדכון אם יש גרסה חדשה שעוד לא נדחתה
Future<(int, String)?> checkUpdate() async {
  if (appBuild == 0) return null;
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 6);
  try {
    final req = await client.getUrl(Uri.parse('$_versionUrl?t=${DateTime.now().millisecondsSinceEpoch ~/ 3600000}'));
    final res = await req.close().timeout(const Duration(seconds: 8));
    if (res.statusCode != 200) return null;
    final j = jsonDecode(await res.transform(utf8.decoder).join()) as Map<String, dynamic>;
    final build = (j['build'] as num?)?.toInt() ?? 0;
    final url = j['url'] as String? ?? 'https://gravemarker.bulu.ltd/download/';
    final skipped = (await SharedPreferences.getInstance()).getInt('skipUpdate') ?? 0;
    return build > appBuild && build > skipped ? (build, url) : null;
  } catch (_) {
    return null;
  } finally {
    client.close();
  }
}

Future<void> skipUpdate(int build) async => (await SharedPreferences.getInstance()).setInt('skipUpdate', build);

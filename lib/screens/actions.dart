import 'dart:math' as math;

import 'package:exif/exif.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';

import '../data.dart';
import '../geo.dart';
import '../l10n/app_localizations.dart';

String _rand() {
  final r = math.Random.secure();
  return List.generate(16, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
}

double? _deg(IfdTag? tag, IfdTag? ref) {
  if (tag == null) return null;
  try {
    final List v = (tag.values as dynamic).toList();
    double num(dynamic x) => x is num ? x.toDouble() : (x.numerator as int) / (x.denominator as int);
    var d = num(v[0]) + num(v[1]) / 60 + num(v[2]) / 3600;
    final r = ref?.printable ?? '';
    if (r.startsWith('S') || r.startsWith('W')) d = -d;
    return d.isFinite ? d : null;
  } catch (_) {
    return null;
  }
}

/// מיקום הצילום מתוך נתוני התמונה: (מיקום, דיוק במטרים)
Future<(LatLng, double)?> photoGps(List<int> bytes) async {
  try {
    final tags = await readExifFromBytes(bytes);
    final lat = _deg(tags['GPS GPSLatitude'], tags['GPS GPSLatitudeRef']);
    final lng = _deg(tags['GPS GPSLongitude'], tags['GPS GPSLongitudeRef']);
    if (lat == null || lng == null || (lat == 0 && lng == 0)) return null;
    var acc = 8.0;
    final e = tags['GPS GPSHPositioningError'];
    if (e != null) {
      final List v = (e.values as dynamic).toList();
      final x = v.first;
      final a = x is num ? x.toDouble() : (x.numerator as int) / (x.denominator as int);
      if (a.isFinite && a > 0) acc = math.max(3, a);
    }
    return (LatLng(lat, lng), acc);
  } catch (_) {
    return null;
  }
}

/// צירוף תמונת קבר. מחזיר true אם נשמר גם מיקום הקבר.
/// [ref] – המיקום הידוע/המשוער של הקבר, [me]/[meAcc] – המיקום הנוכחי בטלפון (לצילום במצלמה).
Future<bool> attachPhoto(BuildContext context, Deceased d, LatLng? ref, LatLng? me, double? meAcc) async {
  final t = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final src = await showModalBottomSheet<ImageSource>(
    context: context,
    showDragHandle: true,
    builder: (c) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text(t.attachPhotoSub, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        ),
        ListTile(
            leading: const Icon(Icons.photo_camera_outlined),
            title: Text(t.camera),
            onTap: () => Navigator.pop(c, ImageSource.camera)),
        ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: Text(t.gallery),
            onTap: () => Navigator.pop(c, ImageSource.gallery)),
      ]),
    ),
  );
  if (src == null) return false;
  // מצלמה: המיקום הנוכחי ברגע הצילום
  final camPos = src == ImageSource.camera ? me : null, camAcc = meAcc;
  final XFile? f;
  try {
    // הקטנה ל-2400 פיקסלים – נתוני המיקום נשמרים בקובץ
    f = await ImagePicker().pickImage(source: src, maxWidth: 2400, maxHeight: 2400, imageQuality: 88);
  } catch (_) {
    messenger.showSnackBar(SnackBar(content: Text(t.uploadFailed)));
    return false;
  }
  if (f == null) return false;
  messenger.showSnackBar(SnackBar(content: Text(t.uploading), duration: const Duration(seconds: 20)));
  try {
    final bytes = await f.readAsBytes();
    var gps = await photoGps(bytes);
    if (gps == null && camPos != null && camAcc != null) gps = (camPos, camAcc);
    final path = 'pending/${d.id}/${_rand()}.jpg';
    await db.storage.from('grave-photos').uploadBinary(path, bytes);
    await db.from('grave_photos').insert({'deceased_id': d.id, 'path': path});
    var msg = t.photoThanks, locSaved = false;
    if (gps != null && ref != null && meters(ref, gps.$1) < 150 && gps.$2 <= 15) {
      locSaved = await Repo.saveGraveLocation(d.id, gps.$1.latitude, gps.$1.longitude, gps.$2);
      if (locSaved) msg += t.photoLocSaved;
    }
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
    return locSaved;
  } catch (_) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(t.uploadFailed)));
    return false;
  }
}

/// תמונות מאושרות של הקבר
Future<List<String>> approvedPhotos(int id) async {
  try {
    final r = await db.from('grave_photos').select('path').eq('deceased_id', id).eq('status', 'approved').order('created_at');
    return [for (final p in r as List) db.storage.from('grave-photos').getPublicUrl(p['path'])];
  } catch (_) {
    return [];
  }
}

/// דיווח על טעות או נזק
Future<void> reportDialog(BuildContext context, Deceased d) async {
  final t = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final msg = TextEditingController(), contact = TextEditingController();
  var kind = 'error';
  var busy = false;
  await showDialog(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, set) => AlertDialog(
        title: Text(t.report),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(d.fullName, style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final (k, label) in [('error', t.reportKindError), ('damage', t.reportKindDamage), ('other', t.reportKindOther)])
                ChoiceChip(label: Text(label), selected: kind == k, onSelected: (_) => set(() => kind = k)),
            ]),
            const SizedBox(height: 10),
            TextField(
              controller: msg,
              maxLines: 4,
              maxLength: 1000,
              decoration: InputDecoration(hintText: t.reportHint, border: const OutlineInputBorder()),
            ),
            TextField(
              controller: contact,
              maxLength: 100,
              decoration: InputDecoration(hintText: t.reportContact, border: const OutlineInputBorder()),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: Text(t.cancel)),
          FilledButton(
            onPressed: busy
                ? null
                : () async {
                    final m = msg.text.trim();
                    if (m.length < 3) {
                      messenger.showSnackBar(SnackBar(content: Text(t.reportShort)));
                      return;
                    }
                    set(() => busy = true);
                    try {
                      await db.from('reports').insert({
                        'cemetery_id': d.cemeteryId,
                        'deceased_id': d.id,
                        'kind': kind,
                        'message': m,
                        'contact': contact.text.trim().isEmpty ? null : contact.text.trim(),
                      });
                      if (c.mounted) Navigator.pop(c);
                      messenger.showSnackBar(SnackBar(content: Text(t.reportThanks)));
                    } catch (_) {
                      set(() => busy = false);
                      messenger.showSnackBar(SnackBar(content: Text(t.uploadFailed)));
                    }
                  },
            child: Text(t.send),
          ),
        ],
      ),
    ),
  );
}

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data.dart';
import '../geo.dart';
import '../hebcal.dart';
import '../l10n/app_localizations.dart';
import '../offline.dart';
import '../reminders.dart';
import 'actions.dart';
import 'search.dart';

const graveRed = Color(0xFFDC1E1E);
const plotGold = Color(0xFFE0A83A);

class DetailScreen extends StatefulWidget {
  final Deceased deceased;
  final Cemetery cemetery;
  const DetailScreen({super.key, required this.deceased, required this.cemetery});
  @override
  State<DetailScreen> createState() => _DetailScreenState();
}

class _DetailScreenState extends State<DetailScreen> {
  final _map = MapController();
  List<Plot> _plots = [];
  List<LatLng>? _targetRing;
  LatLng? _est, _grave, _me;
  double? _heading, _meAcc;
  List<String> _photos = [];
  File? _overlayFile;
  bool _remind = false;
  bool _locDenied = false, _asked = true, _saving = false;
  String? _saveCountdown;
  StreamSubscription<Position>? _posSub;
  StreamSubscription<CompassEvent>? _compSub;

  Deceased get d => widget.deceased;
  Cemetery get cem => widget.cemetery;

  @override
  void initState() {
    super.initState();
    _load();
    _startLocation();
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _compSub?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    _asked = prefs.getBool('asked:${d.id}') ?? false;
    Offline.overlay(cem.id).then((f) {
      if (f != null && mounted) setState(() => _overlayFile = f);
    });
    Reminders.isOn(d.id).then((v) {
      if (mounted) setState(() => _remind = v);
    });
    approvedPhotos(d.id).then((p) {
      if (mounted) setState(() => _photos = p);
    });
    try {
      final plots = await Repo.plots(cem.id);
      final t = plots.where((p) => p.plot == d.plot && p.gush == (d.gush ?? '1') && p.ring != null).firstOrNull;
      setState(() {
        _plots = plots;
        _targetRing = t?.ring;
      });
      if (t?.ring != null) {
        _map.fitCamera(CameraFit.bounds(
            bounds: LatLngBounds.fromPoints(t!.ring!), padding: const EdgeInsets.all(60), maxZoom: 19));
        final row = int.tryParse(d.row ?? ''), grave = int.tryParse(d.grave ?? '');
        if (row != null && grave != null) {
          final size = await Repo.plotSize(d);
          if (size != null) setState(() => _est = estimateGrave(t.ring!, row, grave, size.$1, size.$2));
        }
      } else if (cem.center != null) {
        _map.move(cem.center!, 17);
      }
      final g = await Repo.graveLocation(d.id);
      if (g != null) {
        setState(() => _grave = g);
        _map.move(g, 19);
      }
    } catch (_) {}
  }

  Future<void> _startLocation() async {
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
    if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
      setState(() => _locDenied = true);
      return;
    }
    _posSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.best, distanceFilter: 1),
    ).listen((p) => setState(() {
          _me = LatLng(p.latitude, p.longitude);
          _meAcc = p.accuracy;
        }));
    _compSub = FlutterCompass.events?.listen((e) {
      if (e.heading != null) setState(() => _heading = e.heading);
    });
  }

  LatLng? get _target => _grave ?? _est ?? (_targetRing == null ? null : centroid(_targetRing!));

  String _dir(AppLocalizations t, double br) =>
      [t.dirN, t.dirNE, t.dirE, t.dirSE, t.dirS, t.dirSW, t.dirW, t.dirNW][(br / 45).round() % 8];

  /// (טקסט, הגענו?, כיוון החץ)
  (String, bool, double?) _nav(AppLocalizations t) {
    final tgt = _target;
    if (tgt == null) return (d.plot == null ? t.noGraveLoc : t.plotNotMapped(d.plot!), false, null);
    if (_locDenied) return (t.locDenied, false, null);
    if (_me == null) return (t.locating, false, null);
    final m = meters(_me!, tgt), br = bearing(_me!, tgt);
    final look = (d.row != null && d.grave != null) ? t.lookFor(d.row!, d.grave!) : '';
    if (_grave != null && m <= 5) return (t.arrivedGrave, true, null);
    if (_grave == null && _est != null && m <= 8) return (t.arrivedEst + look, true, null);
    if (_grave == null && _est == null && _targetRing != null && inPolygon(_me!, _targetRing!)) {
      return (t.arrivedPlot(d.plot!) + look, true, null);
    }
    if (m > 2000) return (t.farAway((m / 1000).toStringAsFixed(1)), false, br);
    final dest = _grave != null ? t.theGrave : (_est != null ? t.theGraveEst : t.plotN(d.plot!));
    return (t.metersTo(m.round(), _dir(t, br), dest) + (_heading == null ? t.northNote : ''), false, br);
  }

  Future<void> _saveLocation() async {
    final t = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _saving = true);
    final fixes = <Position>[];
    final sub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.best, distanceFilter: 0),
    ).listen(fixes.add);
    for (var s = 8; s > 0; s--) {
      setState(() => _saveCountdown = t.standStill(s));
      await Future.delayed(const Duration(seconds: 1));
    }
    await sub.cancel();
    setState(() {
      _saving = false;
      _saveCountdown = null;
    });
    if (fixes.isEmpty) return;
    final best = fixes.map((p) => p.accuracy).reduce(math.min);
    if (best > 15) {
      messenger.showSnackBar(SnackBar(content: Text(t.lowAccuracy(best.round()))));
      return;
    }
    final good = fixes.where((p) => p.accuracy <= best * 1.5).toList();
    final lat = good.map((p) => p.latitude).reduce((a, b) => a + b) / good.length;
    final lng = good.map((p) => p.longitude).reduce((a, b) => a + b) / good.length;
    final ok = await Repo.saveGraveLocation(d.id, lat, lng, best);
    if (!ok) {
      messenger.showSnackBar(SnackBar(content: Text(t.saveFailed)));
      return;
    }
    (await SharedPreferences.getInstance()).setBool('asked:${d.id}', true);
    final g = await Repo.graveLocation(d.id);
    setState(() {
      _asked = true;
      _grave = g ?? LatLng(lat, lng);
    });
    messenger.showSnackBar(SnackBar(content: Text(t.locSaved)));
  }

  Future<void> _notNow() async {
    (await SharedPreferences.getInstance()).setBool('asked:${d.id}', true);
    setState(() => _asked = true);
  }

  Future<void> _photo() async {
    final saved = await attachPhoto(context, d, _target, _me, _meAcc);
    if (saved) {
      final g = await Repo.graveLocation(d.id);
      if (g != null && mounted) setState(() => _grave = g);
    }
  }

  Future<void> _toggleRemind() async {
    final t = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final v = await Reminders.toggle(d);
    if (!mounted) return;
    if (v == null) {
      messenger.showSnackBar(SnackBar(content: Text(t.remindNoPerm)));
      return;
    }
    setState(() => _remind = v);
    messenger.showSnackBar(SnackBar(content: Text(v ? t.remindOn : t.remindOff)));
  }

  void _drive() {
    final c = cem.center;
    if (c == null) return;
    launchUrl(Uri.parse('https://waze.com/ul?ll=${c.latitude},${c.longitude}&navigate=yes'),
        mode: LaunchMode.externalApplication);
  }

  void _share() {
    final t = AppLocalizations.of(context);
    Share.share('${d.fullName} – ${locLine(t, d)}, ${cem.name}\n${d.shareUrl}');
  }

  void _tefilon() {
    final q = Uri(queryParameters: {
      'n': d.firstName ?? '',
      'p': d.mother ?? d.father ?? '',
      't': (d.mother ?? '').isNotEmpty ? 'm' : 'f',
    }).query;
    launchUrl(Uri.parse('$webBase/tefilon/?$q'), mode: LaunchMode.inAppBrowserView);
  }

  void _ashkava() {
    final q = Uri(queryParameters: {'n': d.firstName ?? '', 'p': d.father ?? d.mother ?? ''}).query;
    launchUrl(Uri.parse('$webBase/ashkava/?$q'), mode: LaunchMode.inAppBrowserView);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final nav = _nav(t);
    final arrow = nav.$3 == null ? null : (nav.$3! - (_heading ?? 0)) * math.pi / 180;
    final yz = d.death == null ? null : HebCal.nextYahrzeits(d.death!, count: 1).firstOrNull;
    final dows = [t.dow0, t.dow1, t.dow2, t.dow3, t.dow4, t.dow5, t.dow6];
    final corners = cem.overlayCorners;

    return Scaffold(
      body: Column(children: [
        Expanded(
          child: Stack(children: [
            FlutterMap(
              mapController: _map,
              options: MapOptions(initialCenter: cem.center ?? const LatLng(31.3152, 34.6103), initialZoom: 17, maxZoom: 21),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  maxNativeZoom: 19,
                  maxZoom: 21,
                  userAgentPackageName: 'ltd.bulu.gravemarker',
                ),
                if (cem.overlayUrl != null && corners != null && corners.length == 3)
                  OverlayImageLayer(overlayImages: [
                    RotatedOverlayImage(
                      topLeftCorner: corners[0],
                      bottomLeftCorner: corners[2],
                      bottomRightCorner: LatLng(corners[1].latitude + corners[2].latitude - corners[0].latitude,
                          corners[1].longitude + corners[2].longitude - corners[0].longitude),
                      imageProvider: _overlayFile != null ? FileImage(_overlayFile!) : NetworkImage(cem.overlayUrl!) as ImageProvider,
                    ),
                  ]),
                PolygonLayer(polygons: [
                  for (final p in _plots.where((p) => p.ring != null))
                    Polygon(
                      points: p.ring!,
                      color: (identical(p.ring, _targetRing) ? plotGold : Colors.white)
                          .withValues(alpha: identical(p.ring, _targetRing) ? 0.25 : 0.05),
                      borderColor: identical(p.ring, _targetRing) ? plotGold : Colors.white70,
                      borderStrokeWidth: identical(p.ring, _targetRing) ? 4 : 1,
                      label: p.plot,
                      labelStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13, shadows: [
                        Shadow(blurRadius: 3, color: Colors.black),
                        Shadow(blurRadius: 3, color: Colors.black),
                      ]),
                    ),
                ]),
                if (_me != null && _target != null)
                  PolylineLayer(polylines: [
                    Polyline(points: [_me!, _target!], color: const Color(0xFF1F8FFF), strokeWidth: 3),
                  ]),
                CircleLayer(circles: [
                  if (_grave != null)
                    CircleMarker(point: _grave!, radius: 9, color: graveRed, borderColor: Colors.white, borderStrokeWidth: 3)
                  else if (_est != null) ...[
                    CircleMarker(point: _est!, radius: 10, color: Colors.transparent, borderColor: Colors.white, borderStrokeWidth: 6),
                    CircleMarker(point: _est!, radius: 10, color: Colors.transparent, borderColor: graveRed, borderStrokeWidth: 3),
                  ],
                  if (_me != null)
                    CircleMarker(point: _me!, radius: 8, color: const Color(0xFF1F8FFF), borderColor: Colors.white, borderStrokeWidth: 3),
                ]),
                const RichAttributionWidget(
                  attributions: [TextSourceAttribution('OpenStreetMap contributors')],
                ),
              ],
            ),
            PositionedDirectional(
              top: MediaQuery.of(context).padding.top + 10,
              start: 10,
              child: FloatingActionButton.small(
                heroTag: 'back',
                onPressed: () => Navigator.of(context).pop(),
                child: const BackButtonIcon(),
              ),
            ),
          ]),
        ),
        ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.58),
          child: Material(
            color: Theme.of(context).cardTheme.color,
            elevation: 8,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
            child: SafeArea(
              top: false,
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Text(d.fullName + ((d.altName ?? '').isNotEmpty ? ' (${d.altName})' : ''),
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 2),
                  Text(subLine(t, d), style: TextStyle(color: cs.onSurfaceVariant)),
                  const SizedBox(height: 10),
                  Row(children: [
                    for (final (label, val) in [(t.plot, d.plot), (t.row, d.row), (t.grave, d.grave)])
                      Expanded(
                        child: Container(
                          margin: const EdgeInsetsDirectional.only(end: 6),
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(color: cs.primaryContainer, borderRadius: BorderRadius.circular(12)),
                          child: Column(children: [
                            Text(label, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
                            Text(val ?? '—',
                                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: cs.onPrimaryContainer)),
                          ]),
                        ),
                      ),
                  ]),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(12)),
                    child: Row(children: [
                      CircleAvatar(
                        radius: 17,
                        backgroundColor: cs.primary,
                        child: nav.$2
                            ? const Icon(Icons.check, color: Colors.white)
                            : arrow == null
                                ? const Icon(Icons.place, color: Colors.white, size: 18)
                                : Transform.rotate(angle: arrow, child: const Icon(Icons.arrow_upward, color: Colors.white)),
                      ),
                      const SizedBox(width: 10),
                      Expanded(child: Text(nav.$1)),
                    ]),
                  ),
                  if (nav.$2 && !_asked) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: cs.primaryContainer, borderRadius: BorderRadius.circular(12)),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        Text(t.askLocTitle, style: const TextStyle(fontWeight: FontWeight.bold)),
                        Text(t.askLocBody),
                        const SizedBox(height: 8),
                        Row(children: [
                          Expanded(
                              child: FilledButton(
                                  onPressed: _saving ? null : _saveLocation, child: Text(_saveCountdown ?? t.saveLoc))),
                          const SizedBox(width: 8),
                          Expanded(child: OutlinedButton(onPressed: _saving ? null : _notNow, child: Text(t.notNow))),
                        ]),
                      ]),
                    ),
                  ],
                  if (yz != null) ...[
                    const SizedBox(height: 8),
                    Text(t.nextYahrzeit, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
                    Text(HebCal.format(yz.heb), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    Text(t.startsEve(dows[yz.date.weekday % 7], dmy(yz.date)),
                        style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
                    const SizedBox(height: 6),
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: _remind
                          ? FilledButton.tonalIcon(
                              onPressed: _toggleRemind,
                              icon: const Icon(Icons.notifications_active),
                              label: Text(t.remindIsOn))
                          : OutlinedButton.icon(
                              onPressed: _toggleRemind,
                              icon: const Icon(Icons.notifications_none),
                              label: Text(t.remindSet)),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(child: FilledButton(onPressed: _drive, child: Text(t.drive))),
                    const SizedBox(width: 8),
                    Expanded(child: FilledButton.tonal(onPressed: _share, child: Text(t.share))),
                  ]),
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(child: FilledButton.tonal(onPressed: _tefilon, child: Text(t.tefilon))),
                    const SizedBox(width: 8),
                    Expanded(child: FilledButton.tonal(onPressed: _ashkava, child: Text(t.ashkava))),
                  ]),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _photo,
                    icon: const Icon(Icons.add_a_photo_outlined),
                    label: Text(t.attachPhoto),
                  ),
                  if (_photos.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 96,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: _photos.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 6),
                        itemBuilder: (c, i) => GestureDetector(
                          onTap: () => launchUrl(Uri.parse(_photos[i]), mode: LaunchMode.externalApplication),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: Image.network(_photos[i], width: 96, height: 96, fit: BoxFit.cover),
                          ),
                        ),
                      ),
                    ),
                  ],
                  Center(
                    child: TextButton(
                      onPressed: () => reportDialog(context, d),
                      child: Text(t.report, style: TextStyle(color: cs.onSurfaceVariant)),
                    ),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

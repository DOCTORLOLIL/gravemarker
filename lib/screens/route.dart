import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data.dart';
import '../l10n/app_localizations.dart';
import '../routes.dart';
import 'actions.dart';
import 'detail.dart';

/// מסך הביקור המשפחתי
class RouteScreen extends StatefulWidget {
  final VisitRoute route;
  const RouteScreen({super.key, required this.route});
  @override
  State<RouteScreen> createState() => _RouteScreenState();
}

class _RouteScreenState extends State<RouteScreen> {
  VisitRoute get r => widget.route;
  Cemetery? _cem;
  final Map<int, Deceased> _d = {};
  final Map<int, LatLng?> _pos = {};
  final Map<int, String?> _thumb = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      _cem = (await Repo.cemeteries()).where((c) => c.id == r.cem).firstOrNull;
      final plots = await Repo.plots(r.cem);
      await Future.wait(r.ids.map((id) async {
        final d = await Repo.deceased(id);
        if (d == null) return;
        _d[id] = d;
        _pos[id] = await gravePosition(d, plots);
      }));
      r.ids.removeWhere((id) => !_d.containsKey(id));
      // סדר הליכה קצר, עד שהמשתמש משנה את הסדר בעצמו
      if (!r.manual && r.ids.length > 1) {
        LatLng? start;
        try {
          final p = await Geolocator.getLastKnownPosition();
          if (p != null) start = LatLng(p.latitude, p.longitude);
        } catch (_) {}
        if (start == null || _cem?.center == null || _distance(start, _cem!.center!) > 1500) start = _cem?.center;
        r.ids = shortestOrder(r.ids, _pos, start);
      }
      await RouteStore.put(r);
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
    for (final id in r.ids) {
      approvedPhotos(id).then((p) {
        if (mounted) setState(() => _thumb[id] = p.firstOrNull);
      });
    }
  }

  double _distance(LatLng a, LatLng b) => const Distance().as(LengthUnit.Meter, a, b);

  Future<void> _save({bool rename = false}) async {
    final t = AppLocalizations.of(context);
    final cem = _cem;
    if (cem == null) return;
    final suggested = r.name.isNotEmpty ? r.name : await suggestName(t, [for (final id in r.ids) _d[id]!], cem);
    if (!mounted) return;
    final c = TextEditingController(text: suggested);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(rename ? t.routeName : t.routeSave),
        content: TextField(controller: c, autofocus: true, decoration: InputDecoration(labelText: t.routeName)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t.cancel)),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: Text(t.save)),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    setState(() {
      r.name = name;
      r.saved = true;
    });
    await RouteStore.put(r);
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t.routeSaved)));
  }

  Future<void> _changed() => RouteStore.put(r);

  Future<void> _next() async {
    final cem = _cem;
    if (cem == null) return;
    final id = r.ids.where((i) => !r.done.contains(i)).firstOrNull;
    if (id == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AppLocalizations.of(context).routeAllDone)));
      return;
    }
    final res = await Navigator.of(context).push<String>(
        MaterialPageRoute(builder: (_) => DetailScreen(deceased: _d[id]!, cemetery: cem, inRoute: true)));
    if (res == 'next' || res == 'done') {
      setState(() => r.done.add(id));
      await _changed();
      approvedPhotos(id).then((p) {
        if (mounted) setState(() => _thumb[id] = p.firstOrNull);
      });
      if (res == 'next' && mounted) _next();
    }
  }

  void _share() {
    final t = AppLocalizations.of(context);
    final text = '${t.routeShareText(_cem?.name ?? '', r.name.isEmpty ? t.routeTitle : r.name)}\n'
        '${[for (final id in r.ids) '• ${_d[id]?.fullName ?? ''}'].join('\n')}\n${r.shareUrl}';
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.chat, color: Color(0xFF25D366)),
            title: Text(t.whatsapp),
            onTap: () {
              Navigator.pop(c);
              launchUrl(Uri.parse('https://wa.me/?text=${Uri.encodeComponent(text)}'), mode: LaunchMode.externalApplication);
            },
          ),
          ListTile(
            leading: const Icon(Icons.mail_outline),
            title: Text(t.routeEmail),
            onTap: () {
              Navigator.pop(c);
              launchUrl(Uri.parse('mailto:?subject=${Uri.encodeComponent(r.name.isEmpty ? t.routeTitle : r.name)}'
                  '&body=${Uri.encodeComponent(text)}'));
            },
          ),
          ListTile(
            leading: const Icon(Icons.share_outlined),
            title: Text(t.routeOther),
            onTap: () {
              Navigator.pop(c);
              Share.share(text);
            },
          ),
        ]),
      ),
    );
  }

  void _map() {
    final pts = [for (final id in r.ids) if (_pos[id] != null) (r.ids.indexOf(id) + 1, _pos[id]!, r.done.contains(id))];
    if (pts.isEmpty) return;
    showDialog(
      context: context,
      builder: (c) => Dialog(
        insetPadding: const EdgeInsets.all(12),
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          height: MediaQuery.of(c).size.height * 0.7,
          child: FlutterMap(
            options: MapOptions(
              initialCameraFit: pts.length > 1
                  ? CameraFit.bounds(bounds: LatLngBounds.fromPoints([for (final p in pts) p.$2]), padding: const EdgeInsets.all(40))
                  : null,
              initialCenter: pts.first.$2,
              initialZoom: 18,
              maxZoom: 21,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                maxNativeZoom: 19,
                maxZoom: 21,
                userAgentPackageName: 'ltd.bulu.gravemarker',
              ),
              PolylineLayer(polylines: [
                Polyline(points: [for (final p in pts) p.$2], color: const Color(0xFF1F8FFF), strokeWidth: 3),
              ]),
              MarkerLayer(markers: [
                for (final p in pts)
                  Marker(
                    point: p.$2,
                    width: 28,
                    height: 28,
                    child: CircleAvatar(
                      backgroundColor: p.$3 ? Colors.green.shade700 : graveRed,
                      child: Text('${p.$1}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                    ),
                  ),
              ]),
              const SimpleAttributionWidget(source: Text('OpenStreetMap')),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _menu(String v) async {
    final t = AppLocalizations.of(context);
    if (v == 'rename') return _save(rename: true);
    if (v == 'reset') {
      setState(() => r.done.clear());
      return _changed();
    }
    if (v == 'delete') {
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(t.routeDelete),
          content: Text(t.routeDeleteQ(r.name.isEmpty ? t.routeTitle : r.name)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: Text(t.cancel)),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(t.delete)),
          ],
        ),
      );
      if (ok == true) {
        await RouteStore.remove(r.id);
        if (mounted) Navigator.of(context).pop();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final len = roundMeters(routeLength(r.ids, _pos));
    return Scaffold(
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(r.name.isEmpty ? t.routeTitle : r.name, overflow: TextOverflow.ellipsis),
          if (!_loading && r.ids.isNotEmpty)
            Text(t.routeStats('${r.ids.length}', '$len'), style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
        ]),
        actions: [
          PopupMenuButton<String>(
            onSelected: _menu,
            itemBuilder: (_) => [
              PopupMenuItem(value: 'rename', child: Text(t.routeName)),
              PopupMenuItem(value: 'reset', child: Text(t.routeReset)),
              PopupMenuItem(value: 'delete', child: Text(t.routeDelete)),
            ],
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : r.ids.isEmpty
              ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(t.routeEmpty, textAlign: TextAlign.center)))
              : Column(children: [
                  if (!r.saved)
                    Card(
                      margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                      color: const Color(0xFFE0A83A),
                      child: ListTile(
                        leading: const Icon(Icons.bookmark_add_outlined, color: Color(0xFF2B1E00)),
                        title: Text(t.routeSaveHint, style: const TextStyle(color: Color(0xFF2B1E00), fontSize: 14)),
                        trailing: FilledButton(
                          style: FilledButton.styleFrom(backgroundColor: const Color(0xFF2B1E00)),
                          onPressed: _save,
                          child: Text(t.save),
                        ),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: Text(t.routeDrag, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
                  ),
                  Expanded(
                    child: ReorderableListView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
                      itemCount: r.ids.length,
                      onReorder: (a, b) {
                        setState(() {
                          if (b > a) b--;
                          r.ids.insert(b, r.ids.removeAt(a));
                          r.manual = true;
                        });
                        _changed();
                      },
                      itemBuilder: (c, i) {
                        final id = r.ids[i];
                        final d = _d[id]!;
                        final done = r.done.contains(id);
                        final nextId = r.ids.where((x) => !r.done.contains(x)).firstOrNull;
                        final prev = i > 0 ? _pos[r.ids[i - 1]] : null;
                        final dist = prev != null && _pos[id] != null ? roundMeters(_distance(prev, _pos[id]!)) : null;
                        return Dismissible(
                          key: ValueKey(id),
                          direction: DismissDirection.endToStart,
                          background: Container(
                            alignment: AlignmentDirectional.centerEnd,
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            color: Colors.red.shade700,
                            child: const Icon(Icons.delete_outline, color: Colors.white),
                          ),
                          onDismissed: (_) {
                            setState(() {
                              r.ids.remove(id);
                              r.done.remove(id);
                            });
                            _changed();
                          },
                          child: Card(
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            shape: id == nextId
                                ? RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12), side: BorderSide(color: cs.primary, width: 2))
                                : null,
                            child: ListTile(
                              contentPadding: const EdgeInsetsDirectional.only(start: 8, end: 4),
                              leading: Row(mainAxisSize: MainAxisSize.min, children: [
                                CircleAvatar(
                                  radius: 13,
                                  backgroundColor: done ? Colors.green.shade700 : graveRed,
                                  child: Text('${i + 1}',
                                      style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                                ),
                                const SizedBox(width: 8),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: SizedBox(
                                    width: 48,
                                    height: 48,
                                    child: _thumb[id] != null
                                        ? Image.network(_thumb[id]!, fit: BoxFit.cover,
                                            errorBuilder: (_, __, ___) => const Icon(Icons.image_not_supported_outlined))
                                        : Container(
                                            color: cs.surfaceContainerHighest,
                                            child: Icon(Icons.photo_camera_outlined, color: cs.onSurfaceVariant)),
                                  ),
                                ),
                              ]),
                              title: Text(d.fullName, style: const TextStyle(fontWeight: FontWeight.bold)),
                              subtitle: Text([
                                if (d.plot != null) '${t.plot} ${d.plot}',
                                if (dist != null) t.routeFromPrev('$dist'),
                              ].join(' · ')),
                              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                                if (done) Icon(Icons.check_circle, color: Colors.green.shade700),
                                ReorderableDragStartListener(
                                  index: i,
                                  child: const Padding(padding: EdgeInsets.all(8), child: Icon(Icons.drag_handle)),
                                ),
                              ]),
                              onTap: () async {
                                final cem = _cem;
                                if (cem == null) return;
                                final res = await Navigator.of(context).push<String>(MaterialPageRoute(
                                    builder: (_) => DetailScreen(deceased: d, cemetery: cem, inRoute: true)));
                                if (res == 'next' || res == 'done') {
                                  setState(() => r.done.add(id));
                                  await _changed();
                                  if (res == 'next' && mounted) _next();
                                }
                              },
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        FilledButton.icon(
                          style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                          onPressed: _next,
                          icon: const Icon(Icons.play_arrow),
                          label: Text(t.routeNext, style: const TextStyle(fontSize: 16)),
                        ),
                        const SizedBox(height: 8),
                        Row(children: [
                          Expanded(
                              child: OutlinedButton.icon(
                                  onPressed: _share, icon: const Icon(Icons.share_outlined), label: Text(t.routeShare))),
                          const SizedBox(width: 8),
                          Expanded(
                              child: OutlinedButton.icon(onPressed: _map, icon: const Icon(Icons.map_outlined), label: Text(t.routeMap))),
                        ]),
                      ]),
                    ),
                  ),
                ]),
    );
  }
}

/// המסלולים השמורים
class MyRoutesScreen extends StatefulWidget {
  const MyRoutesScreen({super.key});
  @override
  State<MyRoutesScreen> createState() => _MyRoutesScreenState();
}

class _MyRoutesScreenState extends State<MyRoutesScreen> {
  List<VisitRoute>? _list;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final l = (await RouteStore.all()).where((r) => r.ids.isNotEmpty).toList().reversed.toList();
    if (mounted) setState(() => _list = l);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(t.myRoutes)),
      body: _list == null
          ? const Center(child: CircularProgressIndicator())
          : _list!.isEmpty
              ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(t.routeEmpty, textAlign: TextAlign.center)))
              : ListView(padding: const EdgeInsets.all(12), children: [
                  for (final r in _list!)
                    Card(
                      child: ListTile(
                        leading: Icon(r.saved ? Icons.route : Icons.route_outlined, color: cs.primary),
                        title: Text(r.name.isEmpty ? t.routeTitle : r.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text('${t.routeCount('${r.ids.length}')}${r.saved ? '' : ' · ${t.routeNotSaved}'}'),
                        trailing: Icon(Icons.adaptive.arrow_forward),
                        onTap: () async {
                          await RouteStore.setActive(r);
                          if (!context.mounted) return;
                          await Navigator.of(context).push(MaterialPageRoute(builder: (_) => RouteScreen(route: r)));
                          _reload();
                        },
                      ),
                    ),
                ]),
    );
  }
}

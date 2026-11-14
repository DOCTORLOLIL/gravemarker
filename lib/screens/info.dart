import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data.dart';
import '../l10n/app_localizations.dart';
import '../places.dart';
import '../routes.dart';

/// מידע שימושי: שעות פתיחה ונקודות בבית העלמין
class InfoScreen extends StatefulWidget {
  final Cemetery cemetery;
  const InfoScreen({super.key, required this.cemetery});
  @override
  State<InfoScreen> createState() => _InfoScreenState();
}

class _InfoScreenState extends State<InfoScreen> {
  List<Place>? _places;
  String? _hours;
  LatLng? _me;

  @override
  void initState() {
    super.initState();
    Places.of(widget.cemetery.id).then((p) {
      if (mounted) setState(() => _places = p);
    });
    Places.hours(widget.cemetery.id).then((h) {
      if (mounted) setState(() => _hours = h);
    });
    Geolocator.getLastKnownPosition().then((p) {
      if (p != null && mounted) setState(() => _me = LatLng(p.latitude, p.longitude));
    }).catchError((_) {});
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final list = [...?_places];
    if (_me != null) {
      list.sort((a, b) => const Distance()
          .as(LengthUnit.Meter, _me!, a.pos)
          .compareTo(const Distance().as(LengthUnit.Meter, _me!, b.pos)));
    } else {
      const order = ['entrance', 'parking', 'wash', 'tap', 'wc', 'office', 'shade'];
      list.sort((a, b) => order.indexOf(a.kind).compareTo(order.indexOf(b.kind)));
    }
    final near = _me != null && widget.cemetery.center != null &&
        const Distance().as(LengthUnit.Meter, _me!, widget.cemetery.center!) < 2000;
    return Scaffold(
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(t.infoTitle),
          Text(widget.cemetery.name, style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
        ]),
      ),
      body: _places == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(padding: const EdgeInsets.all(12), children: [
              if ((_hours ?? '').isNotEmpty)
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.schedule),
                    title: Text(t.hours, style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text(_hours!),
                  ),
                ),
              if (list.isEmpty)
                Padding(padding: const EdgeInsets.all(24), child: Text(t.noPlaces, textAlign: TextAlign.center)),
              for (final p in list)
                Card(
                  child: ListTile(
                    leading: Text(p.icon, style: const TextStyle(fontSize: 26)),
                    title: Text(p.label(t), style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text([
                      if (near) t.metersFromYou('${roundMeters(const Distance().as(LengthUnit.Meter, _me!, p.pos))}'),
                      if ((p.note ?? '').isNotEmpty) p.note!,
                    ].join(' · ')),
                    trailing: TextButton(
                      onPressed: () => launchUrl(
                          Uri.parse(
                              'https://www.google.com/maps/dir/?api=1&destination=${p.pos.latitude},${p.pos.longitude}&travelmode=walking'),
                          mode: LaunchMode.externalApplication),
                      child: Text(t.navigateShort),
                    ),
                  ),
                ),
            ]),
    );
  }
}

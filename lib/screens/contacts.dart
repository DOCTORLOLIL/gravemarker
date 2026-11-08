import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data.dart';
import '../l10n/app_localizations.dart';

class ContactsScreen extends StatefulWidget {
  final Cemetery cemetery;
  const ContactsScreen({super.key, required this.cemetery});
  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> {
  List<Map<String, dynamic>>? _rows;

  @override
  void initState() {
    super.initState();
    db
        .from('cemetery_contacts')
        .select()
        .eq('cemetery_id', widget.cemetery.id)
        .order('sort')
        .order('name')
        .then((r) => setState(() => _rows = List<Map<String, dynamic>>.from(r)))
        .catchError((_) => setState(() => _rows = []));
  }

  String? _wa(String? phone) {
    final d = (phone ?? '').replaceAll(RegExp(r'\D'), '');
    if (RegExp(r'^05\d{8}$').hasMatch(d)) return 'https://wa.me/972${d.substring(1)}';
    if (RegExp(r'^9725\d{8}$').hasMatch(d)) return 'https://wa.me/$d';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final groups = {'office': t.grpOffice, 'council': t.grpCouncil, 'maker': t.grpMaker, 'other': t.grpOther};
    return Scaffold(
      appBar: AppBar(title: Text(t.contacts)),
      body: _rows == null
          ? const Center(child: CircularProgressIndicator())
          : _rows!.isEmpty
              ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(t.noContacts)))
              : ListView(padding: const EdgeInsets.all(16), children: [
                  for (final g in groups.entries)
                    if (_rows!.any((c) => (c['category'] ?? 'other') == g.key)) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
                        child: Text(g.value, style: TextStyle(color: cs.onSurfaceVariant, fontWeight: FontWeight.bold)),
                      ),
                      for (final c in _rows!.where((c) => (c['category'] ?? 'other') == g.key))
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Row(children: [
                              Expanded(
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text(c['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                  if ((c['role'] ?? '').toString().isNotEmpty)
                                    Text(c['role'], style: TextStyle(color: cs.onSurfaceVariant)),
                                  if ((c['notes'] ?? '').toString().isNotEmpty)
                                    Text(c['notes'], style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
                                ]),
                              ),
                              if ((c['phone'] ?? '').toString().isNotEmpty)
                                FilledButton(
                                  onPressed: () => launchUrl(Uri.parse('tel:${c['phone'].toString().replaceAll(RegExp(r'[^\d+]'), '')}')),
                                  child: Text(t.call),
                                ),
                              if (_wa(c['phone']) != null) ...[
                                const SizedBox(width: 6),
                                FilledButton.tonal(
                                  onPressed: () => launchUrl(Uri.parse(_wa(c['phone'])!), mode: LaunchMode.externalApplication),
                                  child: Text(t.whatsapp),
                                ),
                              ],
                            ]),
                          ),
                        ),
                    ],
                ]),
    );
  }
}

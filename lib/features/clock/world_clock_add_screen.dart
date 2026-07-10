import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../core/theme/app_theme.dart';
import '../../core/time/time_format.dart';
import 'application/world_clock_providers.dart';
import 'domain/city_aliases.dart';
import 'domain/world_city.dart';

/// Searchable list of cities: every IANA zone city plus a table of major
/// cities that aren't zone names (San Antonio, Dallas, Mumbai, …).
class WorldClockAddScreen extends ConsumerStatefulWidget {
  const WorldClockAddScreen({super.key});

  @override
  ConsumerState<WorldClockAddScreen> createState() =>
      _WorldClockAddScreenState();
}

class _WorldClockAddScreenState extends ConsumerState<WorldClockAddScreen> {
  String _query = '';
  late final List<WorldCity> _all = _buildCatalogue();

  static List<WorldCity> _buildCatalogue() {
    final entries = <WorldCity>[
      for (final id in tz.timeZoneDatabase.locations.keys)
        if (id.contains('/') && !id.startsWith('Etc/'))
          WorldCity.fromZoneId(id),
      for (final e in kCityAliases.entries)
        WorldCity(name: e.key, tz: e.value),
    ];
    // Drop alias duplicates of real zone cities, then sort by name.
    final seen = <String>{};
    final unique = <WorldCity>[
      for (final c in entries)
        if (seen.add(c.name.toLowerCase())) c,
    ];
    unique.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return unique;
  }

  @override
  Widget build(BuildContext context) {
    final added = ref.watch(worldClockProvider).value ?? const <WorldCity>[];
    final addedKeys = {for (final c in added) '${c.name}|${c.tz}'};

    final q = _query.trim().toLowerCase();
    final results = q.isEmpty
        ? _all
        : [
            for (final c in _all)
              if (c.name.toLowerCase().contains(q) ||
                  c.region.toLowerCase().contains(q) ||
                  c.tz.toLowerCase().replaceAll('_', ' ').contains(q))
                c,
          ];

    return Scaffold(
      appBar: AppBar(title: const Text('Add city')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              autofocus: true,
              onChanged: (v) => setState(() => _query = v),
              decoration: InputDecoration(
                hintText: 'Search city or region…',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: Theme.of(context).colorScheme.surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: results.length,
              itemBuilder: (context, i) {
                final city = results[i];
                final already =
                    addedKeys.contains('${city.name}|${city.tz}');

                String time = '';
                try {
                  time = TimeFormat.clock(
                    tz.TZDateTime.now(tz.getLocation(city.tz)),
                  );
                } catch (_) {}

                return ListTile(
                  title: Text(city.name),
                  subtitle: Text(
                    city.region,
                    style: TextStyle(color: context.mutedColor, fontSize: 12.5),
                  ),
                  trailing: already
                      ? const Icon(Icons.check, size: 20)
                      : Text(
                          time,
                          style: const TextStyle(
                            fontSize: 15,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                  enabled: !already,
                  onTap: () async {
                    await ref.read(worldClockProvider.notifier).add(city);
                    if (context.mounted) Navigator.of(context).pop();
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

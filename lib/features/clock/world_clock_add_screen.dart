import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../core/theme/app_theme.dart';
import '../../core/time/time_format.dart';
import 'application/world_clock_providers.dart';

/// Searchable list of all IANA time zones to add to the world clock.
class WorldClockAddScreen extends ConsumerStatefulWidget {
  const WorldClockAddScreen({super.key});

  @override
  ConsumerState<WorldClockAddScreen> createState() =>
      _WorldClockAddScreenState();
}

class _WorldClockAddScreenState extends ConsumerState<WorldClockAddScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final added = ref.watch(worldClockProvider).value ?? const [];

    final all = tz.timeZoneDatabase.locations.keys
        .where((id) => id.contains('/') && !id.startsWith('Etc/'))
        .toList()
      ..sort();

    final q = _query.trim().toLowerCase().replaceAll(' ', '_');
    final results = q.isEmpty
        ? all
        : all.where((id) => id.toLowerCase().contains(q)).toList();

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
                final id = results[i];
                final city = id.split('/').last.replaceAll('_', ' ');
                final region = id
                    .substring(0, id.lastIndexOf('/'))
                    .replaceAll('_', ' ');
                final already = added.contains(id);

                String time = '';
                try {
                  time = TimeFormat.clock(tz.TZDateTime.now(tz.getLocation(id)));
                } catch (_) {}

                return ListTile(
                  title: Text(city),
                  subtitle: Text(
                    region,
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
                    await ref.read(worldClockProvider.notifier).add(id);
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

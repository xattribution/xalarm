/// A city on the world clock: a display name plus its IANA time zone.
/// The name can differ from the zone's own city (e.g. "San Antonio" →
/// America/Chicago).
class WorldCity {
  final String name;
  final String tz;
  const WorldCity({required this.name, required this.tz});

  Map<String, dynamic> toJson() => {'name': name, 'tz': tz};

  factory WorldCity.fromJson(Map<String, dynamic> json) =>
      WorldCity(name: json['name'] as String, tz: json['tz'] as String);

  /// Legacy entries were bare zone-id strings.
  factory WorldCity.fromZoneId(String zoneId) => WorldCity(
    name: zoneId.split('/').last.replaceAll('_', ' '),
    tz: zoneId,
  );

  String get region =>
      tz.contains('/') ? tz.substring(0, tz.lastIndexOf('/')).replaceAll('_', ' ') : '';
}

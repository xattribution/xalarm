import 'codes.dart';

/// The payload behind a session QR code / deep link:
/// `xalarm://sync?code=ABC234&server=wss%3A%2F%2Fhost%2Fsync`.
///
/// The server part is optional — a link without it joins via whatever relay
/// the scanning phone is configured for.
class SyncLink {
  final String code;
  final String? server;
  const SyncLink({required this.code, this.server});

  static const scheme = 'xalarm';
  static const host = 'sync';

  String encode() => Uri(
    scheme: scheme,
    host: host,
    queryParameters: {
      'code': code,
      if (server != null && server!.isNotEmpty) 'server': server!,
    },
  ).toString();

  /// Accepts a full link, or a bare code typed/pasted by hand. Returns null
  /// when nothing usable is found.
  static SyncLink? parse(String input) {
    final text = input.trim();
    if (text.isEmpty) return null;
    final bare = PairCodes.normalize(text);
    if (bare != null) return SyncLink(code: bare);

    final uri = Uri.tryParse(text);
    if (uri == null || uri.scheme != scheme || uri.host != host) return null;
    final code = PairCodes.normalize(uri.queryParameters['code'] ?? '');
    if (code == null) return null;
    final server = uri.queryParameters['server'];
    if (server != null) {
      final s = Uri.tryParse(server);
      if (s == null || !(s.isScheme('ws') || s.isScheme('wss'))) {
        return SyncLink(code: code);
      }
    }
    return SyncLink(code: code, server: server);
  }
}

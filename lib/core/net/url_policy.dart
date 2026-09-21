import 'dart:io';

/// Where the app is allowed to talk, and over what.
///
/// Encrypted transports are required for anything that could be on the
/// public internet. Cleartext (`http://`, `ws://`) is only accepted for
/// addresses that cannot leave the local network, so the update check, the
/// ringtone download, and the sync relay can't be quietly downgraded.
class UrlPolicy {
  const UrlPolicy._();

  /// Loopback, RFC 1918, link-local, CGNAT, and unique-local IPv6.
  static bool isPrivateAddress(InternetAddress a) {
    if (a.isLoopback || a.isLinkLocal) return true;
    final b = a.rawAddress;
    if (a.type == InternetAddressType.IPv4 && b.length == 4) {
      if (b[0] == 10) return true;
      if (b[0] == 172 && b[1] >= 16 && b[1] <= 31) return true;
      if (b[0] == 192 && b[1] == 168) return true;
      if (b[0] == 100 && b[1] >= 64 && b[1] <= 127) return true; // CGNAT
      return false;
    }
    if (a.type == InternetAddressType.IPv6 && b.length == 16) {
      if ((b[0] & 0xfe) == 0xfc) return true; // fc00::/7
      // IPv4-mapped ::ffff:a.b.c.d
      final mapped = b.sublist(0, 10).every((x) => x == 0) &&
          b[10] == 0xff &&
          b[11] == 0xff;
      if (mapped) {
        return isPrivateAddress(
          InternetAddress.fromRawAddress(b.sublist(12)),
        );
      }
    }
    return false;
  }

  /// True for hosts that only resolve on a LAN: literal private IPs,
  /// `localhost`, and mDNS `.local` names. Anything else is treated as
  /// public — DNS names are not resolved here on purpose.
  static bool isPrivateHost(String host) {
    final h = host.toLowerCase().replaceAll(RegExp(r'^\[|\]$'), '');
    if (h == 'localhost' || h.endsWith('.localhost')) return true;
    if (h.endsWith('.local')) return true;
    final ip = InternetAddress.tryParse(h);
    return ip != null && isPrivateAddress(ip);
  }

  /// Null when [url] is an acceptable `https://` URL (or `http://` to a
  /// private host); otherwise a short reason.
  static String? checkHttp(String url) =>
      _check(url, secure: 'https', clear: 'http');

  /// Same for WebSocket URLs (`wss://`, or `ws://` on the LAN).
  static String? checkWebSocket(String url) =>
      _check(url, secure: 'wss', clear: 'ws');

  static String? _check(
    String url, {
    required String secure,
    required String clear,
  }) {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || uri.host.isEmpty) return 'Enter a full URL.';
    if (uri.isScheme(secure)) return null;
    if (uri.isScheme(clear)) {
      return isPrivateHost(uri.host)
          ? null
          : 'Use $secure:// — $clear:// is only allowed for local addresses.';
    }
    return 'URL must start with $secure://';
  }
}

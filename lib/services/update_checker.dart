import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/build_info.dart';
import '../core/net/url_policy.dart';

/// Result of checking the self-hosted download site for a newer build.
class UpdateCheckResult {
  final bool updateAvailable;
  final String remoteCommit;
  final String remoteDate;
  final String apkUrl;
  const UpdateCheckResult({
    required this.updateAvailable,
    required this.remoteCommit,
    required this.remoteDate,
    required this.apkUrl,
  });
}

/// Compares the running build (baked in via --dart-define) against the
/// download site's version.json.
///
/// The update server must be HTTPS (cleartext only for LAN hosts), and the
/// APK name it advertises is restricted to a plain file name next to
/// version.json — the server can't point the app anywhere else.
class UpdateChecker {
  static final _apkName = RegExp(r'^[A-Za-z0-9._-]{1,64}\.apk$');

  Future<UpdateCheckResult> check(String baseUrl) async {
    final problem = UrlPolicy.checkHttp(baseUrl);
    if (problem != null) throw FormatException(problem);
    final base = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    final uri = Uri.parse('$base/version.json');

    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final req = await client.getUrl(uri);
      final res = await req.close();
      if (res.statusCode != 200) {
        throw HttpException('HTTP ${res.statusCode} from $uri');
      }
      if (res.contentLength > 64 * 1024) {
        throw const FormatException('version.json is unexpectedly large.');
      }
      final body = await utf8.decodeStream(res);
      final json = Map<String, dynamic>.from(jsonDecode(body) as Map);
      final remoteCommit = json['commit'] as String? ?? 'unknown';
      final remoteDate = json['date'] as String? ?? 'unknown';
      final file = json['file'] as String? ?? 'xalarm.apk';
      if (!_apkName.hasMatch(file)) {
        throw const FormatException('Update server sent a bad file name.');
      }

      return UpdateCheckResult(
        updateAvailable: _isNewer(remoteCommit, remoteDate),
        remoteCommit: remoteCommit,
        remoteDate: remoteDate,
        apkUrl: '$base/$file',
      );
    } finally {
      client.close();
    }
  }

  /// A remote build counts as newer when its commit differs from ours and
  /// its build date is later (commits don't order; dates do). Dev builds
  /// treat any dated remote build as an update.
  bool _isNewer(String remoteCommit, String remoteDate) {
    if (remoteCommit == BuildInfo.commit) return false;
    final remote = DateTime.tryParse(remoteDate);
    if (remote == null) return false;
    final local = DateTime.tryParse(BuildInfo.date);
    if (local == null) return true; // dev build — anything real is newer
    return remote.isAfter(local);
  }
}

final updateCheckerProvider = Provider<UpdateChecker>((ref) => UpdateChecker());

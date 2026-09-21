import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:recurrence_engine/recurrence_engine.dart';

import '../core/net/url_policy.dart';
import '../core/settings/settings_providers.dart';
import '../features/alarm/application/alarm_providers.dart';
import '../features/alarm/domain/alarm.dart';
import '../features/alarm/domain/recurrence_summary.dart';
import '../features/schedules/application/pattern_providers.dart';
import 'ringtone_library.dart';

/// Keeps the local-network REST API in sync with settings. Watch this once
/// from the app root; it starts/stops/restarts the server as settings change.
final haServerManagerProvider = Provider<void>((ref) {
  final server = ref.watch(_haServerProvider);
  final settings = ref.watch(settingsProvider).value;
  if (settings == null) return; // still loading
  server.ensure(
    enabled: settings.apiEnabled,
    port: settings.apiPort,
    token: settings.apiToken,
  );
});

final _haServerProvider = Provider<HaApiServer>((ref) {
  final server = HaApiServer(ref);
  ref.onDispose(server.dispose);
  return server;
});

/// A small token-authenticated JSON API served on the LAN so Home Assistant
/// (RESTful sensors / rest_command) can read and control alarms.
///
/// Endpoints (all under /api, Bearer-token auth):
///   GET    /api/status                     app + next-alarm summary
///   GET    /api/alarms                     all alarms
///   POST   /api/alarms                     create (body = alarm JSON, no id)
///   GET    /api/alarms/{id}                one alarm
///   PUT    /api/alarms/{id}                merge-update fields
///   DELETE /api/alarms/{id}                delete
///   POST   /api/alarms/{id}/enable|disable|toggle
///   GET    /api/schedules                  built-in + custom shift patterns
///
/// Hardening: only private-network callers are served, the token compare is
/// constant-time, repeated bad tokens from one address are throttled, bodies
/// are size-capped, every alarm is validated before it reaches the engine,
/// and internal errors never leak exception text.
class HaApiServer {
  HaApiServer(this._ref);
  final Ref _ref;

  static const int maxBodyBytes = 64 * 1024;
  static const int maxAuthFailures = 10;
  static const Duration authWindow = Duration(minutes: 1);

  HttpServer? _server;
  int? _port;
  String _token = '';
  Future<void> _queue = Future.value();
  final Map<String, _FailureWindow> _failures = {};

  /// Serialise start/stop transitions so rapid settings changes can't race.
  void ensure({
    required bool enabled,
    required int port,
    required String token,
  }) {
    _queue = _queue.then((_) async {
      final unchanged =
          _server != null && _port == port && _token == token && enabled;
      if (unchanged) return;
      await _stop();
      if (!enabled) return;
      _token = token;
      _port = port;
      try {
        _server = await HttpServer.bind(InternetAddress.anyIPv4, port);
        _server!.listen(_safeHandle);
        debugPrint('xalarm API listening on port $port');
      } catch (e) {
        debugPrint('xalarm API failed to bind port $port: $e');
        _server = null;
      }
    });
  }

  Future<void> _stop() async {
    await _server?.close(force: true);
    _server = null;
  }

  void dispose() {
    _queue = _queue.then((_) => _stop());
  }

  Future<void> _safeHandle(HttpRequest req) async {
    try {
      await _handle(req);
    } catch (e, st) {
      debugPrint('xalarm API error: $e\n$st');
      try {
        _json(req, HttpStatus.internalServerError, {'error': 'internal error'});
      } catch (_) {}
    }
  }

  Future<void> _handle(HttpRequest req) async {
    final remote = req.connectionInfo?.remoteAddress;
    if (remote == null || !UrlPolicy.isPrivateAddress(remote)) {
      // Never answer anything — not even a 401 — off the local network.
      _json(req, HttpStatus.forbidden, {'error': 'local network only'});
      return;
    }
    final client = remote.address;

    if (_isThrottled(client)) {
      req.response.headers.set(HttpHeaders.retryAfterHeader, '60');
      _json(req, HttpStatus.tooManyRequests, {'error': 'too many bad tokens'});
      return;
    }

    final auth = req.headers.value(HttpHeaders.authorizationHeader) ?? '';
    if (_token.isEmpty || !_constantTimeEquals(auth, 'Bearer $_token')) {
      _recordFailure(client);
      _json(req, HttpStatus.unauthorized, {'error': 'invalid token'});
      return;
    }
    _failures.remove(client);

    final parts = req.uri.pathSegments; // e.g. [api, alarms, 3, toggle]
    if (parts.isEmpty || parts.first != 'api') {
      _json(req, HttpStatus.notFound, {'error': 'not found'});
      return;
    }

    switch (parts.length) {
      case 2 when parts[1] == 'status' && req.method == 'GET':
        return _status(req);
      case 2 when parts[1] == 'schedules' && req.method == 'GET':
        return _schedules(req);
      case 2 when parts[1] == 'alarms' && req.method == 'GET':
        return _listAlarms(req);
      case 2 when parts[1] == 'alarms' && req.method == 'POST':
        return _createAlarm(req);
      case 3 when parts[1] == 'alarms':
        final id = int.tryParse(parts[2]);
        if (id == null) break;
        switch (req.method) {
          case 'GET':
            return _getAlarm(req, id);
          case 'PUT':
            return _updateAlarm(req, id);
          case 'DELETE':
            return _deleteAlarm(req, id);
        }
      case 4 when parts[1] == 'alarms' && req.method == 'POST':
        final id = int.tryParse(parts[2]);
        if (id == null) break;
        return _setEnabled(req, id, parts[3]);
    }
    _json(req, HttpStatus.notFound, {'error': 'not found'});
  }

  // --- auth helpers ---

  static bool _constantTimeEquals(String a, String b) {
    final ua = a.codeUnits;
    final ub = b.codeUnits;
    var diff = ua.length ^ ub.length;
    final n = ua.length < ub.length ? ua.length : ub.length;
    for (var i = 0; i < n; i++) {
      diff |= ua[i] ^ ub[i];
    }
    return diff == 0;
  }

  bool _isThrottled(String client) {
    final w = _failures[client];
    if (w == null) return false;
    if (DateTime.now().difference(w.start) > authWindow) {
      _failures.remove(client);
      return false;
    }
    return w.count >= maxAuthFailures;
  }

  void _recordFailure(String client) {
    final now = DateTime.now();
    final w = _failures[client];
    if (w == null || now.difference(w.start) > authWindow) {
      _failures[client] = _FailureWindow(now);
    } else {
      w.count++;
    }
    // Keep the table bounded even under a scan.
    if (_failures.length > 256) {
      _failures.remove(_failures.keys.first);
    }
  }

  // --- handlers ---

  Future<void> _status(HttpRequest req) async {
    final alarms = await _ref.read(alarmListProvider.future);
    final next = Alarm.nextAcross(alarms);
    _json(req, HttpStatus.ok, {
      'app': 'xalarm',
      'alarmCount': alarms.length,
      'enabledCount': alarms.where((a) => a.enabled).length,
      'nextAlarm': next == null
          ? null
          : {
              'id': next.alarm.id,
              'label': next.alarm.label,
              'at': next.at.toIso8601String(),
            },
    });
  }

  Future<void> _schedules(HttpRequest req) async {
    final custom = await _ref.read(customPatternsProvider.future);
    _json(req, HttpStatus.ok, {
      'builtIn': ShiftPatterns.all.map((p) => p.toJson()).toList(),
      'custom': custom.map((p) => p.toJson()).toList(),
    });
  }

  Map<String, dynamic> _alarmJson(Alarm a) => {
    ...a.toJson(),
    'summary': RecurrenceSummary.describe(a.rule, a.bounds),
    'next': a.nextFire()?.toIso8601String(),
  };

  Future<void> _listAlarms(HttpRequest req) async {
    final alarms = await _ref.read(alarmListProvider.future);
    _json(req, HttpStatus.ok, alarms.map(_alarmJson).toList());
  }

  Future<void> _getAlarm(HttpRequest req, int id) async {
    final alarm = await _find(id);
    if (alarm == null) {
      _json(req, HttpStatus.notFound, {'error': 'no alarm $id'});
      return;
    }
    _json(req, HttpStatus.ok, _alarmJson(alarm));
  }

  /// Decodes + validates an alarm body. Returns null after replying 4xx.
  Future<Alarm?> _parseAlarm(
    HttpRequest req,
    Map<String, dynamic> base,
    int id,
  ) async {
    final body = await _readBody(req);
    if (body == null) {
      _json(req, HttpStatus.badRequest, {'error': 'invalid JSON body'});
      return null;
    }
    final Alarm alarm;
    try {
      alarm = Alarm.fromJson({...base, ...body, 'id': id});
    } catch (e) {
      _json(req, HttpStatus.badRequest, {'error': 'bad alarm: $e'});
      return null;
    }
    final problem = alarm.validate() ??
        await _ref.read(ringtoneLibraryProvider).validateSoundValue(
          alarm.soundAsset,
        );
    if (problem != null) {
      _json(req, HttpStatus.badRequest, {'error': 'bad alarm: $problem'});
      return null;
    }
    return alarm;
  }

  Future<void> _createAlarm(HttpRequest req) async {
    final alarm = await _parseAlarm(req, const {}, 0);
    if (alarm == null) return;
    try {
      final created = await _ref.read(alarmListProvider.notifier).add(alarm);
      _json(req, HttpStatus.created, _alarmJson(created));
    } on InvalidAlarmException catch (e) {
      _json(req, HttpStatus.badRequest, {'error': 'bad alarm: $e'});
    }
  }

  Future<void> _updateAlarm(HttpRequest req, int id) async {
    final existing = await _find(id);
    if (existing == null) {
      _json(req, HttpStatus.notFound, {'error': 'no alarm $id'});
      return;
    }
    final merged = await _parseAlarm(req, existing.toJson(), id);
    if (merged == null) return;
    try {
      await _ref.read(alarmListProvider.notifier).updateAlarm(merged);
      _json(req, HttpStatus.ok, _alarmJson((await _find(id)) ?? merged));
    } on InvalidAlarmException catch (e) {
      _json(req, HttpStatus.badRequest, {'error': 'bad alarm: $e'});
    }
  }

  Future<void> _deleteAlarm(HttpRequest req, int id) async {
    final existing = await _find(id);
    if (existing == null) {
      _json(req, HttpStatus.notFound, {'error': 'no alarm $id'});
      return;
    }
    await _ref.read(alarmListProvider.notifier).remove(id);
    _json(req, HttpStatus.ok, {'deleted': id});
  }

  Future<void> _setEnabled(HttpRequest req, int id, String action) async {
    final existing = await _find(id);
    if (existing == null) {
      _json(req, HttpStatus.notFound, {'error': 'no alarm $id'});
      return;
    }
    final enabled = switch (action) {
      'enable' => true,
      'disable' => false,
      'toggle' => !existing.enabled,
      _ => null,
    };
    if (enabled == null) {
      _json(req, HttpStatus.notFound, {'error': 'unknown action $action'});
      return;
    }
    await _ref.read(alarmListProvider.notifier).setEnabled(id, enabled);
    final updated = await _find(id);
    _json(req, HttpStatus.ok, _alarmJson(updated ?? existing));
  }

  // --- helpers ---

  Future<Alarm?> _find(int id) async {
    final alarms = await _ref.read(alarmListProvider.future);
    for (final a in alarms) {
      if (a.id == id) return a;
    }
    return null;
  }

  /// Reads a JSON object body, refusing anything over [maxBodyBytes].
  Future<Map<String, dynamic>?> _readBody(HttpRequest req) async {
    try {
      if (req.contentLength > maxBodyBytes) return null;
      final bytes = <int>[];
      await for (final chunk in req) {
        bytes.addAll(chunk);
        if (bytes.length > maxBodyBytes) return null;
      }
      final raw = utf8.decode(bytes);
      if (raw.trim().isEmpty) return {};
      final decoded = jsonDecode(raw);
      return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
    } catch (_) {
      return null;
    }
  }

  void _json(HttpRequest req, int status, Object body) {
    final res = req.response;
    res.statusCode = status;
    res.headers.contentType = ContentType.json;
    res.headers.set('Cache-Control', 'no-store');
    res.write(jsonEncode(body));
    res.close();
  }
}

class _FailureWindow {
  _FailureWindow(this.start);
  final DateTime start;
  int count = 1;
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:recurrence_engine/recurrence_engine.dart';

import '../core/settings/settings_providers.dart';
import '../features/alarm/application/alarm_providers.dart';
import '../features/alarm/domain/alarm.dart';
import '../features/alarm/domain/recurrence_summary.dart';
import '../features/schedules/application/pattern_providers.dart';

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
class HaApiServer {
  HaApiServer(this._ref);
  final Ref _ref;

  HttpServer? _server;
  int? _port;
  String _token = '';
  Future<void> _queue = Future.value();

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
    } catch (e) {
      debugPrint('xalarm API error: $e');
      try {
        _json(req, HttpStatus.internalServerError, {'error': '$e'});
      } catch (_) {}
    }
  }

  Future<void> _handle(HttpRequest req) async {
    final res = req.response;
    res.headers.set('Access-Control-Allow-Origin', '*');
    res.headers.set(
      'Access-Control-Allow-Methods',
      'GET, POST, PUT, DELETE, OPTIONS',
    );
    res.headers.set(
      'Access-Control-Allow-Headers',
      'Authorization, Content-Type',
    );

    if (req.method == 'OPTIONS') {
      res.statusCode = HttpStatus.noContent;
      await res.close();
      return;
    }

    final auth = req.headers.value('authorization') ?? '';
    if (_token.isEmpty || auth != 'Bearer $_token') {
      _json(req, HttpStatus.unauthorized, {'error': 'invalid token'});
      return;
    }

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

  // --- handlers ---

  Future<void> _status(HttpRequest req) async {
    final alarms = await _ref.read(alarmListProvider.future);
    final now = DateTime.now();
    DateTime? next;
    Alarm? nextAlarm;
    for (final a in alarms) {
      final f = a.nextFire(from: now);
      if (f != null && (next == null || f.isBefore(next))) {
        next = f;
        nextAlarm = a;
      }
    }
    _json(req, HttpStatus.ok, {
      'app': 'xalarm',
      'alarmCount': alarms.length,
      'enabledCount': alarms.where((a) => a.enabled).length,
      'nextAlarm': next == null
          ? null
          : {
              'id': nextAlarm!.id,
              'label': nextAlarm.label,
              'at': next.toIso8601String(),
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

  Future<void> _createAlarm(HttpRequest req) async {
    final body = await _readBody(req);
    if (body == null) {
      _json(req, HttpStatus.badRequest, {'error': 'invalid JSON body'});
      return;
    }
    try {
      final alarm = Alarm.fromJson({...body, 'id': 0});
      final created =
          await _ref.read(alarmListProvider.notifier).add(alarm);
      _json(req, HttpStatus.created, _alarmJson(created));
    } catch (e) {
      _json(req, HttpStatus.badRequest, {'error': 'bad alarm: $e'});
    }
  }

  Future<void> _updateAlarm(HttpRequest req, int id) async {
    final existing = await _find(id);
    if (existing == null) {
      _json(req, HttpStatus.notFound, {'error': 'no alarm $id'});
      return;
    }
    final body = await _readBody(req);
    if (body == null) {
      _json(req, HttpStatus.badRequest, {'error': 'invalid JSON body'});
      return;
    }
    try {
      final merged = Alarm.fromJson({...existing.toJson(), ...body, 'id': id});
      await _ref.read(alarmListProvider.notifier).updateAlarm(merged);
      _json(req, HttpStatus.ok, _alarmJson(merged));
    } catch (e) {
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
    _json(req, HttpStatus.ok, _alarmJson(updated!));
  }

  // --- helpers ---

  Future<Alarm?> _find(int id) async {
    final alarms = await _ref.read(alarmListProvider.future);
    for (final a in alarms) {
      if (a.id == id) return a;
    }
    return null;
  }

  Future<Map<String, dynamic>?> _readBody(HttpRequest req) async {
    try {
      final raw = await utf8.decodeStream(req);
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
    res.write(jsonEncode(body));
    res.close();
  }
}

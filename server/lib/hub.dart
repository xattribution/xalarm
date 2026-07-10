import 'dart:async';
import 'dart:math';

import 'package:sync_protocol/sync_protocol.dart';

/// One connected (or recently dropped) app instance.
class HubClient {
  HubClient(this.send);

  /// Delivers a message to this client's socket. Swapped out on resume when
  /// a dropped client comes back on a fresh socket.
  void Function(SyncMessage) send;

  String name = '';
  String code = '';
  String resumeKey = '';
  bool connected = true;

  PairSession? session;

  /// Outgoing pair request target / incoming requester (pre-session).
  HubClient? pendingTarget;
  HubClient? pendingFrom;

  bool get registered => code.isNotEmpty;

  void trySend(SyncMessage msg) {
    if (!connected) return;
    try {
      send(msg);
    } catch (_) {
      connected = false;
    }
  }
}

/// A paired session between exactly two clients.
class PairSession {
  PairSession(this.a, this.b);
  HubClient a;
  HubClient b;
  int seq = 0;

  bool inLimbo = false;
  Timer? limboTimer;
  final Set<HubClient> resumeVotes = {};

  /// Last action per category, replayed to both sides after a restore so
  /// state reconverges. Timestamps inside are absolute server time, so
  /// replaying verbatim is correct.
  final Map<String, PeerAction> lastActions = {};

  HubClient peerOf(HubClient c) => identical(c, a) ? b : a;
  bool contains(HubClient c) => identical(c, a) || identical(c, b);
}

/// The relay: registration, pairing, action relay, and the 5-second
/// both-must-reconnect limbo. Everything lives in memory; a purged session
/// leaves no trace.
class SyncHub {
  SyncHub({this.graceMs = 5000, Random? rng, int Function()? now})
    : _rng = rng ?? Random.secure(),
      _now = now ?? (() => DateTime.now().millisecondsSinceEpoch);

  final int graceMs;
  final Random _rng;
  final int Function() _now;

  final Map<String, HubClient> _byCode = {};
  final Map<String, PairSession> _limboByResumeKey = {};

  int get registeredCount => _byCode.length;

  HubClient attach(void Function(SyncMessage) send) => HubClient(send);

  void onMessage(HubClient c, String raw) {
    SyncMessage msg;
    try {
      msg = SyncMessage.decode(raw);
    } catch (_) {
      c.trySend(const ErrorMsg(message: 'malformed message'));
      return;
    }

    switch (msg) {
      case Hello(:final name):
        _hello(c, name);
      case Resume(:final resumeKey):
        _resume(c, resumeKey);
      case PairRequest(:final targetCode):
        _pairRequest(c, targetCode);
      case PairAccept():
        _pairAccept(c);
      case PairDecline():
        _pairDecline(c);
      case ActionMsg(:final action):
        _action(c, action);
      case Ping(:final t0):
        c.trySend(Pong(t0: t0, serverTime: _now()));
      case Bye():
        onDisconnect(c);
      default:
        c.trySend(const ErrorMsg(message: 'unexpected message'));
    }
  }

  /// Socket dropped or client said bye.
  void onDisconnect(HubClient c) {
    c.connected = false;
    final session = c.session;
    if (session != null && !session.inLimbo) {
      _enterLimbo(session);
    } else if (session == null) {
      _unregister(c);
    }
    // If already in limbo, the running timer keeps counting.
  }

  // --- registration & pairing ---

  void _hello(HubClient c, String rawName) {
    if (c.registered) {
      c.trySend(const ErrorMsg(message: 'already registered'));
      return;
    }
    final name = rawName.trim().replaceAll(RegExp(r'[\x00-\x1f]'), '');
    if (name.isEmpty || name.length > 24) {
      c.trySend(const ErrorMsg(message: 'name must be 1-24 characters'));
      return;
    }
    var code = PairCodes.generate(_rng);
    while (_byCode.containsKey(code)) {
      code = PairCodes.generate(_rng);
    }
    c
      ..name = name
      ..code = code
      ..resumeKey = _newKey();
    _byCode[code] = c;
    c.trySend(Welcome(code: code, resumeKey: c.resumeKey));
  }

  void _pairRequest(HubClient c, String rawCode) {
    if (!c.registered || c.session != null) {
      c.trySend(const ErrorMsg(message: 'not available to pair'));
      return;
    }
    final code = PairCodes.normalize(rawCode);
    final target = code == null ? null : _byCode[code];
    if (target == null || !target.connected) {
      c.trySend(const ErrorMsg(message: 'no one with that code'));
      return;
    }
    if (identical(target, c)) {
      c.trySend(const ErrorMsg(message: 'that is your own code'));
      return;
    }
    if (target.session != null || target.pendingFrom != null) {
      c.trySend(const ErrorMsg(message: 'that user is busy'));
      return;
    }
    c.pendingTarget = target;
    target.pendingFrom = c;
    target.trySend(PairIncoming(name: c.name, code: c.code));
  }

  void _pairAccept(HubClient c) {
    final from = c.pendingFrom;
    if (from == null || !from.connected) {
      c.trySend(const ErrorMsg(message: 'no pending request'));
      c.pendingFrom = null;
      return;
    }
    c.pendingFrom = null;
    from.pendingTarget = null;
    final session = PairSession(from, c);
    from.session = session;
    c.session = session;
    from.trySend(Paired(peerName: c.name, peerCode: c.code));
    c.trySend(Paired(peerName: from.name, peerCode: from.code));
  }

  void _pairDecline(HubClient c) {
    final from = c.pendingFrom;
    c.pendingFrom = null;
    if (from != null) {
      from.pendingTarget = null;
      from.trySend(const PairDeclined());
    }
  }

  // --- action relay ---

  void _action(HubClient c, SyncAction action) {
    final session = c.session;
    if (session == null) {
      c.trySend(const ErrorMsg(message: 'not paired'));
      return;
    }
    if (session.inLimbo) {
      c.trySend(const ErrorMsg(message: 'session interrupted'));
      return;
    }
    session.seq++;
    final relay = PeerAction(
      action: action,
      serverTime: _now(),
      seq: session.seq,
    );
    session.lastActions[_categoryOf(action)] = relay;
    session.peerOf(c).trySend(relay);
  }

  static String _categoryOf(SyncAction a) => switch (a) {
    TimerSet() || TimerStart() || TimerPause() || TimerReset() => 'timer',
    StopwatchStart() ||
    StopwatchPause() ||
    StopwatchReset() ||
    StopwatchLap() => 'stopwatch',
  };

  // --- limbo / resume / purge ---

  void _enterLimbo(PairSession session) {
    session.inLimbo = true;
    session.resumeVotes.clear();
    _limboByResumeKey[session.a.resumeKey] = session;
    _limboByResumeKey[session.b.resumeKey] = session;
    session.a.trySend(PeerLost(graceMs: graceMs));
    session.b.trySend(PeerLost(graceMs: graceMs));
    session.limboTimer = Timer(Duration(milliseconds: graceMs), () {
      _purge(session);
    });
  }

  void _resume(HubClient c, String? resumeKey) {
    PairSession? session;
    var voter = c;

    if (c.session != null) {
      // Still-connected member voting from its existing socket.
      session = c.session;
    } else if (resumeKey != null) {
      // Dropped member back on a fresh socket: rebind its identity.
      session = _limboByResumeKey[resumeKey];
      if (session != null) {
        final old = session.a.resumeKey == resumeKey ? session.a : session.b;
        old
          ..send = c.send
          ..connected = true;
        _byCode[old.code] = old;
        voter = old;
        // Tell the fresh socket wrapper which identity it now speaks for.
        _rebound[c] = old;
      }
    }

    if (session == null || !session.inLimbo) {
      c.trySend(const ErrorMsg(message: 'nothing to reconnect to'));
      return;
    }

    session.resumeVotes.add(voter);
    if (session.resumeVotes.contains(session.a) &&
        session.resumeVotes.contains(session.b)) {
      session.limboTimer?.cancel();
      session.inLimbo = false;
      _limboByResumeKey.remove(session.a.resumeKey);
      _limboByResumeKey.remove(session.b.resumeKey);
      session.a.trySend(const Restored());
      session.b.trySend(const Restored());
      // Replay last known state so both sides reconverge.
      for (final action in session.lastActions.values) {
        session.a.trySend(action);
        session.b.trySend(action);
      }
    }
  }

  /// Fresh sockets that resumed an old identity: socket-level client →
  /// the identity it now represents. The socket layer uses this to route
  /// subsequent messages and disconnects.
  final Map<HubClient, HubClient> _rebound = {};

  HubClient effective(HubClient socketClient) =>
      _rebound[socketClient] ?? socketClient;

  void _purge(PairSession session) {
    session.limboTimer?.cancel();
    _limboByResumeKey.remove(session.a.resumeKey);
    _limboByResumeKey.remove(session.b.resumeKey);
    for (final member in [session.a, session.b]) {
      member.session = null;
      member.trySend(const Purged());
      _unregister(member);
    }
    _rebound.removeWhere((_, identity) => session.contains(identity));
  }

  void _unregister(HubClient c) {
    if (c.code.isNotEmpty) _byCode.remove(c.code);
    final target = c.pendingTarget;
    if (target != null) target.pendingFrom = null;
    final from = c.pendingFrom;
    if (from != null) {
      from.pendingTarget = null;
      from.trySend(const PairDeclined());
    }
    c
      ..code = ''
      ..resumeKey = ''
      ..pendingTarget = null
      ..pendingFrom = null;
  }

  String _newKey() {
    const chars =
        'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    return List.generate(32, (_) => chars[_rng.nextInt(chars.length)]).join();
  }
}

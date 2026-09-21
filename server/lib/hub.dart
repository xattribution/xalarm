import 'dart:async';
import 'dart:math';

import 'package:sync_protocol/sync_protocol.dart';

/// One connected (or recently dropped) app instance.
class HubClient {
  HubClient(this.send, this.close);

  /// Delivers a message to this client's socket. Swapped out on resume when
  /// a dropped client comes back on a fresh socket.
  void Function(SyncMessage) send;

  /// Closes the socket (abuse / hello timeout).
  void Function() close;

  String name = '';
  String code = '';
  String resumeKey = '';
  bool connected = true;

  HubSession? session;

  /// Outgoing join request (pre-session) and, for a host / would-be host,
  /// the queue of people waiting to be let in (insertion-ordered by code).
  HubClient? pendingTarget;
  final Map<String, HubClient> pendingFrom = {};

  /// Set while this client's socket is down and its identity is reclaimable.
  Timer? limboTimer;

  /// Closes an unregistered socket that never says hello.
  Timer? helloTimer;

  final TokenBucket messageBudget = TokenBucket(capacity: 40, perSecond: 15);
  final TokenBucket pairBudget = TokenBucket(capacity: 5, perSecond: 1 / 6);

  bool get registered => code.isNotEmpty;
  bool get isHost => session?.host == this;

  void trySend(SyncMessage msg) {
    if (!connected) return;
    try {
      send(msg);
    } catch (_) {
      connected = false;
    }
  }
}

/// A session: one host plus up to [kMaxSessionMembers] - 1 members.
class HubSession {
  HubSession(this.host) : members = [host];

  HubClient host;
  final List<HubClient> members; // host first
  bool membersCanControl = true;
  int seq = 0;

  /// Actions are rejected while the host's socket is down.
  bool get frozen => !host.connected;

  /// Last action per category, replayed to a resumed client so its display
  /// reconverges. Timestamps inside are absolute server time, so replaying
  /// verbatim is correct.
  final Map<String, PeerAction> lastActions = {};

  bool contains(HubClient c) => members.contains(c);

  bool canControl(HubClient c) => c == host || membersCanControl;

  SessionState snapshot() => SessionState(
    hostCode: host.code,
    membersCanControl: membersCanControl,
    members: [
      for (final m in members)
        SessionMember(name: m.name, code: m.code, connected: m.connected),
    ],
  );

  void broadcast(SyncMessage msg, {HubClient? except}) {
    for (final m in members) {
      if (m != except) m.trySend(msg);
    }
  }
}

/// The relay: registration, joining, action fan-out, host policy, and the
/// per-member reconnect grace window. Everything lives in memory; an ended
/// session leaves no trace.
class SyncHub {
  SyncHub({
    this.graceMs = 15000,
    this.helloTimeoutMs = 15000,
    this.maxClients = 1000,
    this.maxMessageLength = 4096,
    Random? rng,
    int Function()? now,
  }) : _rng = rng ?? Random.secure(),
       _now = now ?? (() => DateTime.now().millisecondsSinceEpoch);

  /// How long a dropped member (or host) has to come back.
  final int graceMs;

  /// A socket that has not registered within this window is closed.
  final int helloTimeoutMs;

  /// Registration cap; beyond it `hello` is refused.
  final int maxClients;

  /// Frames longer than this (in UTF-16 units) are rejected and the socket
  /// is closed — every legitimate message is a few hundred bytes.
  final int maxMessageLength;

  final Random _rng;
  final int Function() _now;

  final Map<String, HubClient> _byCode = {};
  final Map<String, HubClient> _limboByResumeKey = {};

  /// Fresh sockets that resumed an old identity: socket-level client →
  /// the identity it now represents. The socket layer uses this to route
  /// subsequent messages and disconnects.
  final Map<HubClient, HubClient> _rebound = {};

  int get registeredCount => _byCode.length;

  HubClient attach(void Function(SyncMessage) send, void Function() close) {
    final c = HubClient(send, close);
    c.helloTimer = Timer(Duration(milliseconds: helloTimeoutMs), () {
      final identity = _rebound[c] ?? c;
      if (!identity.registered && identity.connected) {
        identity.trySend(
          const ErrorMsg(message: 'say hello first', code: 'timeout'),
        );
        _closeSocket(c);
      }
    });
    return c;
  }

  HubClient effective(HubClient socketClient) =>
      _rebound[socketClient] ?? socketClient;

  void onMessage(HubClient c, String raw) {
    if (raw.length > maxMessageLength) {
      c.trySend(const ErrorMsg(message: 'message too large'));
      _closeSocket(c);
      return;
    }
    if (!c.messageBudget.take(_now())) {
      c.trySend(
        const ErrorMsg(message: 'slow down', code: ErrorCode.rateLimited),
      );
      return;
    }

    SyncMessage msg;
    try {
      msg = SyncMessage.decode(raw);
    } on FormatException {
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
      case PairAccept(:final code):
        _pairAccept(c, code);
      case PairDecline(:final code):
        _pairDecline(c, code);
      case ActionMsg(:final action):
        _action(c, action);
      case SetPolicy(:final membersCanControl):
        _setPolicy(c, membersCanControl);
      case Kick(:final code):
        _kick(c, code);
      case Ping(:final t0):
        c.trySend(Pong(t0: t0, serverTime: _now()));
      case Bye():
        _bye(c);
      default:
        c.trySend(const ErrorMsg(message: 'unexpected message'));
    }
  }

  /// Socket dropped. Session members get a grace window to come back on a
  /// fresh socket; everyone else is forgotten immediately.
  void onDisconnect(HubClient c) {
    c.helloTimer?.cancel();
    c.connected = false;
    final session = c.session;
    if (session == null) {
      _unregister(c);
      return;
    }
    if (c.limboTimer != null) return; // already counting down
    _limboByResumeKey[c.resumeKey] = c;
    c.limboTimer = Timer(Duration(milliseconds: graceMs), () => _expire(c));
    session.broadcast(
      PeerLost(code: c.code, isHost: c.isHost, graceMs: graceMs),
      except: c,
    );
    session.broadcast(session.snapshot(), except: c);
  }

  void _closeSocket(HubClient c) {
    try {
      c.close();
    } catch (_) {}
  }

  // --- registration ---

  void _hello(HubClient c, String rawName) {
    if (c.registered) {
      c.trySend(const ErrorMsg(message: 'already registered'));
      return;
    }
    if (_byCode.length >= maxClients) {
      c.trySend(const ErrorMsg(message: 'relay is full', code: ErrorCode.full));
      return;
    }
    final name = sanitizeName(rawName);
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
    c.helloTimer?.cancel();
    _byCode[code] = c;
    c.trySend(Welcome(code: code, resumeKey: c.resumeKey));
  }

  /// Display names: trimmed, no control / format / bidi characters, and
  /// whitespace collapsed, so a name can't spoof UI or hide content.
  static String sanitizeName(String raw) => raw
      .replaceAll(RegExp(r'[\p{Cc}\p{Cf}\p{Zl}\p{Zp}]', unicode: true), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  // --- joining ---

  void _pairRequest(HubClient c, String rawCode) {
    if (!c.registered || c.session != null || c.pendingTarget != null) {
      c.trySend(const ErrorMsg(message: 'not available to join'));
      return;
    }
    if (!c.pairBudget.take(_now())) {
      c.trySend(
        const ErrorMsg(
          message: 'too many requests — wait a moment',
          code: ErrorCode.rateLimited,
        ),
      );
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
    // Any member's code leads to their host.
    final host = target.session?.host ?? target;
    final session = host.session;
    if (session != null && session.members.length >= kMaxSessionMembers) {
      c.trySend(const ErrorMsg(message: 'that session is full', code: 'full'));
      return;
    }
    if (host.pendingFrom.length >= kMaxSessionMembers) {
      c.trySend(const ErrorMsg(message: 'the host is busy — try again'));
      return;
    }
    if (!host.connected) {
      c.trySend(const ErrorMsg(message: 'the host is reconnecting'));
      return;
    }
    c.pendingTarget = host;
    host.pendingFrom[c.code] = c;
    host.trySend(PairIncoming(name: c.name, code: c.code));
  }

  void _pairAccept(HubClient host, String? code) {
    final from = _takePending(host, code);
    if (from == null) {
      host.trySend(const ErrorMsg(message: 'no pending request'));
      return;
    }
    if (!from.connected || from.session != null) {
      host.trySend(const ErrorMsg(message: 'they are no longer waiting'));
      return;
    }
    var session = host.session;
    if (session != null && session.host != host) {
      // Defensive: requests are only queued on hosts / unsessioned clients.
      host.trySend(const ErrorMsg(message: 'only the host can accept'));
      from.trySend(const PairDeclined());
      return;
    }
    if (session != null && session.members.length >= kMaxSessionMembers) {
      host.trySend(const ErrorMsg(message: 'session is full'));
      from.trySend(const PairDeclined());
      return;
    }
    session ??= HubSession(host);
    host.session = session;
    session.members.add(from);
    from.session = session;
    // Anyone who was waiting on the newcomer (they were a would-be host)
    // must not be left hanging: members can't accept joins.
    _declineAllPending(from);
    session.broadcast(session.snapshot());
    // Late joiners need the current timer/stopwatch state.
    for (final action in session.lastActions.values) {
      from.trySend(action);
    }
  }

  void _declineAllPending(HubClient c) {
    for (final from in c.pendingFrom.values) {
      from.pendingTarget = null;
      from.trySend(const PairDeclined());
    }
    c.pendingFrom.clear();
  }

  void _pairDecline(HubClient host, String? code) {
    final from = _takePending(host, code);
    if (from != null) from.trySend(const PairDeclined());
  }

  /// Pops the pending requester with [code] (or the oldest one) off [host]'s
  /// queue. Clears the requester's outgoing state either way.
  HubClient? _takePending(HubClient host, String? code) {
    final key = code == null ? null : PairCodes.normalize(code);
    final HubClient? from;
    if (key != null) {
      from = host.pendingFrom.remove(key);
    } else if (host.pendingFrom.isNotEmpty) {
      from = host.pendingFrom.remove(host.pendingFrom.keys.first);
    } else {
      from = null;
    }
    from?.pendingTarget = null;
    return from;
  }

  // --- in-session ---

  void _action(HubClient c, SyncAction action) {
    final session = c.session;
    if (session == null) {
      c.trySend(
        const ErrorMsg(message: 'not in a session', code: ErrorCode.notInSession),
      );
      return;
    }
    if (session.frozen) {
      c.trySend(
        const ErrorMsg(
          message: 'the host is reconnecting',
          code: ErrorCode.frozen,
        ),
      );
      return;
    }
    if (!session.canControl(c)) {
      c.trySend(
        const ErrorMsg(
          message: 'view only — the host has locked controls',
          code: ErrorCode.viewOnly,
        ),
      );
      return;
    }
    session.seq++;
    final relay = PeerAction(
      action: action,
      serverTime: _now(),
      seq: session.seq,
      fromCode: c.code,
    );
    session.lastActions[_categoryOf(action)] = relay;
    session.broadcast(relay, except: c);
  }

  static String _categoryOf(SyncAction a) => switch (a) {
    TimerSet() || TimerStart() || TimerPause() || TimerReset() => 'timer',
    StopwatchStart() ||
    StopwatchPause() ||
    StopwatchReset() ||
    StopwatchLap() => 'stopwatch',
  };

  void _setPolicy(HubClient c, bool membersCanControl) {
    final session = c.session;
    if (session == null || !c.isHost) {
      c.trySend(
        const ErrorMsg(message: 'only the host can do that', code: ErrorCode.notHost),
      );
      return;
    }
    session.membersCanControl = membersCanControl;
    session.broadcast(session.snapshot());
  }

  void _kick(HubClient c, String rawCode) {
    final session = c.session;
    if (session == null || !c.isHost) {
      c.trySend(
        const ErrorMsg(message: 'only the host can do that', code: ErrorCode.notHost),
      );
      return;
    }
    final code = PairCodes.normalize(rawCode);
    HubClient? target;
    for (final m in session.members) {
      if (m.code == code && m != session.host) target = m;
    }
    if (target == null) {
      c.trySend(const ErrorMsg(message: 'no such member'));
      return;
    }
    _removeMember(target, const Purged(reason: PurgeReason.kicked));
  }

  void _bye(HubClient c) {
    c.helloTimer?.cancel();
    final session = c.session;
    if (session == null) {
      _unregister(c);
      return;
    }
    if (c.isHost) {
      _endSession(session, PurgeReason.hostLeft);
    } else {
      _removeMember(c, null);
    }
    _unregister(c);
  }

  // --- limbo / resume / expiry ---

  void _resume(HubClient c, String? resumeKey) {
    final old = resumeKey == null ? null : _limboByResumeKey.remove(resumeKey);
    if (old == null) {
      c.trySend(
        const ErrorMsg(
          message: 'nothing to reconnect to',
          code: ErrorCode.noSession,
        ),
      );
      return;
    }
    // A socket that registered separately before resuming gives up that
    // throwaway identity; the resumed one is what it speaks for now.
    if (c.registered && c != old) _unregister(c);
    c.helloTimer?.cancel();
    old.limboTimer?.cancel();
    old.limboTimer = null;
    old
      ..send = c.send
      ..close = c.close
      ..connected = true;
    _byCode[old.code] = old;
    if (c != old) _rebound[c] = old;

    final session = old.session;
    if (session == null) {
      // Session ended while they were away (host left / kicked).
      old.trySend(const Purged(reason: PurgeReason.ended));
      _unregister(old);
      return;
    }
    session.broadcast(Restored(code: old.code), except: old);
    session.broadcast(session.snapshot());
    for (final action in session.lastActions.values) {
      old.trySend(action);
    }
  }

  void _expire(HubClient c) {
    c.limboTimer = null;
    _limboByResumeKey.remove(c.resumeKey);
    final session = c.session;
    if (session == null) {
      _unregister(c);
      return;
    }
    if (c.isHost) {
      _endSession(session, PurgeReason.hostLost);
    } else {
      _removeMember(c, null);
    }
    _unregister(c);
  }

  /// Drop [c] from its session (they stay registered unless disconnected).
  void _removeMember(HubClient c, Purged? notice) {
    final session = c.session;
    if (session == null) return;
    session.members.remove(c);
    c.session = null;
    c.limboTimer?.cancel();
    c.limboTimer = null;
    _limboByResumeKey.remove(c.resumeKey);
    _rebound.removeWhere((_, identity) => identity == c);
    if (notice != null) c.trySend(notice);
    session.broadcast(session.snapshot());
    if (!c.connected) _unregister(c);
  }

  /// Tear down a whole session. Connected members keep their registration
  /// so they can join something else without a new hello.
  void _endSession(HubSession session, String reason) {
    for (final m in List<HubClient>.of(session.members)) {
      m.session = null;
      m.limboTimer?.cancel();
      m.limboTimer = null;
      _limboByResumeKey.remove(m.resumeKey);
      if (m != session.host) m.trySend(Purged(reason: reason));
      if (!m.connected) _unregister(m);
    }
    session.members.clear();
    _rebound.removeWhere((_, identity) => identity.session == null &&
        !identity.connected);
  }

  void _unregister(HubClient c) {
    if (c.code.isNotEmpty) _byCode.remove(c.code);
    if (c.resumeKey.isNotEmpty) _limboByResumeKey.remove(c.resumeKey);
    c.limboTimer?.cancel();
    c.limboTimer = null;
    final target = c.pendingTarget;
    if (target != null) target.pendingFrom.remove(c.code);
    _declineAllPending(c);
    c
      ..code = ''
      ..resumeKey = ''
      ..name = ''
      ..pendingTarget = null;
    _rebound.removeWhere((socket, identity) => identity == c && !c.connected);
  }

  String _newKey() {
    const chars =
        'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    return List.generate(32, (_) => chars[_rng.nextInt(chars.length)]).join();
  }
}

/// Classic token bucket: [capacity] burst, refilled at [perSecond].
class TokenBucket {
  TokenBucket({required this.capacity, required this.perSecond})
    : _tokens = capacity.toDouble();

  final int capacity;
  final double perSecond;
  double _tokens;
  int? _lastMs;

  bool take(int nowMs) {
    final last = _lastMs;
    if (last != null && nowMs > last) {
      _tokens = min(capacity.toDouble(), _tokens + (nowMs - last) / 1000 * perSecond);
    }
    _lastMs = nowMs;
    if (_tokens < 1) return false;
    _tokens -= 1;
    return true;
  }
}

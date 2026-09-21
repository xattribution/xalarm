import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sync_protocol/sync_protocol.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../../core/net/url_policy.dart';
import '../../../core/settings/app_settings.dart';
import '../../../core/settings/settings_providers.dart';

enum SyncPhase {
  idle,
  connecting,
  registered, // have a code; can host or join
  outgoing, // asked to join someone, waiting for the host
  paired, // in a session
  limbo, // our own socket dropped — reconnecting within the grace window
}

/// A join request waiting for the host's decision.
class JoinRequest {
  final String name;
  final String code;
  const JoinRequest({required this.name, required this.code});
}

class SyncState {
  final SyncPhase phase;
  final String myName;
  final String myCode;
  final String? error;

  /// People asking to join (you are the host, or about to become one).
  final List<JoinRequest> pendingJoins;

  /// The live session as the relay last described it; null when not in one.
  final SessionState? session;

  /// While the host (or we) are reconnecting: when the grace window ends.
  final DateTime? graceDeadline;

  /// A code we were asked to join (QR / link) that hasn't been sent yet.
  final String? queuedJoinCode;

  const SyncState({
    this.phase = SyncPhase.idle,
    this.myName = '',
    this.myCode = '',
    this.error,
    this.pendingJoins = const [],
    this.session,
    this.graceDeadline,
    this.queuedJoinCode,
  });

  SyncState copyWith({
    SyncPhase? phase,
    String? myName,
    String? myCode,
    String? error,
    bool clearError = false,
    List<JoinRequest>? pendingJoins,
    SessionState? session,
    bool clearSession = false,
    DateTime? graceDeadline,
    bool clearGrace = false,
    String? queuedJoinCode,
    bool clearQueuedJoin = false,
  }) => SyncState(
    phase: phase ?? this.phase,
    myName: myName ?? this.myName,
    myCode: myCode ?? this.myCode,
    error: clearError ? null : (error ?? this.error),
    pendingJoins: pendingJoins ?? this.pendingJoins,
    session: clearSession ? null : (session ?? this.session),
    graceDeadline: clearGrace ? null : (graceDeadline ?? this.graceDeadline),
    queuedJoinCode:
        clearQueuedJoin ? null : (queuedJoinCode ?? this.queuedJoinCode),
  );

  bool get isPaired => phase == SyncPhase.paired || phase == SyncPhase.limbo;
  bool get isHost => session != null && session!.hostCode == myCode;
  bool get hostConnected => session?.hostConnected ?? false;
  bool get membersCanControl => session?.membersCanControl ?? true;

  /// Whether this device may start/pause/reset/lap right now.
  bool get canControl =>
      phase == SyncPhase.paired &&
      hostConnected &&
      (isHost || membersCanControl);

  /// In a session, but temporarily unable to act (host or we dropped).
  bool get interrupted =>
      phase == SyncPhase.limbo || (phase == SyncPhase.paired && !hostConnected);

  bool get viewOnly => isPaired && !isHost && !membersCanControl;

  List<SessionMember> get members => session?.members ?? const [];
  List<SessionMember> get others =>
      [for (final m in members) if (m.code != myCode) m];
  String get hostName => session?.member(session!.hostCode)?.name ?? '';

  /// One-line description for the banner: "Synced with Sam" / "… and 2 more".
  String get peerSummary {
    final names = others.map((m) => m.name).toList();
    if (names.isEmpty) return 'Waiting for others';
    if (names.length == 1) return 'Synced with ${names.first}';
    if (names.length == 2) return 'Synced with ${names[0]} and ${names[1]}';
    return 'Synced with ${names[0]} and ${names.length - 1} more';
  }

  bool get showsBanner => isPaired;
}

final syncProvider = NotifierProvider<SyncController, SyncState>(
  SyncController.new,
);

/// Manages the WebSocket to the relay, the session state machine, the clock
/// offset, and the action fan-out to the stopwatch/timer screens.
class SyncController extends Notifier<SyncState> {
  /// Matches the relay's default GRACE_MS; only affects the countdown shown
  /// while we reconnect (the relay is authoritative).
  static const int clientGraceMs = 15000;

  WebSocketChannel? _channel;
  StreamSubscription? _sub;
  Timer? _pingTimer;
  Timer? _graceTimer;
  Timer? _retryTimer;
  String _resumeKey = '';
  String _activeUrl = '';
  final ClockSync clock = ClockSync();

  final _actions = StreamController<PeerAction>.broadcast();

  /// Remote actions from the session; stopwatch/timer screens subscribe.
  Stream<PeerAction> get actions => _actions.stream;

  @override
  SyncState build() {
    ref.onDispose(() {
      _teardownSocket();
      _actions.close();
    });
    return const SyncState();
  }

  int nowServerMs() =>
      clock.toServer(DateTime.now().millisecondsSinceEpoch);
  int toLocalMs(int serverMs) => clock.toLocal(serverMs);

  String get _configuredUrl =>
      (ref.read(settingsProvider).value ?? const AppSettings()).syncUrl;

  // --- connection lifecycle ---

  /// Register with the relay under [name]. With [joinCode] the join request
  /// is sent as soon as we have a code (QR / link flow). [serverUrl] uses a
  /// relay other than the configured one for this session only.
  Future<void> connect(
    String name, {
    String? joinCode,
    String? serverUrl,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      state = state.copyWith(error: 'Pick a name first.');
      return;
    }
    final url = (serverUrl ?? _configuredUrl).trim();
    final problem = UrlPolicy.checkWebSocket(url);
    if (problem != null) {
      state = state.copyWith(error: problem);
      return;
    }
    _teardownSocket();
    state = SyncState(
      phase: SyncPhase.connecting,
      myName: trimmed,
      queuedJoinCode: joinCode,
    );
    if (!await _openSocket(url)) return;
    _send(Hello(name: trimmed));
  }

  Future<bool> _openSocket(String url) async {
    _closeSocketOnly();
    try {
      final channel = WebSocketChannel.connect(Uri.parse(url));
      await channel.ready.timeout(const Duration(seconds: 8));
      _channel = channel;
      _activeUrl = url;
      _sub = channel.stream.listen(
        (raw) {
          if (raw is String) _onMessage(raw);
        },
        onDone: _onSocketClosed,
        onError: (_) => _onSocketClosed(),
        cancelOnError: true,
      );
      _startPings();
      return true;
    } catch (e) {
      debugPrint('Sync connect failed: $e');
      if (state.phase != SyncPhase.limbo) {
        state = SyncState(
          phase: SyncPhase.idle,
          myName: state.myName,
          error: 'Could not reach the sync server.',
        );
      }
      return false;
    }
  }

  void _startPings() {
    _pingTimer?.cancel();
    // A quick burst for the clock fix, then a keep-alive cadence.
    for (var i = 0; i < 4; i++) {
      Timer(Duration(milliseconds: 300 * i), _ping);
    }
    _pingTimer = Timer.periodic(const Duration(seconds: 12), (_) => _ping());
  }

  void _ping() =>
      _send(Ping(t0: DateTime.now().millisecondsSinceEpoch));

  void _send(SyncMessage msg) {
    try {
      _channel?.sink.add(msg.encode());
    } catch (e) {
      debugPrint('Sync send failed: $e');
    }
  }

  void _onSocketClosed() {
    _pingTimer?.cancel();
    _sub = null;
    _channel = null;
    switch (state.phase) {
      case SyncPhase.paired:
        _enterLimbo();
      case SyncPhase.limbo:
        break; // a reconnect attempt failed; the retry loop continues
      case SyncPhase.idle:
        break;
      case SyncPhase.connecting:
      case SyncPhase.registered:
      case SyncPhase.outgoing:
        state = SyncState(
          phase: SyncPhase.idle,
          myName: state.myName,
          error: 'Connection lost.',
        );
    }
  }

  /// Closes the socket without touching session/limbo bookkeeping.
  void _closeSocketOnly() {
    _pingTimer?.cancel();
    _sub?.cancel();
    _sub = null;
    try {
      _channel?.sink.close();
    } catch (_) {}
    _channel = null;
  }

  void _teardownSocket() {
    _graceTimer?.cancel();
    _retryTimer?.cancel();
    _closeSocketOnly();
    _resumeKey = '';
  }

  // --- user actions ---

  /// Ask to join whoever owns [rawCode] (a code or a scanned link).
  Future<void> requestPair(String rawCode) async {
    final link = SyncLink.parse(rawCode);
    if (link == null) {
      state = state.copyWith(error: 'Codes are 6 letters/numbers.');
      return;
    }
    if (link.code == state.myCode) {
      state = state.copyWith(error: 'That is your own code.');
      return;
    }
    if (state.phase != SyncPhase.registered) {
      state = state.copyWith(queuedJoinCode: link.code);
      return;
    }
    state = state.copyWith(
      phase: SyncPhase.outgoing,
      clearError: true,
      clearQueuedJoin: true,
    );
    _send(PairRequest(targetCode: link.code));
  }

  void acceptJoin(String code) {
    _send(PairAccept(code: code));
    _dropPending(code);
  }

  void declineJoin(String code) {
    _send(PairDecline(code: code));
    _dropPending(code);
  }

  void _dropPending(String code) {
    state = state.copyWith(
      pendingJoins: [for (final j in state.pendingJoins) if (j.code != code) j],
    );
  }

  /// Host only: let members drive, or make them watch.
  void setMembersCanControl(bool allowed) {
    if (!state.isHost) return;
    _send(SetPolicy(membersCanControl: allowed));
  }

  /// Host only.
  void kick(String code) {
    if (!state.isHost) return;
    _send(Kick(code: code));
  }

  /// Leave the session (a host ends it for everyone) and drop the relay
  /// connection entirely.
  void leave() {
    _send(const Bye());
    _teardownSocket();
    state = SyncState(myName: state.myName);
  }

  /// Manual reconnect while in limbo (the automatic retry loop also runs).
  Future<void> reconnect() => _tryResume();

  /// Publish a local timer/stopwatch action to the session. Silently
  /// ignored when this device may not control (the UI is disabled then).
  void sendAction(SyncAction action) {
    if (state.canControl) _send(ActionMsg(action: action));
  }

  // --- limbo (our own socket dropped) ---

  void _enterLimbo() {
    _graceTimer?.cancel();
    _retryTimer?.cancel();
    final deadline =
        DateTime.now().add(const Duration(milliseconds: clientGraceMs));
    state = state.copyWith(
      phase: SyncPhase.limbo,
      graceDeadline: deadline,
      clearError: true,
    );
    // Backstop: if the relay never answers, give up shortly after the
    // window the relay itself uses.
    _graceTimer = Timer(
      const Duration(milliseconds: clientGraceMs + 3000),
      () => _endSession('Session ended — could not reconnect.'),
    );
    unawaited(_tryResume());
    _retryTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (state.phase == SyncPhase.limbo && _channel == null) {
        unawaited(_tryResume());
      }
    });
  }

  Future<void> _tryResume() async {
    if (state.phase != SyncPhase.limbo || _resumeKey.isEmpty) return;
    if (_channel == null && !await _openSocket(_activeUrl)) return;
    _send(Resume(resumeKey: _resumeKey));
  }

  void _endSession(String message) {
    _teardownSocket();
    state = SyncState(myName: state.myName, error: message);
  }

  // --- inbound ---

  void _onMessage(String raw) {
    SyncMessage msg;
    try {
      msg = SyncMessage.decode(raw);
    } on FormatException {
      return;
    }

    switch (msg) {
      case Welcome(:final code, :final resumeKey):
        _resumeKey = resumeKey;
        state = state.copyWith(
          phase: SyncPhase.registered,
          myCode: code,
          clearError: true,
        );
        final queued = state.queuedJoinCode;
        if (queued != null) unawaited(requestPair(queued));

      case Pong(:final t0, :final serverTime):
        clock.addSample(
          t0: t0,
          serverTime: serverTime,
          t1: DateTime.now().millisecondsSinceEpoch,
        );

      case PairIncoming(:final name, :final code):
        if (state.pendingJoins.any((j) => j.code == code)) return;
        state = state.copyWith(
          pendingJoins: [
            ...state.pendingJoins,
            JoinRequest(name: name, code: code),
          ],
        );

      case PairDeclined():
        state = state.copyWith(
          phase: SyncPhase.registered,
          error: 'They declined.',
        );

      case SessionState():
        _graceTimer?.cancel();
        _retryTimer?.cancel();
        final memberCodes = msg.members.map((m) => m.code).toSet();
        state = state.copyWith(
          phase: SyncPhase.paired,
          session: msg,
          pendingJoins: [
            for (final j in state.pendingJoins)
              if (!memberCodes.contains(j.code)) j,
          ],
          clearError: true,
          clearGrace: msg.hostConnected,
        );

      case PeerAction():
        _actions.add(msg);

      case PeerLost(:final isHost, :final graceMs):
        if (isHost) {
          state = state.copyWith(
            graceDeadline:
                DateTime.now().add(Duration(milliseconds: graceMs)),
          );
        }

      case Restored():
        state = state.copyWith(clearGrace: true);

      case Purged(:final reason):
        _graceTimer?.cancel();
        _retryTimer?.cancel();
        state = state.copyWith(
          phase: SyncPhase.registered,
          clearSession: true,
          clearGrace: true,
          pendingJoins: const [],
          error: switch (reason) {
            PurgeReason.hostLeft => 'The host ended the session.',
            PurgeReason.hostLost => "The host's connection was lost.",
            PurgeReason.kicked => 'You were removed from the session.',
            _ => 'Session ended.',
          },
        );

      case ErrorMsg(:final message, :final code):
        if (code == ErrorCode.noSession) {
          // Our session expired while we were away.
          _endSession('Session ended.');
          return;
        }
        state = state.copyWith(
          error: message,
          // A failed join request drops back to registered.
          phase: state.phase == SyncPhase.outgoing
              ? SyncPhase.registered
              : null,
        );

      default:
        break;
    }
  }
}

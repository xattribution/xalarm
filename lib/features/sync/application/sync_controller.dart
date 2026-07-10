import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sync_protocol/sync_protocol.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../../core/settings/app_settings.dart';
import '../../../core/settings/settings_providers.dart';

enum SyncPhase {
  idle,
  connecting,
  registered, // have a code, waiting to pair
  outgoing, // sent a pair request
  incoming, // received a pair request
  paired,
  limbo, // peer lost — 5s reconnect window
}

class SyncState {
  final SyncPhase phase;
  final String myName;
  final String myCode;
  final String peerName;
  final String peerCode;
  final String incomingName;
  final String incomingCode;
  final DateTime? limboDeadline;
  final String? error;

  const SyncState({
    this.phase = SyncPhase.idle,
    this.myName = '',
    this.myCode = '',
    this.peerName = '',
    this.peerCode = '',
    this.incomingName = '',
    this.incomingCode = '',
    this.limboDeadline,
    this.error,
  });

  SyncState copyWith({
    SyncPhase? phase,
    String? myName,
    String? myCode,
    String? peerName,
    String? peerCode,
    String? incomingName,
    String? incomingCode,
    DateTime? limboDeadline,
    String? error,
    bool clearError = false,
    bool clearLimbo = false,
  }) => SyncState(
    phase: phase ?? this.phase,
    myName: myName ?? this.myName,
    myCode: myCode ?? this.myCode,
    peerName: peerName ?? this.peerName,
    peerCode: peerCode ?? this.peerCode,
    incomingName: incomingName ?? this.incomingName,
    incomingCode: incomingCode ?? this.incomingCode,
    limboDeadline: clearLimbo ? null : (limboDeadline ?? this.limboDeadline),
    error: clearError ? null : (error ?? this.error),
  );

  bool get isPaired => phase == SyncPhase.paired;
  bool get showsBanner => phase == SyncPhase.paired || phase == SyncPhase.limbo;
}

final syncProvider = NotifierProvider<SyncController, SyncState>(
  SyncController.new,
);

/// Manages the WebSocket to the relay, the pairing state machine, the clock
/// offset, and the action fan-out to the stopwatch/timer screens.
class SyncController extends Notifier<SyncState> {
  WebSocketChannel? _channel;
  StreamSubscription? _sub;
  Timer? _pingTimer;
  Timer? _limboTimer;
  String _resumeKey = '';
  final ClockSync clock = ClockSync();

  final _actions = StreamController<PeerAction>.broadcast();

  /// Remote actions from the peer; stopwatch/timer screens subscribe.
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

  // --- connection lifecycle ---

  Future<void> connect(String name) async {
    if (name.trim().isEmpty) {
      state = state.copyWith(error: 'Pick a name first.');
      return;
    }
    state = SyncState(phase: SyncPhase.connecting, myName: name.trim());
    if (!await _openSocket()) return;
    _send(Hello(name: name.trim()));
  }

  Future<bool> _openSocket() async {
    _teardownSocket(keepState: true);
    final url =
        (ref.read(settingsProvider).value ?? const AppSettings()).syncUrl;
    try {
      final channel = WebSocketChannel.connect(Uri.parse(url));
      await channel.ready.timeout(const Duration(seconds: 8));
      _channel = channel;
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
      state = SyncState(
        phase: SyncPhase.idle,
        myName: state.myName,
        error: 'Could not reach the sync server.',
      );
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
    if (state.phase == SyncPhase.paired) {
      // Our own socket dropped mid-session: same 5s window applies.
      _enterLimbo(graceMs: 5000, socketDown: true);
    } else if (state.phase != SyncPhase.idle &&
        state.phase != SyncPhase.limbo) {
      state = SyncState(
        phase: SyncPhase.idle,
        myName: state.myName,
        error: 'Connection lost.',
      );
    }
  }

  void _teardownSocket({bool keepState = false}) {
    _pingTimer?.cancel();
    _limboTimer?.cancel();
    _sub?.cancel();
    _sub = null;
    try {
      _channel?.sink.close();
    } catch (_) {}
    _channel = null;
    if (!keepState) _resumeKey = '';
  }

  // --- user actions ---

  Future<void> requestPair(String rawCode) async {
    final code = PairCodes.normalize(rawCode);
    if (code == null) {
      state = state.copyWith(error: 'Codes are 6 letters/numbers.');
      return;
    }
    state = state.copyWith(phase: SyncPhase.outgoing, clearError: true);
    _send(PairRequest(targetCode: code));
  }

  void acceptPair() => _send(const PairAccept());

  void declinePair() {
    _send(const PairDecline());
    state = state.copyWith(
      phase: SyncPhase.registered,
      incomingName: '',
      incomingCode: '',
    );
  }

  /// User-initiated disconnect (or leaving the sync flow entirely).
  void disconnect() {
    _send(const Bye());
    if (state.phase == SyncPhase.paired) {
      // Server puts the session in limbo; we mirror it so the user can
      // change their mind within the window.
      _enterLimbo(graceMs: 5000, socketDown: false);
    } else {
      _teardownSocket();
      state = const SyncState();
    }
  }

  /// The reconnect vote during limbo.
  Future<void> reconnect() async {
    if (state.phase != SyncPhase.limbo) return;
    if (_channel == null) {
      if (!await _openSocket()) return;
      _send(Resume(resumeKey: _resumeKey));
    } else {
      _send(const Resume());
    }
  }

  /// Publish a local timer/stopwatch action to the peer.
  void sendAction(SyncAction action) {
    if (state.isPaired) _send(ActionMsg(action: action));
  }

  // --- inbound ---

  void _onMessage(String raw) {
    SyncMessage msg;
    try {
      msg = SyncMessage.decode(raw);
    } catch (_) {
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
      case Pong(:final t0, :final serverTime):
        clock.addSample(
          t0: t0,
          serverTime: serverTime,
          t1: DateTime.now().millisecondsSinceEpoch,
        );
      case PairIncoming(:final name, :final code):
        state = state.copyWith(
          phase: SyncPhase.incoming,
          incomingName: name,
          incomingCode: code,
        );
      case PairDeclined():
        state = state.copyWith(
          phase: SyncPhase.registered,
          error: 'They declined.',
        );
      case Paired(:final peerName, :final peerCode):
        _limboTimer?.cancel();
        state = state.copyWith(
          phase: SyncPhase.paired,
          peerName: peerName,
          peerCode: peerCode,
          incomingName: '',
          incomingCode: '',
          clearError: true,
          clearLimbo: true,
        );
      case PeerAction():
        _actions.add(msg);
      case PeerLost(:final graceMs):
        _enterLimbo(graceMs: graceMs, socketDown: false);
      case Restored():
        _limboTimer?.cancel();
        state = state.copyWith(
          phase: SyncPhase.paired,
          clearLimbo: true,
          clearError: true,
        );
      case Purged():
        _teardownSocket();
        state = const SyncState(error: 'Session ended.');
      case ErrorMsg(:final message):
        state = state.copyWith(
          error: message,
          // A failed pair request drops back to registered.
          phase: state.phase == SyncPhase.outgoing
              ? SyncPhase.registered
              : null,
        );
      default:
        break;
    }
  }

  void _enterLimbo({required int graceMs, required bool socketDown}) {
    _limboTimer?.cancel();
    final deadline = DateTime.now().add(Duration(milliseconds: graceMs));
    state = state.copyWith(phase: SyncPhase.limbo, limboDeadline: deadline);
    // Local backstop: if the server's purge doesn't reach us (socket down),
    // clean up ourselves shortly after the deadline.
    _limboTimer = Timer(Duration(milliseconds: graceMs + 1500), () {
      if (state.phase == SyncPhase.limbo) {
        _teardownSocket();
        state = const SyncState(error: 'Session ended.');
      }
    });
  }
}

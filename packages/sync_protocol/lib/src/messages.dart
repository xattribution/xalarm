import 'dart:convert';

import 'actions.dart';

/// Wire messages between app and relay server. JSON envelope:
/// `{"type": "...", ...fields}`. Client→server and server→client types live
/// in one sealed hierarchy so both sides share the codec.
///
/// Sessions have one **host** (the client whose code was joined) and up to
/// [kMaxSessionMembers] members. The host decides whether members may
/// control the shared timer/stopwatch ([SetPolicy]) and can remove members
/// ([Kick]). Everyone always *sees* the live state.
sealed class SyncMessage {
  const SyncMessage();

  Map<String, dynamic> toJson();
  String encode() => jsonEncode(toJson());

  /// Decodes one message. Throws [FormatException] on anything that is not
  /// a well-formed message of a known type (including wrong field types, so
  /// callers only ever need to catch one exception).
  static SyncMessage decode(String raw) {
    try {
      return _decode(raw);
    } on FormatException {
      rethrow;
    } catch (e) {
      throw FormatException('Malformed message: $e');
    }
  }

  static SyncMessage _decode(String raw) {
    final json = Map<String, dynamic>.from(jsonDecode(raw) as Map);
    switch (json['type'] as String) {
      // client → server
      case 'hello':
        return Hello(name: json['name'] as String);
      case 'resume':
        return Resume(resumeKey: json['resumeKey'] as String?);
      case 'pairRequest':
        return PairRequest(targetCode: json['targetCode'] as String);
      case 'pairAccept':
        return PairAccept(code: json['code'] as String?);
      case 'pairDecline':
        return PairDecline(code: json['code'] as String?);
      case 'action':
        return ActionMsg(
          action: SyncAction.fromJson(
            Map<String, dynamic>.from(json['action'] as Map),
          ),
        );
      case 'ping':
        return Ping(t0: json['t0'] as int);
      case 'bye':
        return const Bye();
      case 'setPolicy':
        return SetPolicy(membersCanControl: json['membersCanControl'] as bool);
      case 'kick':
        return Kick(code: json['code'] as String);
      // server → client
      case 'welcome':
        return Welcome(
          code: json['code'] as String,
          resumeKey: json['resumeKey'] as String,
        );
      case 'pairIncoming':
        return PairIncoming(
          name: json['name'] as String,
          code: json['code'] as String,
        );
      case 'pairDeclined':
        return const PairDeclined();
      case 'sessionState':
        return SessionState(
          hostCode: json['hostCode'] as String,
          membersCanControl: json['membersCanControl'] as bool,
          members: [
            for (final m in json['members'] as List)
              SessionMember.fromJson(Map<String, dynamic>.from(m as Map)),
          ],
        );
      case 'peerAction':
        return PeerAction(
          action: SyncAction.fromJson(
            Map<String, dynamic>.from(json['action'] as Map),
          ),
          serverTime: json['serverTime'] as int,
          seq: json['seq'] as int,
          fromCode: json['fromCode'] as String? ?? '',
        );
      case 'pong':
        return Pong(t0: json['t0'] as int, serverTime: json['serverTime'] as int);
      case 'peerLost':
        return PeerLost(
          code: json['code'] as String,
          isHost: json['isHost'] as bool,
          graceMs: json['graceMs'] as int,
        );
      case 'restored':
        return Restored(code: json['code'] as String);
      case 'purged':
        return Purged(reason: json['reason'] as String? ?? 'ended');
      case 'error':
        return ErrorMsg(
          message: json['message'] as String,
          code: json['code'] as String?,
        );
      default:
        throw FormatException('Unknown message type: ${json['type']}');
    }
  }
}

/// Upper bound on people in one session (host included).
const int kMaxSessionMembers = 8;

// --- client → server ---

class Hello extends SyncMessage {
  final String name;
  const Hello({required this.name});
  @override
  Map<String, dynamic> toJson() => {'type': 'hello', 'name': name};
}

/// Reclaim a dropped identity from a fresh socket within the grace window.
class Resume extends SyncMessage {
  final String? resumeKey;
  const Resume({this.resumeKey});
  @override
  Map<String, dynamic> toJson() =>
      {'type': 'resume', 'resumeKey': resumeKey};
}

/// Ask to join the session of whoever owns [targetCode] (or start one with
/// them if they are not in a session yet). The host must accept.
class PairRequest extends SyncMessage {
  final String targetCode;
  const PairRequest({required this.targetCode});
  @override
  Map<String, dynamic> toJson() =>
      {'type': 'pairRequest', 'targetCode': targetCode};
}

/// Host accepts the pending requester with [code] (null = the oldest one).
class PairAccept extends SyncMessage {
  final String? code;
  const PairAccept({this.code});
  @override
  Map<String, dynamic> toJson() => {'type': 'pairAccept', 'code': code};
}

class PairDecline extends SyncMessage {
  final String? code;
  const PairDecline({this.code});
  @override
  Map<String, dynamic> toJson() => {'type': 'pairDecline', 'code': code};
}

class ActionMsg extends SyncMessage {
  final SyncAction action;
  const ActionMsg({required this.action});
  @override
  Map<String, dynamic> toJson() =>
      {'type': 'action', 'action': action.toJson()};
}

class Ping extends SyncMessage {
  final int t0;
  const Ping({required this.t0});
  @override
  Map<String, dynamic> toJson() => {'type': 'ping', 't0': t0};
}

/// Leave for good: a member leaves the session, a host ends it for everyone.
class Bye extends SyncMessage {
  const Bye();
  @override
  Map<String, dynamic> toJson() => {'type': 'bye'};
}

/// Host-only: whether members may start/pause/reset/lap. Everyone can always
/// watch; the host can always control.
class SetPolicy extends SyncMessage {
  final bool membersCanControl;
  const SetPolicy({required this.membersCanControl});
  @override
  Map<String, dynamic> toJson() =>
      {'type': 'setPolicy', 'membersCanControl': membersCanControl};
}

/// Host-only: remove a member from the session.
class Kick extends SyncMessage {
  final String code;
  const Kick({required this.code});
  @override
  Map<String, dynamic> toJson() => {'type': 'kick', 'code': code};
}

// --- server → client ---

class Welcome extends SyncMessage {
  final String code;
  final String resumeKey;
  const Welcome({required this.code, required this.resumeKey});
  @override
  Map<String, dynamic> toJson() =>
      {'type': 'welcome', 'code': code, 'resumeKey': resumeKey};
}

/// Delivered to the host (or the would-be host) when someone wants to join.
class PairIncoming extends SyncMessage {
  final String name;
  final String code;
  const PairIncoming({required this.name, required this.code});
  @override
  Map<String, dynamic> toJson() =>
      {'type': 'pairIncoming', 'name': name, 'code': code};
}

class PairDeclined extends SyncMessage {
  const PairDeclined();
  @override
  Map<String, dynamic> toJson() => {'type': 'pairDeclined'};
}

class SessionMember {
  final String name;
  final String code;
  final bool connected;
  const SessionMember({
    required this.name,
    required this.code,
    required this.connected,
  });

  Map<String, dynamic> toJson() =>
      {'name': name, 'code': code, 'connected': connected};

  factory SessionMember.fromJson(Map<String, dynamic> json) => SessionMember(
    name: json['name'] as String,
    code: json['code'] as String,
    connected: json['connected'] as bool? ?? true,
  );
}

/// The full picture of a session, sent to every member whenever membership,
/// connectivity, or policy changes. The host is always `members.first`.
class SessionState extends SyncMessage {
  final String hostCode;
  final bool membersCanControl;
  final List<SessionMember> members;
  const SessionState({
    required this.hostCode,
    required this.membersCanControl,
    required this.members,
  });

  SessionMember? member(String code) {
    for (final m in members) {
      if (m.code == code) return m;
    }
    return null;
  }

  bool get hostConnected => member(hostCode)?.connected ?? false;

  @override
  Map<String, dynamic> toJson() => {
    'type': 'sessionState',
    'hostCode': hostCode,
    'membersCanControl': membersCanControl,
    'members': members.map((m) => m.toJson()).toList(),
  };
}

class PeerAction extends SyncMessage {
  final SyncAction action;
  final int serverTime;
  final int seq;
  final String fromCode;
  const PeerAction({
    required this.action,
    required this.serverTime,
    required this.seq,
    this.fromCode = '',
  });
  @override
  Map<String, dynamic> toJson() => {
    'type': 'peerAction',
    'action': action.toJson(),
    'serverTime': serverTime,
    'seq': seq,
    'fromCode': fromCode,
  };
}

class Pong extends SyncMessage {
  final int t0;
  final int serverTime;
  const Pong({required this.t0, required this.serverTime});
  @override
  Map<String, dynamic> toJson() =>
      {'type': 'pong', 't0': t0, 'serverTime': serverTime};
}

/// A member's socket dropped. If it was the host, the session is frozen
/// (actions rejected) until they resume or the grace window expires.
class PeerLost extends SyncMessage {
  final String code;
  final bool isHost;
  final int graceMs;
  const PeerLost({
    required this.code,
    required this.isHost,
    required this.graceMs,
  });
  @override
  Map<String, dynamic> toJson() => {
    'type': 'peerLost',
    'code': code,
    'isHost': isHost,
    'graceMs': graceMs,
  };
}

class Restored extends SyncMessage {
  final String code;
  const Restored({required this.code});
  @override
  Map<String, dynamic> toJson() => {'type': 'restored', 'code': code};
}

/// You are no longer in a session. [reason] is one of [PurgeReason].
class Purged extends SyncMessage {
  final String reason;
  const Purged({this.reason = PurgeReason.ended});
  @override
  Map<String, dynamic> toJson() => {'type': 'purged', 'reason': reason};
}

class PurgeReason {
  const PurgeReason._();
  static const hostLeft = 'hostLeft';
  static const hostLost = 'hostLost';
  static const kicked = 'kicked';
  static const ended = 'ended';
}

class ErrorMsg extends SyncMessage {
  final String message;

  /// Machine-readable reason (see [ErrorCode]); null for generic errors.
  final String? code;
  const ErrorMsg({required this.message, this.code});
  @override
  Map<String, dynamic> toJson() =>
      {'type': 'error', 'message': message, 'code': code};
}

class ErrorCode {
  const ErrorCode._();
  static const viewOnly = 'viewOnly';
  static const frozen = 'frozen';
  static const notInSession = 'notInSession';
  static const noSession = 'noSession';
  static const rateLimited = 'rateLimited';
  static const full = 'full';
  static const notHost = 'notHost';
}

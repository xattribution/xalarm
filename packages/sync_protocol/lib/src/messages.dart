import 'dart:convert';

import 'actions.dart';

/// Wire messages between app and relay server. JSON envelope:
/// `{"type": "...", ...fields}`. Client→server and server→client types live
/// in one sealed hierarchy so both sides share the codec.
sealed class SyncMessage {
  const SyncMessage();

  Map<String, dynamic> toJson();
  String encode() => jsonEncode(toJson());

  static SyncMessage decode(String raw) {
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
        return const PairAccept();
      case 'pairDecline':
        return const PairDecline();
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
      case 'paired':
        return Paired(
          peerName: json['peerName'] as String,
          peerCode: json['peerCode'] as String,
        );
      case 'peerAction':
        return PeerAction(
          action: SyncAction.fromJson(
            Map<String, dynamic>.from(json['action'] as Map),
          ),
          serverTime: json['serverTime'] as int,
          seq: json['seq'] as int,
        );
      case 'pong':
        return Pong(t0: json['t0'] as int, serverTime: json['serverTime'] as int);
      case 'peerLost':
        return PeerLost(graceMs: json['graceMs'] as int);
      case 'restored':
        return const Restored();
      case 'purged':
        return const Purged();
      case 'error':
        return ErrorMsg(message: json['message'] as String);
      default:
        throw FormatException('Unknown message type: ${json['type']}');
    }
  }
}

// --- client → server ---

class Hello extends SyncMessage {
  final String name;
  const Hello({required this.name});
  @override
  Map<String, dynamic> toJson() => {'type': 'hello', 'name': name};
}

/// Vote to restore a limbo session. A dropped client reconnects its socket
/// first, then sends its resumeKey; the still-connected client sends
/// resume with no key. Both must arrive within the grace window.
class Resume extends SyncMessage {
  final String? resumeKey;
  const Resume({this.resumeKey});
  @override
  Map<String, dynamic> toJson() =>
      {'type': 'resume', 'resumeKey': resumeKey};
}

class PairRequest extends SyncMessage {
  final String targetCode;
  const PairRequest({required this.targetCode});
  @override
  Map<String, dynamic> toJson() =>
      {'type': 'pairRequest', 'targetCode': targetCode};
}

class PairAccept extends SyncMessage {
  const PairAccept();
  @override
  Map<String, dynamic> toJson() => {'type': 'pairAccept'};
}

class PairDecline extends SyncMessage {
  const PairDecline();
  @override
  Map<String, dynamic> toJson() => {'type': 'pairDecline'};
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

class Bye extends SyncMessage {
  const Bye();
  @override
  Map<String, dynamic> toJson() => {'type': 'bye'};
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

class Paired extends SyncMessage {
  final String peerName;
  final String peerCode;
  const Paired({required this.peerName, required this.peerCode});
  @override
  Map<String, dynamic> toJson() =>
      {'type': 'paired', 'peerName': peerName, 'peerCode': peerCode};
}

class PeerAction extends SyncMessage {
  final SyncAction action;
  final int serverTime;
  final int seq;
  const PeerAction({
    required this.action,
    required this.serverTime,
    required this.seq,
  });
  @override
  Map<String, dynamic> toJson() => {
    'type': 'peerAction',
    'action': action.toJson(),
    'serverTime': serverTime,
    'seq': seq,
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

class PeerLost extends SyncMessage {
  final int graceMs;
  const PeerLost({required this.graceMs});
  @override
  Map<String, dynamic> toJson() => {'type': 'peerLost', 'graceMs': graceMs};
}

class Restored extends SyncMessage {
  const Restored();
  @override
  Map<String, dynamic> toJson() => {'type': 'restored'};
}

class Purged extends SyncMessage {
  const Purged();
  @override
  Map<String, dynamic> toJson() => {'type': 'purged'};
}

class ErrorMsg extends SyncMessage {
  final String message;
  const ErrorMsg({required this.message});
  @override
  Map<String, dynamic> toJson() => {'type': 'error', 'message': message};
}

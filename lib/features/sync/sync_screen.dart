import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:sync_protocol/sync_protocol.dart';

import '../../core/settings/app_settings.dart';
import '../../core/settings/settings_providers.dart';
import '../../core/theme/app_theme.dart';
import 'application/sync_controller.dart';
import 'qr_scan_screen.dart';

/// Time Sync: get a code, share it (or its QR), let people in, and the
/// timer + stopwatch stay in lockstep for everyone. The host decides
/// whether members can control or only watch.
class SyncScreen extends ConsumerStatefulWidget {
  const SyncScreen({super.key, this.initialLink});

  /// A scanned / tapped `xalarm://sync…` link to act on when the screen
  /// opens.
  final SyncLink? initialLink;

  @override
  ConsumerState<SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends ConsumerState<SyncScreen> {
  final _name = TextEditingController();
  final _code = TextEditingController();
  Timer? _graceTick;
  SyncLink? _pendingLink;

  @override
  void initState() {
    super.initState();
    _name.text = ref.read(syncProvider).myName;
    final link = widget.initialLink;
    if (link != null) _applyLink(link);
  }

  @override
  void dispose() {
    _graceTick?.cancel();
    _name.dispose();
    _code.dispose();
    super.dispose();
  }

  /// A link arrived (scan / deep link): join now if we're registered,
  /// otherwise remember it for the connect step.
  void _applyLink(SyncLink link) {
    final phase = ref.read(syncProvider).phase;
    _code.text = PairCodes.pretty(link.code);
    if (phase == SyncPhase.registered) {
      ref.read(syncProvider.notifier).requestPair(link.code);
    } else if (phase == SyncPhase.idle) {
      setState(() => _pendingLink = link);
    }
  }

  Future<void> _scan() async {
    final raw = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const QrScanScreen()),
    );
    if (raw == null || !mounted) return;
    final link = SyncLink.parse(raw);
    if (link == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('That QR code is not an xalarm session.')),
      );
      return;
    }
    _applyLink(link);
  }

  void _ensureGraceTicker(bool on) {
    if (on && _graceTick == null) {
      _graceTick = Timer.periodic(const Duration(milliseconds: 250), (_) {
        if (mounted) setState(() {});
      });
    } else if (!on && _graceTick != null) {
      _graceTick?.cancel();
      _graceTick = null;
    }
  }

  Future<void> _confirmLeave(SyncState sync) async {
    final controller = ref.read(syncProvider.notifier);
    if (!sync.isHost || sync.others.isEmpty) {
      controller.leave();
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('End the session?'),
        content: Text(
          'You are hosting. Leaving ends the session for '
          '${sync.others.length == 1 ? 'the other person' : 'everyone'}.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('End session'),
          ),
        ],
      ),
    );
    if (ok ?? false) controller.leave();
  }

  @override
  Widget build(BuildContext context) {
    final sync = ref.watch(syncProvider);
    final controller = ref.read(syncProvider.notifier);
    final scheme = Theme.of(context).colorScheme;
    _ensureGraceTicker(sync.graceDeadline != null);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Time Sync'),
        actions: [
          if (sync.phase == SyncPhase.idle ||
              sync.phase == SyncPhase.registered)
            IconButton(
              tooltip: 'Scan a session QR code',
              icon: const Icon(Icons.qr_code_scanner),
              onPressed: _scan,
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
        children: [
          Text(
            'Share a live timer and stopwatch. The host chooses whether '
            'everyone can start and stop, or only watch.',
            style: TextStyle(color: context.mutedColor, fontSize: 13.5),
          ),
          const SizedBox(height: 20),
          if (sync.error != null) ...[
            _Notice(text: sync.error!, color: scheme.error),
            const SizedBox(height: 16),
          ],
          if (sync.pendingJoins.isNotEmpty) ...[
            for (final j in sync.pendingJoins) _JoinCard(request: j),
            const SizedBox(height: 16),
          ],
          ...switch (sync.phase) {
            SyncPhase.idle => _idle(controller),
            SyncPhase.connecting => const [
              Center(child: CircularProgressIndicator()),
            ],
            SyncPhase.registered ||
            SyncPhase.outgoing => _registered(sync, controller),
            SyncPhase.paired => _paired(sync, controller),
            SyncPhase.limbo => _limbo(sync, controller),
          },
        ],
      ),
    );
  }

  List<Widget> _idle(SyncController controller) => [
    _Panel(
      child: TextField(
        controller: _name,
        maxLength: 24,
        decoration: const InputDecoration(
          labelText: 'Your display name',
          border: InputBorder.none,
          counterText: '',
        ),
      ),
    ),
    const SizedBox(height: 16),
    if (_pendingLink != null) ...[
      _Notice(
        text: 'Ready to join ${PairCodes.pretty(_pendingLink!.code)}'
            '${_pendingLink!.server != null ? ' via ${_pendingLink!.server}' : ''}',
        color: Theme.of(context).colorScheme.primary,
      ),
      const SizedBox(height: 12),
      FilledButton.icon(
        onPressed: () => controller.connect(
          _name.text,
          joinCode: _pendingLink!.code,
          serverUrl: _pendingLink!.server,
        ),
        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
        icon: const Icon(Icons.login),
        label: const Text('Join session'),
      ),
      const SizedBox(height: 8),
      TextButton(
        onPressed: () => setState(() => _pendingLink = null),
        child: const Text('Not now'),
      ),
    ] else
      FilledButton(
        onPressed: () => controller.connect(_name.text),
        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
        child: const Text('Get my code'),
      ),
  ];

  List<Widget> _registered(SyncState sync, SyncController controller) {
    final server =
        (ref.read(settingsProvider).value ?? const AppSettings()).syncUrl;
    final link = SyncLink(code: sync.myCode, server: server).encode();
    return [
      const _SectionLabel('Your code'),
      _Panel(
        child: Column(
          children: [
            ListTile(
              title: Text(
                PairCodes.pretty(sync.myCode),
                style: const TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 2,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
              subtitle: Text(
                '${sync.myName} — share this or let them scan the QR',
                style: TextStyle(color: context.mutedColor, fontSize: 12.5),
              ),
              trailing: IconButton(
                tooltip: 'Copy code',
                icon: const Icon(Icons.copy, size: 20),
                onPressed: () =>
                    Clipboard.setData(ClipboardData(text: sync.myCode)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: _QrCard(data: link),
            ),
          ],
        ),
      ),
      const SizedBox(height: 20),
      const _SectionLabel('Join someone'),
      _Panel(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _code,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                    hintText: 'ABC-234',
                    border: InputBorder.none,
                  ),
                  style: const TextStyle(fontSize: 20, letterSpacing: 1.5),
                ),
              ),
              IconButton(
                tooltip: 'Scan QR',
                icon: const Icon(Icons.qr_code_scanner),
                onPressed: sync.phase == SyncPhase.outgoing ? null : _scan,
              ),
              FilledButton(
                onPressed: sync.phase == SyncPhase.outgoing
                    ? null
                    : () => controller.requestPair(_code.text),
                child: Text(
                  sync.phase == SyncPhase.outgoing ? 'Waiting…' : 'Join',
                ),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 8),
      Text(
        'Whoever you join becomes the host. When someone joins you, you host.',
        style: TextStyle(color: context.mutedColor, fontSize: 12.5),
      ),
      const SizedBox(height: 24),
      TextButton(
        onPressed: controller.leave,
        child: const Text('Leave'),
      ),
    ];
  }

  List<Widget> _paired(SyncState sync, SyncController controller) {
    final scheme = Theme.of(context).colorScheme;
    final server =
        (ref.read(settingsProvider).value ?? const AppSettings()).syncUrl;
    final link = SyncLink(code: sync.myCode, server: server).encode();
    final hostLost = !sync.hostConnected;
    return [
      if (hostLost) ...[
        _Notice(
          text: 'Host reconnecting… ${_secondsLeft(sync)}',
          color: scheme.error,
        ),
        const SizedBox(height: 16),
      ],
      _Panel(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Icon(
                sync.viewOnly ? Icons.visibility : Icons.link,
                size: 40,
                color: scheme.primary,
              ),
              const SizedBox(height: 12),
              Text(
                sync.isHost ? 'You are hosting' : 'Hosted by ${sync.hostName}',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                sync.isHost
                    ? (sync.membersCanControl
                        ? 'Everyone can start, pause, reset and lap.'
                        : 'Only you can control. Everyone else watches.')
                    : (sync.viewOnly
                        ? 'View only — the host controls the timer and stopwatch.'
                        : 'You can control the timer and stopwatch too.'),
                textAlign: TextAlign.center,
                style: TextStyle(color: context.mutedColor, fontSize: 12.5),
              ),
            ],
          ),
        ),
      ),
      if (sync.isHost) ...[
        const SizedBox(height: 16),
        const _SectionLabel('Host controls'),
        _Panel(
          child: SwitchListTile(
            title: const Text('Members can control'),
            subtitle: Text(
              'Off = members only watch the timer and stopwatch.',
              style: TextStyle(color: context.mutedColor, fontSize: 12.5),
            ),
            value: sync.membersCanControl,
            onChanged: controller.setMembersCanControl,
          ),
        ),
      ],
      const SizedBox(height: 16),
      _SectionLabel('In this session (${sync.members.length})'),
      _Panel(
        child: Column(
          children: [
            for (final m in sync.members)
              ListTile(
                leading: Icon(
                  m.code == sync.session!.hostCode
                      ? Icons.star
                      : Icons.person_outline,
                  color: m.connected ? scheme.primary : context.mutedColor,
                ),
                title: Text(
                  m.code == sync.myCode ? '${m.name} (you)' : m.name,
                  style: TextStyle(
                    color: m.connected ? null : context.mutedColor,
                  ),
                ),
                subtitle: Text(
                  '${PairCodes.pretty(m.code)}'
                  '${m.code == sync.session!.hostCode ? ' · host' : ''}'
                  '${m.connected ? '' : ' · reconnecting'}',
                  style: TextStyle(color: context.mutedColor, fontSize: 12),
                ),
                trailing: sync.isHost && m.code != sync.myCode
                    ? IconButton(
                        tooltip: 'Remove',
                        icon: const Icon(Icons.person_remove_outlined),
                        onPressed: () => controller.kick(m.code),
                      )
                    : null,
              ),
          ],
        ),
      ),
      if (sync.isHost && sync.members.length < kMaxSessionMembers) ...[
        const SizedBox(height: 16),
        const _SectionLabel('Invite more'),
        _Panel(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Text(
                  PairCodes.pretty(sync.myCode),
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 10),
                _QrCard(data: link, size: 160),
              ],
            ),
          ),
        ),
      ],
      const SizedBox(height: 24),
      OutlinedButton.icon(
        onPressed: () => _confirmLeave(sync),
        icon: const Icon(Icons.link_off, size: 18),
        label: Text(sync.isHost ? 'End session' : 'Leave session'),
      ),
    ];
  }

  List<Widget> _limbo(SyncState sync, SyncController controller) => [
    _Panel(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const Icon(Icons.link_off, size: 40),
            const SizedBox(height: 12),
            const Text(
              'Connection interrupted',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              'Reconnecting automatically… ${_secondsLeft(sync)}',
              textAlign: TextAlign.center,
              style: TextStyle(color: context.mutedColor, fontSize: 13),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: controller.reconnect,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Retry now'),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: controller.leave,
              child: const Text('Give up'),
            ),
          ],
        ),
      ),
    ),
  ];

  String _secondsLeft(SyncState sync) {
    final d = sync.graceDeadline;
    if (d == null) return '';
    final ms = d.difference(DateTime.now()).inMilliseconds.clamp(0, 600000);
    return '${(ms / 1000).toStringAsFixed(0)} s left';
  }
}

class _JoinCard extends ConsumerWidget {
  const _JoinCard({required this.request});
  final JoinRequest request;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(syncProvider.notifier);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: _Panel(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const Icon(Icons.person_add_alt_1_outlined),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${request.name} wants to join',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    Text(
                      PairCodes.pretty(request.code),
                      style:
                          TextStyle(color: context.mutedColor, fontSize: 12),
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: () => controller.declineJoin(request.code),
                child: const Text('Decline'),
              ),
              FilledButton(
                onPressed: () => controller.acceptJoin(request.code),
                child: const Text('Accept'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QrCard extends StatelessWidget {
  const _QrCard({required this.data, this.size = 200});
  final String data;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
        ),
        child: QrImageView(
          data: data,
          version: QrVersions.auto,
          size: size,
          backgroundColor: Colors.white,
          eyeStyle: const QrEyeStyle(
            eyeShape: QrEyeShape.square,
            color: Colors.black,
          ),
          dataModuleStyle: const QrDataModuleStyle(
            dataModuleShape: QrDataModuleShape.square,
            color: Colors.black,
          ),
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.text, required this.color});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Text(text, style: TextStyle(color: color, fontSize: 13)),
  );
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.1,
          color: context.mutedColor,
        ),
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}

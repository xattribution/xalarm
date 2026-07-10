import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sync_protocol/sync_protocol.dart';

import '../../core/theme/app_theme.dart';
import 'application/sync_controller.dart';

/// Pair with another xalarm user: pick a name, share codes, confirm, and the
/// timer + stopwatch stay in lockstep on both phones until someone leaves.
class SyncScreen extends ConsumerStatefulWidget {
  const SyncScreen({super.key});

  @override
  ConsumerState<SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends ConsumerState<SyncScreen> {
  final _name = TextEditingController();
  final _code = TextEditingController();
  Timer? _limboTick;

  @override
  void initState() {
    super.initState();
    _name.text = ref.read(syncProvider).myName;
  }

  @override
  void dispose() {
    _limboTick?.cancel();
    _name.dispose();
    _code.dispose();
    super.dispose();
  }

  void _ensureLimboTicker(bool inLimbo) {
    if (inLimbo && _limboTick == null) {
      _limboTick = Timer.periodic(const Duration(milliseconds: 200), (_) {
        if (mounted) setState(() {});
      });
    } else if (!inLimbo && _limboTick != null) {
      _limboTick?.cancel();
      _limboTick = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final sync = ref.watch(syncProvider);
    final controller = ref.read(syncProvider.notifier);
    final scheme = Theme.of(context).colorScheme;
    _ensureLimboTicker(sync.phase == SyncPhase.limbo);

    return Scaffold(
      appBar: AppBar(title: const Text('Time Sync')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
        children: [
          Text(
            'Share a live timer and stopwatch with one other person — either '
            'of you can start and stop, and both screens stay in lockstep.',
            style: TextStyle(color: context.mutedColor, fontSize: 13.5),
          ),
          const SizedBox(height: 20),
          if (sync.error != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: scheme.error.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                sync.error!,
                style: TextStyle(color: scheme.error, fontSize: 13),
              ),
            ),
            const SizedBox(height: 16),
          ],
          ...switch (sync.phase) {
            SyncPhase.idle => _idle(controller),
            SyncPhase.connecting => const [
              Center(child: CircularProgressIndicator()),
            ],
            SyncPhase.registered ||
            SyncPhase.outgoing => _registered(sync, controller),
            SyncPhase.incoming => _incoming(sync, controller),
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
    FilledButton(
      onPressed: () => controller.connect(_name.text),
      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
      child: const Text('Get my code'),
    ),
  ];

  List<Widget> _registered(SyncState sync, SyncController controller) => [
    const _SectionLabel('Your code'),
    _Panel(
      child: ListTile(
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
          '${sync.myName} — share this with your partner',
          style: TextStyle(color: context.mutedColor, fontSize: 12.5),
        ),
        trailing: IconButton(
          tooltip: 'Copy code',
          icon: const Icon(Icons.copy, size: 20),
          onPressed: () =>
              Clipboard.setData(ClipboardData(text: sync.myCode)),
        ),
      ),
    ),
    const SizedBox(height: 20),
    const _SectionLabel('Their code'),
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
            FilledButton(
              onPressed: sync.phase == SyncPhase.outgoing
                  ? null
                  : () => controller.requestPair(_code.text),
              child: Text(
                sync.phase == SyncPhase.outgoing ? 'Waiting…' : 'Connect',
              ),
            ),
          ],
        ),
      ),
    ),
    const SizedBox(height: 24),
    TextButton(
      onPressed: controller.disconnect,
      child: const Text('Leave'),
    ),
  ];

  List<Widget> _incoming(SyncState sync, SyncController controller) => [
    _Panel(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const Icon(Icons.link, size: 40),
            const SizedBox(height: 12),
            Text(
              '${sync.incomingName} wants to sync with you',
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              'Their code: ${PairCodes.pretty(sync.incomingCode)}',
              style: TextStyle(color: context.mutedColor, fontSize: 13),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: controller.declinePair,
                    child: const Text('Decline'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: controller.acceptPair,
                    child: const Text('Accept'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  ];

  List<Widget> _paired(SyncState sync, SyncController controller) => [
    _Panel(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Icon(Icons.link, size: 40,
                color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 12),
            Text(
              'Synced with ${sync.peerName}',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${PairCodes.pretty(sync.myCode)} (you)  ↔  '
              '${PairCodes.pretty(sync.peerCode)} (${sync.peerName})',
              style: TextStyle(color: context.mutedColor, fontSize: 12.5),
            ),
            const SizedBox(height: 8),
            Text(
              'The Timer and Stopwatch tabs are now shared — either of you '
              'can start and stop them.',
              textAlign: TextAlign.center,
              style: TextStyle(color: context.mutedColor, fontSize: 12.5),
            ),
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: controller.disconnect,
              icon: const Icon(Icons.link_off, size: 18),
              label: const Text('Disconnect'),
            ),
          ],
        ),
      ),
    ),
  ];

  List<Widget> _limbo(SyncState sync, SyncController controller) {
    final left = sync.limboDeadline
            ?.difference(DateTime.now())
            .inMilliseconds
            .clamp(0, 10000) ??
        0;
    return [
      _Panel(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              const Icon(Icons.link_off, size: 40),
              const SizedBox(height: 12),
              Text(
                'Connection with ${sync.peerName} interrupted',
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              Text(
                'Both of you must reconnect within '
                '${(left / 1000).toStringAsFixed(1)} s or the session is '
                'gone for good.',
                textAlign: TextAlign.center,
                style: TextStyle(color: context.mutedColor, fontSize: 13),
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: controller.reconnect,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Reconnect'),
              ),
            ],
          ),
        ),
      ),
    ];
  }
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

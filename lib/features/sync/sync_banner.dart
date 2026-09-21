import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import 'application/sync_controller.dart';
import 'sync_screen.dart';

/// The always-visible "you are connected" strip shown on the Stopwatch and
/// Timer tabs while a sync session exists. Tap to open the sync screen.
class SyncBanner extends ConsumerWidget {
  const SyncBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sync = ref.watch(syncProvider);
    if (!sync.showsBanner) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    final interrupted = sync.interrupted;
    final String title;
    if (sync.phase == SyncPhase.limbo) {
      title = 'Reconnecting…';
    } else if (!sync.hostConnected) {
      title = 'Host reconnecting — tap for details';
    } else {
      title = sync.peerSummary;
    }
    final String trailing;
    if (interrupted) {
      trailing = '';
    } else if (sync.isHost) {
      trailing = sync.membersCanControl ? 'hosting' : 'hosting · locked';
    } else if (sync.viewOnly) {
      trailing = 'view only';
    } else {
      trailing = 'shared timer & stopwatch';
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Material(
        color: interrupted
            ? scheme.error.withValues(alpha: 0.14)
            : scheme.primary.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const SyncScreen()),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                Icon(
                  interrupted
                      ? Icons.link_off
                      : (sync.viewOnly ? Icons.visibility : Icons.link),
                  size: 18,
                  color: interrupted ? scheme.error : scheme.primary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: interrupted ? scheme.error : scheme.primary,
                    ),
                  ),
                ),
                Text(
                  trailing,
                  style: TextStyle(fontSize: 11.5, color: context.mutedColor),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

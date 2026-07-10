import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

/// Requests the runtime permissions an alarm app needs on Android:
/// notifications (Android 13+) and exact-alarm scheduling (Android 12+).
class PermissionsService {
  const PermissionsService();

  /// Requests notification + exact-alarm permissions. Safe to call on any
  /// platform; only does work on Android.
  Future<void> requestAll() async {
    if (defaultTargetPlatform != TargetPlatform.android) return;

    if (!await Permission.notification.isGranted) {
      await Permission.notification.request();
    }
    // SCHEDULE_EXACT_ALARM — required for reliable exact firing on Android 12+.
    if (!await Permission.scheduleExactAlarm.isGranted) {
      await Permission.scheduleExactAlarm.request();
    }
  }

  Future<bool> hasNotificationPermission() async {
    if (defaultTargetPlatform != TargetPlatform.android) return true;
    return Permission.notification.isGranted;
  }

  Future<bool> hasExactAlarmPermission() async {
    if (defaultTargetPlatform != TargetPlatform.android) return true;
    return Permission.scheduleExactAlarm.isGranted;
  }
}

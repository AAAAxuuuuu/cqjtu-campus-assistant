import 'package:campus_platform/services/notification_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// `NotificationService.ensurePluginInitialized` used to call
/// `_plugin.initialize(settings)` with no `onDidReceiveNotificationResponse`,
/// and no reminder carried a payload. Tapping a class reminder or a low-balance
/// alert therefore just cold-opened the app on the first tab — while the
/// home-screen widget deep-link path (`WidgetNavigationService` →
/// `_handleWidgetTarget`) was already fully built. These tests pin the tap
/// routing contract, including the cold-start replay.
void main() {
  setUp(NotificationService.debugResetTapHandler);
  tearDown(NotificationService.debugResetTapHandler);

  group('notification tap routing', () {
    test('delivers a tap to the registered handler', () {
      final seen = <String>[];
      NotificationService.setTapHandler(seen.add);

      NotificationService.debugSimulateTap(notificationTargetSchedule);

      expect(seen, [notificationTargetSchedule]);
    });

    test('replays a tap that arrived before the UI registered', () {
      // Cold start: Android delivers the tap while Flutter is still booting,
      // so the handler does not exist yet.
      NotificationService.debugSimulateTap(notificationTargetElectricity);

      final seen = <String>[];
      NotificationService.setTapHandler(seen.add);

      expect(
        seen,
        [notificationTargetElectricity],
        reason: 'the pending target must be replayed on registration',
      );
    });

    test('replays only once', () {
      NotificationService.debugSimulateTap(notificationTargetCampusCard);

      final first = <String>[];
      NotificationService.setTapHandler(first.add);
      expect(first, hasLength(1));

      final second = <String>[];
      NotificationService.setTapHandler(second.add);
      expect(
        second,
        isEmpty,
        reason: 'a consumed target must not fire again for a later handler',
      );
    });

    test('routes every target the app schedules notifications for', () {
      final seen = <String>[];
      NotificationService.setTapHandler(seen.add);

      for (final target in [
        notificationTargetSchedule,
        notificationTargetElectricity,
        notificationTargetCampusCard,
        notificationTargetAppUpdate,
      ]) {
        NotificationService.debugSimulateTap(target);
      }

      expect(seen, [
        notificationTargetSchedule,
        notificationTargetElectricity,
        notificationTargetCampusCard,
        notificationTargetAppUpdate,
      ]);
    });

    test('targets match the widget deep-link vocabulary', () {
      // _handleWidgetTarget switches on these exact strings; a rename on either
      // side would silently fall through to the default (timetable) arm.
      expect(notificationTargetSchedule, 'schedule');
      expect(notificationTargetElectricity, 'electricity');
      expect(notificationTargetCampusCard, 'campus_card');
      expect(notificationTargetAppUpdate, 'app_update');
    });
  });
}

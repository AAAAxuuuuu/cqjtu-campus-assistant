import 'package:campus_platform/services/notification_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('course reminder preferences', () {
    test('defaults to enabled', () async {
      expect(await NotificationService.getCourseReminderEnabled(), isTrue);
    });

    test('defaults to 15 minutes', () async {
      expect(await NotificationService.getCourseReminderMinutes(), 15);
    });

    test('round-trips enabled flag per account', () async {
      await NotificationService.setCourseReminderEnabled(false, accountId: 'a');
      expect(await NotificationService.getCourseReminderEnabled(accountId: 'a'),
          isFalse);
      expect(await NotificationService.getCourseReminderEnabled(accountId: 'b'),
          isTrue);
    });

    test('clamps reminder minutes to the allowed range', () async {
      await NotificationService.setCourseReminderMinutes(5, accountId: 'a');
      expect(await NotificationService.getCourseReminderMinutes(accountId: 'a'),
          15);

      await NotificationService.setCourseReminderMinutes(120, accountId: 'a');
      expect(await NotificationService.getCourseReminderMinutes(accountId: 'a'),
          60);
    });

    test('migrates a legacy unscoped flag into the account-scoped key',
        () async {
      SharedPreferences.setMockInitialValues({'course_reminder': false});
      final value =
          await NotificationService.getCourseReminderEnabled(accountId: 'a');
      expect(value, isFalse);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('user_a_course_reminder'), isFalse);
      expect(prefs.containsKey('course_reminder'), isFalse,
          reason: 'legacy key is removed after migration');
    });

    test('migrates a legacy unscoped minutes value', () async {
      SharedPreferences.setMockInitialValues({'course_reminder_minutes': 30});
      expect(await NotificationService.getCourseReminderMinutes(accountId: 'a'),
          30);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('user_a_course_reminder_minutes'), 30);
      expect(prefs.containsKey('course_reminder_minutes'), isFalse);
    });

    test('accounts keep independent settings', () async {
      await NotificationService.setCourseReminderEnabled(false, accountId: 'a');
      await NotificationService.setCourseReminderEnabled(true, accountId: 'b');
      await NotificationService.setCourseReminderMinutes(30, accountId: 'a');
      await NotificationService.setCourseReminderMinutes(45, accountId: 'b');

      expect(await NotificationService.getCourseReminderEnabled(accountId: 'a'),
          isFalse);
      expect(await NotificationService.getCourseReminderEnabled(accountId: 'b'),
          isTrue);
      expect(await NotificationService.getCourseReminderMinutes(accountId: 'a'),
          30);
      expect(await NotificationService.getCourseReminderMinutes(accountId: 'b'),
          45);
    });
  });

  group('reminder coverage watermark and seed', () {
    test('no seed means no stale coverage and no replenish', () async {
      expect(await NotificationService.isReminderCoverageStale(), isFalse);
      expect(
        await NotificationService.replenishFromSeedIfNeeded(username: 'u'),
        isFalse,
      );
    });

    test('coverage is fresh right after the watermark is written', () async {
      // Simulate a scheduling run writing the watermark + seed.
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(
        'class_reminder_scheduled_until_ms',
        DateTime.now().add(const Duration(days: 14)).millisecondsSinceEpoch,
      );
      await prefs.setString(
        'class_reminder_seed_v1',
        '{"accountId":"u","semesterStartIso":"2026-06-01T00:00:00.000","totalWeeks":20,"calendarRules":{},"courses":[]}',
      );

      expect(await NotificationService.isReminderCoverageStale(), isFalse);
    });

    test('coverage becomes stale shortly before the window ends', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(
        'class_reminder_scheduled_until_ms',
        DateTime.now().add(const Duration(days: 1)).millisecondsSinceEpoch,
      );
      expect(await NotificationService.isReminderCoverageStale(), isTrue);
    });

    test('replenish skips seeds owned by another account', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(
        'class_reminder_scheduled_until_ms',
        DateTime.now().add(const Duration(days: 1)).millisecondsSinceEpoch,
      );
      await prefs.setString(
        'class_reminder_seed_v1',
        '{"accountId":"someone_else","semesterStartIso":"2026-06-01T00:00:00.000","totalWeeks":20,"calendarRules":{},"courses":[]}',
      );

      expect(
        await NotificationService.replenishFromSeedIfNeeded(username: 'u'),
        isFalse,
      );
    });

    test('replenish skips an empty seed', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(
        'class_reminder_scheduled_until_ms',
        DateTime.now().add(const Duration(days: 1)).millisecondsSinceEpoch,
      );
      await prefs.setString(
        'class_reminder_seed_v1',
        '{"accountId":"u","semesterStartIso":"2026-06-01T00:00:00.000","totalWeeks":20,"calendarRules":{},"courses":[]}',
      );

      expect(
        await NotificationService.replenishFromSeedIfNeeded(username: 'u'),
        isFalse,
      );
    });
  });
  group('reminder coverage watermark and seed', () {
    test('no seed means no stale coverage and no replenish', () async {
      expect(await NotificationService.isReminderCoverageStale(), isFalse);
      expect(
        await NotificationService.replenishFromSeedIfNeeded(username: 'u'),
        isFalse,
      );
    });

    test('coverage is fresh right after the watermark is written', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(
        'class_reminder_scheduled_until_ms',
        DateTime.now().add(const Duration(days: 14)).millisecondsSinceEpoch,
      );
      await prefs.setString(
        'class_reminder_seed_v1',
        '{"accountId":"u","semesterStartIso":"2026-06-01T00:00:00.000","totalWeeks":20,"calendarRules":{},"courses":[]}',
      );

      expect(await NotificationService.isReminderCoverageStale(), isFalse);
    });

    test('coverage becomes stale shortly before the window ends', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(
        'class_reminder_scheduled_until_ms',
        DateTime.now().add(const Duration(days: 1)).millisecondsSinceEpoch,
      );
      expect(await NotificationService.isReminderCoverageStale(), isTrue);
    });

    test('replenish skips seeds owned by another account', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(
        'class_reminder_scheduled_until_ms',
        DateTime.now().add(const Duration(days: 1)).millisecondsSinceEpoch,
      );
      await prefs.setString(
        'class_reminder_seed_v1',
        '{"accountId":"someone_else","semesterStartIso":"2026-06-01T00:00:00.000","totalWeeks":20,"calendarRules":{},"courses":[]}',
      );

      expect(
        await NotificationService.replenishFromSeedIfNeeded(username: 'u'),
        isFalse,
      );
    });

    test('replenish skips an empty seed', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(
        'class_reminder_scheduled_until_ms',
        DateTime.now().add(const Duration(days: 1)).millisecondsSinceEpoch,
      );
      await prefs.setString(
        'class_reminder_seed_v1',
        '{"accountId":"u","semesterStartIso":"2026-06-01T00:00:00.000","totalWeeks":20,"calendarRules":{},"courses":[]}',
      );

      expect(
        await NotificationService.replenishFromSeedIfNeeded(username: 'u'),
        isFalse,
      );
    });
  });

  group('threshold preferences', () {
    test('defaults for electricity and campus card', () async {
      expect(await NotificationService.getElecThreshold(), 10.0);
      expect(await NotificationService.getCardThreshold(), 20.0);
    });

    test('round-trips custom thresholds', () async {
      await NotificationService.setElecThreshold(12.5);
      await NotificationService.setCardThreshold(25.0);
      expect(await NotificationService.getElecThreshold(), 12.5);
      expect(await NotificationService.getCardThreshold(), 25.0);
    });
  });
}

import 'dart:convert';

import 'package:campus_platform/services/notification_service.dart';
import 'package:core/models/course.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const reminderChannel = MethodChannel('campus_app/class_reminder');
  const localNotificationsChannel = MethodChannel(
    'dexterous.com/flutter/local_notifications',
  );
  late List<MethodCall> channelCalls;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    channelCalls = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(reminderChannel, (call) async {
      channelCalls.add(call);
      return null;
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(localNotificationsChannel, (call) async {
      return true;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(reminderChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(localNotificationsChannel, null);
  });

  Course futureCourse() {
    final now = DateTime.now();
    final lateToday = now.hour >= 20 && now.minute >= 15;
    final day = lateToday ? (now.weekday % 7) + 1 : now.weekday;
    final slot = lateToday ? 1 : 13;
    return Course(
      name: '测试课',
      teacher: '',
      timeStr: '',
      classroom: 'A101',
      dayOfWeek: day,
      timeSlot: slot,
      endTimeSlot: slot,
      weekList: [1],
    );
  }

  group('class reminder delivery channels', () {
    test('scheduleClassReminders invokes the native channel and persists seed',
        () async {
      final semesterStart = DateTime.now().subtract(
        Duration(days: DateTime.now().weekday - 1),
      );

      await NotificationService.scheduleClassReminders(
        [futureCourse()],
        semesterStart,
        accountId: 'u',
      );

      final scheduleCalls =
          channelCalls.where((call) => call.method == 'scheduleClassReminders');
      expect(scheduleCalls, hasLength(1), reason: 'native channel invoked');

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('class_reminder_scheduled_until_ms'), isNotNull);
      final seed = prefs.getString('class_reminder_seed_v1');
      expect(seed, isNotNull);
      final decoded = jsonDecode(seed!);
      expect((decoded as Map)['accountId'], 'u');
    });

    test('cancelAllClassReminders invokes cancel and clears the seed',
        () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'class_reminder_seed_v1',
        '{"accountId":"u","semesterStartIso":"2026-06-01T00:00:00.000","totalWeeks":20,"calendarRules":{},"courses":[]}',
      );
      await prefs.setInt('class_reminder_scheduled_until_ms', 1);

      await NotificationService.cancelAllClassReminders();

      expect(
        channelCalls.where((call) => call.method == 'cancelClassReminders'),
        hasLength(1),
      );
      expect(prefs.getString('class_reminder_seed_v1'), isNull);
      expect(prefs.getInt('class_reminder_scheduled_until_ms'), isNull);
    });

    test(
      'replenishFromSeedIfNeeded reschedules without a prior init() '
      '(background isolate path)',
      () async {
        final semesterStart = DateTime.now().subtract(
          Duration(days: DateTime.now().weekday - 1),
        );
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt(
          'class_reminder_scheduled_until_ms',
          DateTime.now().add(const Duration(days: 1)).millisecondsSinceEpoch,
        );
        await prefs.setString(
          'class_reminder_seed_v1',
          jsonEncode({
            'accountId': 'u',
            'semesterStartIso': semesterStart.toIso8601String(),
            'totalWeeks': 20,
            'calendarRules': const {},
            'courses': [futureCourse().toJson()],
          }),
        );

        // No init() call happened in this test isolate: the replenish path
        // must lazily set up the timezone database and plugin by itself.
        final replenished = await NotificationService.replenishFromSeedIfNeeded(
          username: 'u',
        );

        expect(replenished, isTrue);
        expect(
          channelCalls.where((call) => call.method == 'scheduleClassReminders'),
          hasLength(1),
          reason: 'rescheduled through the native channel',
        );
        final updatedUntil = prefs.getInt('class_reminder_scheduled_until_ms')!;
        expect(
          updatedUntil,
          greaterThan(DateTime.now().millisecondsSinceEpoch),
          reason: 'coverage watermark refreshed',
        );
      },
    );
  });
}

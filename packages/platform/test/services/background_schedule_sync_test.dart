import 'dart:convert';

import 'package:campus_platform/services/background_task.dart';
import 'package:campus_platform/services/session_service.dart';
import 'package:core/models/course.dart';
import 'package:core/utils/resource_cache_key.dart';
import 'package:data/data.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MockScheduleGateway extends DirectSchoolCampusGateway {
  MockScheduleGateway({
    this.scheduleHandler,
    this.elecHandler,
    this.cardHandler,
    super.sessionStore,
  });

  Future<({List<Course> courses, String remark})> Function(
    String username,
    String password, {
    String? semester,
    bool forceRefresh,
  })? scheduleHandler;

  Future<String> Function(
    String username,
    String password, {
    bool forceRefresh,
    Map<String, String>? dormParams,
  })? elecHandler;

  Future<String> Function(
    String username,
    String password, {
    bool forceRefresh,
  })? cardHandler;

  int scheduleCallCount = 0;
  String? lastUsername;
  String? lastPassword;
  String? lastSemester;

  @override
  Future<({List<Course> courses, String remark})> getSchedule(
    String username,
    String password, {
    String? semester,
    bool forceRefresh = false,
  }) async {
    scheduleCallCount++;
    lastUsername = username;
    lastPassword = password;
    lastSemester = semester;
    if (scheduleHandler != null) {
      return scheduleHandler!(
        username,
        password,
        semester: semester,
        forceRefresh: forceRefresh,
      );
    }
    return (courses: const <Course>[], remark: '');
  }

  @override
  Future<String> getElecBalance(
    String username,
    String password, {
    bool forceRefresh = false,
    Map<String, String>? dormParams,
  }) async {
    if (elecHandler != null) {
      return elecHandler!(
        username,
        password,
        forceRefresh: forceRefresh,
        dormParams: dormParams,
      );
    }
    return '18.50';
  }

  @override
  Future<String> getCampusCardBalance(
    String username,
    String password, {
    bool forceRefresh = false,
  }) async {
    if (cardHandler != null) {
      return cardHandler!(
        username,
        password,
        forceRefresh: forceRefresh,
      );
    }
    return '52.00';
  }
}

Course createTestCourse({
  String name = '高等数学',
  String classroom = 'A101',
  int dayOfWeek = 1,
  int timeSlot = 1,
  int endTimeSlot = 2,
  List<int> weekList = const [1, 2, 3, 4],
}) {
  return Course(
    name: name,
    teacher: '张老师',
    timeStr: '1-2节',
    classroom: classroom,
    dayOfWeek: dayOfWeek,
    timeSlot: timeSlot,
    endTimeSlot: endTimeSlot,
    weekList: weekList,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const widgetChannel = MethodChannel('campus_app/schedule_widget');
  const reminderChannel = MethodChannel('campus_app/class_reminder');
  const localNotificationsChannel = MethodChannel(
    'dexterous.com/flutter/local_notifications',
  );

  final widgetChannelCalls = <MethodCall>[];
  final reminderChannelCalls = <MethodCall>[];

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    widgetChannelCalls.clear();
    reminderChannelCalls.clear();

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(widgetChannel, (call) async {
      widgetChannelCalls.add(call);
      return null;
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(reminderChannel, (call) async {
      reminderChannelCalls.add(call);
      return null;
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(localNotificationsChannel, (call) async {
      return true;
    });
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(widgetChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(reminderChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(localNotificationsChannel, null);
  });

  group('Background Schedule Sync Integration (R2 & R3)', () {
    test('performs schedule sync and writes ResourceCacheStore format',
        () async {
      final prefs = await SharedPreferences.getInstance();
      final now = DateTime(2026, 9, 19, 10, 0, 0);
      final course1 = createTestCourse(name: '微积分');
      final course2 = createTestCourse(name: '大学物理', dayOfWeek: 2);

      final gateway = MockScheduleGateway(
        scheduleHandler: (username, password,
            {semester, forceRefresh = false}) async {
          return (courses: [course1, course2], remark: '开学第3周');
        },
      );

      final result = await runBackgroundScheduleSync(
        prefs: prefs,
        username: 'u2026',
        password: 'pwd',
        semester: '2026-2027-1',
        gateway: gateway,
        now: now,
      );

      expect(result, isTrue);
      expect(gateway.scheduleCallCount, 1);
      expect(gateway.lastSemester, '2026-2027-1');

      // Verify ResourceCacheStore format in SharedPreferences
      final cacheKey =
          resourceCacheKey('schedule', username: 'u2026', scope: '2026-2027-1');
      final cachedRaw = prefs.getString(cacheKey);
      expect(cachedRaw, isNotNull);

      final decoded = jsonDecode(cachedRaw!) as Map<String, dynamic>;
      expect(decoded['updatedAtMs'], now.millisecondsSinceEpoch);
      final data = decoded['data'] as Map<String, dynamic>;
      expect(data['remark'], '开学第3周');
      final coursesJson = data['courses'] as List<dynamic>;
      expect(coursesJson.length, 2);
      expect(coursesJson[0]['name'], '微积分');
      expect(coursesJson[1]['name'], '大学物理');

      // Verify sync timestamps recorded
      expect(prefs.getInt('bg_schedule_last_sync_ms_u2026'),
          now.millisecondsSinceEpoch);
      expect(prefs.getInt('bg_schedule_checked_at_ms'),
          now.millisecondsSinceEpoch);

      // Verify widget channel was invoked
      final widgetCalls = widgetChannelCalls
          .where((call) => call.method == 'updateScheduleWidgets')
          .toList();
      expect(widgetCalls, hasLength(1));
      final widgetArgs = widgetCalls.first.arguments as Map<dynamic, dynamic>;
      expect(widgetArgs['selectedSemester'], '2026-2027-1');
      expect(widgetArgs['remark'], '开学第3周');
      expect((widgetArgs['courses'] as List).any((c) => c['name'] == '微积分'),
          isTrue);
      expect((widgetArgs['courses'] as List).any((c) => c['name'] == '大学物理'),
          isTrue);

      // Verify reminder channel was invoked and seed was persisted
      final reminderCalls = reminderChannelCalls
          .where((call) => call.method == 'scheduleClassReminders')
          .toList();
      expect(reminderCalls, hasLength(1));
      final seedJson = prefs.getString('class_reminder_seed_v1');
      expect(seedJson, isNotNull);
      expect(seedJson, contains('微积分'));
    });

    test(
        '2-hour freshness window skips network sync when cache was updated within 2 hours',
        () async {
      final prefs = await SharedPreferences.getInstance();
      final baseTime = DateTime(2026, 9, 19, 12, 0, 0);

      // Pre-populate cache updated 90 minutes ago (within 2-hour freshness window)
      final cacheKey =
          resourceCacheKey('schedule', username: 'u2026', scope: '2026-2027-1');
      final updatedAt = baseTime.subtract(const Duration(minutes: 90));
      await prefs.setString(
        cacheKey,
        jsonEncode({
          'updatedAtMs': updatedAt.millisecondsSinceEpoch,
          'data': {
            'courses': [createTestCourse().toJson()],
            'remark': '已有缓存',
          },
        }),
      );

      final gateway = MockScheduleGateway();

      final result = await runBackgroundScheduleSync(
        prefs: prefs,
        username: 'u2026',
        password: 'pwd',
        semester: '2026-2027-1',
        gateway: gateway,
        now: baseTime,
      );

      expect(result, isFalse, reason: 'freshness window should skip sync');
      expect(gateway.scheduleCallCount, 0,
          reason: 'no network request should be sent');
    });

    test(
        '2-hour freshness window skips network sync when bg_schedule_last_sync_ms was updated within 2 hours',
        () async {
      final prefs = await SharedPreferences.getInstance();
      final baseTime = DateTime(2026, 9, 19, 14, 0, 0);

      // Recorded sync 45 minutes ago
      await prefs.setInt(
        'bg_schedule_last_sync_ms_u2026',
        baseTime.subtract(const Duration(minutes: 45)).millisecondsSinceEpoch,
      );

      final gateway = MockScheduleGateway();

      final result = await runBackgroundScheduleSync(
        prefs: prefs,
        username: 'u2026',
        password: 'pwd',
        semester: '2026-2027-1',
        gateway: gateway,
        now: baseTime,
      );

      expect(result, isFalse);
      expect(gateway.scheduleCallCount, 0);
    });

    test('proceeds with network sync when cache is older than 2 hours',
        () async {
      final prefs = await SharedPreferences.getInstance();
      final baseTime = DateTime(2026, 9, 19, 14, 0, 0);

      // Pre-populate cache updated 2 hours and 10 minutes ago (expired freshness)
      final cacheKey =
          resourceCacheKey('schedule', username: 'u2026', scope: '2026-2027-1');
      final updatedAt =
          baseTime.subtract(const Duration(hours: 2, minutes: 10));
      await prefs.setString(
        cacheKey,
        jsonEncode({
          'updatedAtMs': updatedAt.millisecondsSinceEpoch,
          'data': {
            'courses': [createTestCourse(name: '旧课程').toJson()],
            'remark': '旧数据',
          },
        }),
      );

      final gateway = MockScheduleGateway(
        scheduleHandler: (username, password,
            {semester, forceRefresh = false}) async {
          return (courses: [createTestCourse(name: '新课程')], remark: '已刷新');
        },
      );

      final result = await runBackgroundScheduleSync(
        prefs: prefs,
        username: 'u2026',
        password: 'pwd',
        semester: '2026-2027-1',
        gateway: gateway,
        now: baseTime,
      );

      expect(result, isTrue);
      expect(gateway.scheduleCallCount, 1);

      final updatedRaw = prefs.getString(cacheKey)!;
      final decoded = jsonDecode(updatedRaw) as Map<String, dynamic>;
      expect(decoded['updatedAtMs'], baseTime.millisecondsSinceEpoch);
      final courses = (decoded['data'] as Map)['courses'] as List<dynamic>;
      expect(courses[0]['name'], '新课程');
    });

    test(
        'auto-login rate limiting blocks background sync on 7th attempt within 1 hour',
        () async {
      final prefs = await SharedPreferences.getInstance();
      final sessionService = SessionService();
      final baseTime = DateTime(2026, 9, 19, 15, 0, 0);

      // Record 6 attempts within the past 50 minutes (spaced by 8 minutes to satisfy minInterval)
      for (var i = 0; i < 6; i++) {
        await sessionService.recordAutoLoginAttempt(
          'u2026',
          now: baseTime.subtract(Duration(minutes: 50 - i * 8)),
        );
      }

      expect(await sessionService.canAttemptAutoLogin('u2026', now: baseTime),
          isFalse);

      final gateway = MockScheduleGateway();

      final result = await runBackgroundScheduleSync(
        prefs: prefs,
        username: 'u2026',
        password: 'pwd',
        semester: '2026-2027-1',
        gateway: gateway,
        sessionService: sessionService,
        now: baseTime,
      );

      expect(result, isFalse, reason: 'rate limiter must block 7th attempt');
      expect(gateway.scheduleCallCount, 0,
          reason: 'no network request should be sent');
    });

    test(
        'auto-login rate limiting allows sync when fewer than 6 attempts recorded and interval elapsed',
        () async {
      final prefs = await SharedPreferences.getInstance();
      final sessionService = SessionService();
      final baseTime = DateTime(2026, 9, 19, 15, 0, 0);

      // Record 5 attempts within the past 50 minutes (quota is 6)
      for (var i = 0; i < 5; i++) {
        await sessionService.recordAutoLoginAttempt(
          'u2026',
          now: baseTime.subtract(Duration(minutes: 50 - i * 8)),
        );
      }

      expect(await sessionService.canAttemptAutoLogin('u2026', now: baseTime),
          isTrue);

      final gateway = MockScheduleGateway(
        scheduleHandler: (username, password,
            {semester, forceRefresh = false}) async {
          return (courses: [createTestCourse()], remark: '成功获取');
        },
      );

      final result = await runBackgroundScheduleSync(
        prefs: prefs,
        username: 'u2026',
        password: 'pwd',
        semester: '2026-2027-1',
        gateway: gateway,
        sessionService: sessionService,
        now: baseTime,
      );

      expect(result, isTrue);
      expect(gateway.scheduleCallCount, 1);
    });

    test(
        'runLocalAndroidBalanceChecks blocks and skips all checks when auto-login rate limited (F5)',
        () async {
      final prefs = await SharedPreferences.getInstance();
      final plugin = FlutterLocalNotificationsPlugin();
      final sessionService = SessionService();
      final baseTime = DateTime(2026, 9, 19, 15, 0, 0);
      const testUser = 'u2026_balance_rl';

      // Pre-fill 6 attempts to exhaust rate limit
      for (var i = 0; i < 6; i++) {
        await sessionService.recordAutoLoginAttempt(
          testUser,
          now: baseTime.subtract(Duration(minutes: 50 - i * 8)),
        );
      }
      expect(await sessionService.canAttemptAutoLogin(testUser, now: baseTime),
          isFalse);

      var elecCalled = false;
      var cardCalled = false;
      final gateway = MockScheduleGateway(
        elecHandler: (u, p, {dormParams, forceRefresh = false}) async {
          elecCalled = true;
          return '10.00';
        },
        cardHandler: (u, p, {forceRefresh = false}) async {
          cardCalled = true;
          return '20.00';
        },
        sessionStore: sessionService,
      );

      final balanceSuccess = await runLocalAndroidBalanceChecks(
        prefs: prefs,
        plugin: plugin,
        username: testUser,
        password: 'pwd',
        elecThreshold: 5.0,
        cardThreshold: 5.0,
        dormParams: {'buildid': 'B1', 'roomid': '101'},
        sessionService: sessionService,
        gateway: gateway,
        now: baseTime,
      );

      expect(balanceSuccess, isFalse);
      expect(elecCalled, isFalse,
          reason: 'elec check must be skipped at front gate');
      expect(cardCalled, isFalse,
          reason: 'card check must be skipped at front gate');
    });

    test(
        'defensive cache check prevents overwriting existing non-empty cache with empty remote response',
        () async {
      final prefs = await SharedPreferences.getInstance();
      final baseTime = DateTime(2026, 9, 19, 16, 0, 0);
      final cacheKey =
          resourceCacheKey('schedule', username: 'u2026', scope: '2026-2027-1');

      // Pre-existing non-empty schedule cache
      final existingCourse = createTestCourse(name: '重要既有课程');
      final originalPayload = jsonEncode({
        'updatedAtMs':
            baseTime.subtract(const Duration(hours: 3)).millisecondsSinceEpoch,
        'data': {
          'courses': [existingCourse.toJson()],
          'remark': '原始课表',
        },
      });
      await prefs.setString(cacheKey, originalPayload);

      // Remote server returns empty courses
      final gateway = MockScheduleGateway(
        scheduleHandler: (username, password,
            {semester, forceRefresh = false}) async {
          return (courses: const <Course>[], remark: '');
        },
      );

      final result = await runBackgroundScheduleSync(
        prefs: prefs,
        username: 'u2026',
        password: 'pwd',
        semester: '2026-2027-1',
        gateway: gateway,
        now: baseTime,
      );

      expect(result, isFalse,
          reason: 'empty remote schedule blocked from wiping cache');
      expect(gateway.scheduleCallCount, 1);

      // Verify existing cache is untouched
      final afterRaw = prefs.getString(cacheKey);
      expect(afterRaw, equals(originalPayload));

      final decoded = jsonDecode(afterRaw!) as Map<String, dynamic>;
      final courses = (decoded['data'] as Map)['courses'] as List;
      expect(courses, hasLength(1));
      expect(courses.first['name'], '重要既有课程');

      // Verify widgets were NOT updated with empty list
      expect(
          widgetChannelCalls
              .where((call) => call.method == 'updateScheduleWidgets'),
          isEmpty);
    });

    test(
        'empty remote response DOES write cache when existing cache is empty or absent',
        () async {
      final prefs = await SharedPreferences.getInstance();
      final baseTime = DateTime(2026, 9, 19, 16, 0, 0);
      final cacheKey =
          resourceCacheKey('schedule', username: 'u2026', scope: '2026-2027-1');

      final gateway = MockScheduleGateway(
        scheduleHandler: (username, password,
            {semester, forceRefresh = false}) async {
          return (courses: const <Course>[], remark: '假期无课');
        },
      );

      final result = await runBackgroundScheduleSync(
        prefs: prefs,
        username: 'u2026',
        password: 'pwd',
        semester: '2026-2027-1',
        gateway: gateway,
        now: baseTime,
      );

      expect(result, isTrue);
      expect(gateway.scheduleCallCount, 1);

      final afterRaw = prefs.getString(cacheKey);
      expect(afterRaw, isNotNull);
      final decoded = jsonDecode(afterRaw!) as Map<String, dynamic>;
      expect((decoded['data'] as Map)['remark'], '假期无课');
      expect((decoded['data'] as Map)['courses'], isEmpty);
    });

    test(
        'silent error handling: catches BotChallengeFailure silently without clearing cache or throwing',
        () async {
      final prefs = await SharedPreferences.getInstance();
      final baseTime = DateTime(2026, 9, 19, 17, 0, 0);
      final cacheKey =
          resourceCacheKey('schedule', username: 'u2026', scope: '2026-2027-1');

      final existingPayload = jsonEncode({
        'updatedAtMs':
            baseTime.subtract(const Duration(hours: 4)).millisecondsSinceEpoch,
        'data': {
          'courses': [createTestCourse().toJson()],
          'remark': '初始课表',
        },
      });
      await prefs.setString(cacheKey, existingPayload);

      final gateway = MockScheduleGateway(
        scheduleHandler: (username, password,
            {semester, forceRefresh = false}) async {
          throw const BotChallengeFailure('教务系统开启了人机验证，请使用网页登录完成验证');
        },
      );

      final result = await runBackgroundScheduleSync(
        prefs: prefs,
        username: 'u2026',
        password: 'pwd',
        semester: '2026-2027-1',
        gateway: gateway,
        now: baseTime,
      );

      expect(result, isFalse);
      expect(prefs.getString(cacheKey), equals(existingPayload));
    });

    test(
        'silent error handling: catches CaptchaRequiredFailure silently without clearing cache or throwing',
        () async {
      final prefs = await SharedPreferences.getInstance();
      final baseTime = DateTime(2026, 9, 19, 17, 0, 0);
      final cacheKey =
          resourceCacheKey('schedule', username: 'u2026', scope: '2026-2027-1');

      final existingPayload = jsonEncode({
        'updatedAtMs':
            baseTime.subtract(const Duration(hours: 4)).millisecondsSinceEpoch,
        'data': {
          'courses': [createTestCourse().toJson()],
          'remark': '初始课表',
        },
      });
      await prefs.setString(cacheKey, existingPayload);

      final gateway = MockScheduleGateway(
        scheduleHandler: (username, password,
            {semester, forceRefresh = false}) async {
          throw const CaptchaRequiredFailure('教务系统需要安全验证');
        },
      );

      final result = await runBackgroundScheduleSync(
        prefs: prefs,
        username: 'u2026',
        password: 'pwd',
        semester: '2026-2027-1',
        gateway: gateway,
        now: baseTime,
      );

      expect(result, isFalse);
      expect(prefs.getString(cacheKey), equals(existingPayload));
    });

    test(
        'silent error handling: catches SessionExpiredFailure silently without clearing cache or throwing',
        () async {
      final prefs = await SharedPreferences.getInstance();
      final baseTime = DateTime(2026, 9, 19, 17, 0, 0);
      final cacheKey =
          resourceCacheKey('schedule', username: 'u2026', scope: '2026-2027-1');

      final existingPayload = jsonEncode({
        'updatedAtMs':
            baseTime.subtract(const Duration(hours: 4)).millisecondsSinceEpoch,
        'data': {
          'courses': [createTestCourse().toJson()],
          'remark': '初始课表',
        },
      });
      await prefs.setString(cacheKey, existingPayload);

      final gateway = MockScheduleGateway(
        scheduleHandler: (username, password,
            {semester, forceRefresh = false}) async {
          throw const SessionExpiredFailure('教务会话已过期');
        },
      );

      final result = await runBackgroundScheduleSync(
        prefs: prefs,
        username: 'u2026',
        password: 'pwd',
        semester: '2026-2027-1',
        gateway: gateway,
        now: baseTime,
      );

      expect(result, isFalse);
      expect(prefs.getString(cacheKey), equals(existingPayload));
    });

    test(
        'silent error handling: catches DioException / network error silently without clearing cache or throwing',
        () async {
      final prefs = await SharedPreferences.getInstance();
      final baseTime = DateTime(2026, 9, 19, 17, 0, 0);
      final cacheKey =
          resourceCacheKey('schedule', username: 'u2026', scope: '2026-2027-1');

      final existingPayload = jsonEncode({
        'updatedAtMs':
            baseTime.subtract(const Duration(hours: 4)).millisecondsSinceEpoch,
        'data': {
          'courses': [createTestCourse().toJson()],
          'remark': '初始课表',
        },
      });
      await prefs.setString(cacheKey, existingPayload);

      final gateway = MockScheduleGateway(
        scheduleHandler: (username, password,
            {semester, forceRefresh = false}) async {
          throw DioException(
            requestOptions: RequestOptions(path: '/schedule'),
            type: DioExceptionType.connectionTimeout,
          );
        },
      );

      final result = await runBackgroundScheduleSync(
        prefs: prefs,
        username: 'u2026',
        password: 'pwd',
        semester: '2026-2027-1',
        gateway: gateway,
        now: baseTime,
      );

      expect(result, isFalse);
      expect(prefs.getString(cacheKey), equals(existingPayload));
    });

    test(
        'silent error handling: catches SchoolSystemChangedFailure silently without clearing cache or throwing',
        () async {
      final prefs = await SharedPreferences.getInstance();
      final baseTime = DateTime(2026, 9, 19, 17, 0, 0);
      final cacheKey =
          resourceCacheKey('schedule', username: 'u2026', scope: '2026-2027-1');

      final existingPayload = jsonEncode({
        'updatedAtMs':
            baseTime.subtract(const Duration(hours: 4)).millisecondsSinceEpoch,
        'data': {
          'courses': [createTestCourse().toJson()],
          'remark': '初始课表',
        },
      });
      await prefs.setString(cacheKey, existingPayload);

      final gateway = MockScheduleGateway(
        scheduleHandler: (username, password,
            {semester, forceRefresh = false}) async {
          throw const SchoolSystemChangedFailure('未在响应中找到课程表结构(#timetable)');
        },
      );

      final result = await runBackgroundScheduleSync(
        prefs: prefs,
        username: 'u2026',
        password: 'pwd',
        semester: '2026-2027-1',
        gateway: gateway,
        now: baseTime,
      );

      expect(result, isFalse);
      expect(prefs.getString(cacheKey), equals(existingPayload));
    });

    test(
        'silent error handling: catches arbitrary unexpected exception silently without clearing cache or throwing',
        () async {
      final prefs = await SharedPreferences.getInstance();
      final baseTime = DateTime(2026, 9, 19, 17, 0, 0);
      final cacheKey =
          resourceCacheKey('schedule', username: 'u2026', scope: '2026-2027-1');

      final existingPayload = jsonEncode({
        'updatedAtMs':
            baseTime.subtract(const Duration(hours: 4)).millisecondsSinceEpoch,
        'data': {
          'courses': [createTestCourse().toJson()],
          'remark': '初始课表',
        },
      });
      await prefs.setString(cacheKey, existingPayload);

      final gateway = MockScheduleGateway(
        scheduleHandler: (username, password,
            {semester, forceRefresh = false}) async {
          throw Exception('Unknown socket or memory failure');
        },
      );

      final result = await runBackgroundScheduleSync(
        prefs: prefs,
        username: 'u2026',
        password: 'pwd',
        semester: '2026-2027-1',
        gateway: gateway,
        now: baseTime,
      );

      expect(result, isFalse);
      expect(prefs.getString(cacheKey), equals(existingPayload));
    });

    test(
        'preserves custom courses and merges them into cache and widget updates',
        () async {
      final prefs = await SharedPreferences.getInstance();
      final baseTime = DateTime(2026, 9, 19, 18, 0, 0);

      // Save custom course in SharedPreferences
      final customCourse = createTestCourse(name: '自习课程', dayOfWeek: 5);
      await prefs.setString(
        'user_u2026_custom_courses_2026-2027-1',
        jsonEncode([customCourse.toJson()]),
      );

      final schoolCourse = createTestCourse(name: '大学英语');
      final gateway = MockScheduleGateway(
        scheduleHandler: (username, password,
            {semester, forceRefresh = false}) async {
          return (courses: [schoolCourse], remark: '正常');
        },
      );

      final result = await runBackgroundScheduleSync(
        prefs: prefs,
        username: 'u2026',
        password: 'pwd',
        semester: '2026-2027-1',
        gateway: gateway,
        now: baseTime,
      );

      expect(result, isTrue);

      final cacheKey =
          resourceCacheKey('schedule', username: 'u2026', scope: '2026-2027-1');
      final cachedRaw = prefs.getString(cacheKey)!;
      final decoded = jsonDecode(cachedRaw) as Map<String, dynamic>;
      final courses = (decoded['data'] as Map)['courses'] as List<dynamic>;

      expect(courses, hasLength(2));
      expect(courses.any((c) => c['name'] == '大学英语'), isTrue);
      expect(courses.any((c) => c['name'] == '自习课程' && c['isCustom'] == true),
          isTrue);

      // Verify widgets received both courses
      final widgetCall = widgetChannelCalls
          .lastWhere((call) => call.method == 'updateScheduleWidgets');
      final widgetCourses = (widgetCall.arguments as Map)['courses'] as List;
      expect(widgetCourses.any((c) => c['name'] == '大学英语'), isTrue);
      expect(widgetCourses.any((c) => c['name'] == '自习课程'), isTrue);
    });

    test('resolves saved semester parameters from SharedPreferences', () async {
      final prefs = await SharedPreferences.getInstance();
      final baseTime = DateTime(2026, 9, 19, 19, 0, 0);

      // Configure selected semester and specific semester start
      await prefs.setString('user_u2026_selected_semester_str', '2026-2027-2');
      await prefs.setString(
        'user_u2026_semester_start_key_2026-2027-2',
        '2027-02-22T00:00:00.000',
      );
      await prefs.setInt('user_u2026_semester_total_weeks_2026-2027-2', 18);

      final gateway = MockScheduleGateway(
        scheduleHandler: (username, password,
            {semester, forceRefresh = false}) async {
          return (courses: [createTestCourse()], remark: '下半学期');
        },
      );

      final result = await runBackgroundScheduleSync(
        prefs: prefs,
        username: 'u2026',
        password: 'pwd',
        gateway: gateway,
        now: baseTime,
      );

      expect(result, isTrue);
      expect(gateway.lastSemester, '2026-2027-2');

      final widgetCall = widgetChannelCalls
          .lastWhere((call) => call.method == 'updateScheduleWidgets');
      final widgetArgs = widgetCall.arguments as Map;
      expect(widgetArgs['selectedSemester'], '2026-2027-2');
      expect(widgetArgs['totalWeeks'], 18);
      expect(
        widgetArgs['semesterStartMillis'],
        DateTime.parse('2027-02-22T00:00:00.000').millisecondsSinceEpoch,
      );
    });

    test(
        'falls back to calculated semester start when not configured in SharedPreferences',
        () async {
      final prefs = await SharedPreferences.getInstance();
      final now = DateTime(2026, 9, 19, 20, 0, 0);

      final gateway = MockScheduleGateway(
        scheduleHandler: (username, password,
            {semester, forceRefresh = false}) async {
          return (courses: [createTestCourse()], remark: '');
        },
      );

      final result = await runBackgroundScheduleSync(
        prefs: prefs,
        username: 'u2026',
        password: 'pwd',
        semester: '2026-2027-1',
        gateway: gateway,
        now: now,
      );

      expect(result, isTrue);

      final widgetCall = widgetChannelCalls
          .lastWhere((call) => call.method == 'updateScheduleWidgets');
      final widgetArgs = widgetCall.arguments as Map;
      // Fallback for 2026-2027-1 is 2026-09-01
      expect(
        widgetArgs['semesterStartMillis'],
        DateTime(2026, 9, 1).millisecondsSinceEpoch,
      );
    });

    test(
        'runLocalAndroidBalanceChecks injects sessionService into gateway and backfills caches',
        () async {
      final prefs = await SharedPreferences.getInstance();
      final sessionService = SessionService();
      final plugin = FlutterLocalNotificationsPlugin();

      final gateway = MockScheduleGateway(
        elecHandler: (username, password,
            {dormParams, forceRefresh = false}) async {
          return '24.50';
        },
        cardHandler: (username, password, {forceRefresh = false}) async {
          return '78.20';
        },
        sessionStore: sessionService,
      );

      await runLocalAndroidBalanceChecks(
        prefs: prefs,
        plugin: plugin,
        username: 'u2026',
        password: 'pwd',
        elecThreshold: 10.0,
        cardThreshold: 20.0,
        dormParams: {'buildid': 'B2', 'roomid': '302'},
        sessionService: sessionService,
        gateway: gateway,
      );

      final elecKey = resourceCacheKey('electricity_balance',
          username: 'u2026', scope: 'B2:302');
      final elecRaw = prefs.getString(elecKey);
      expect(elecRaw, isNotNull);
      final elecData = jsonDecode(elecRaw!) as Map<String, dynamic>;
      expect(elecData['data'], '24.50');

      final cardKey = resourceCacheKey('campus_card_balance',
          username: 'u2026', scope: null);
      final cardRaw = prefs.getString(cardKey);
      expect(cardRaw, isNotNull);
      final cardData = jsonDecode(cardRaw!) as Map<String, dynamic>;
      expect(cardData['data'], '78.20');
    });

    test(
        'R2 & R3: single background execution with elec AuthInvalidFailure trips circuit breaker and short-circuits card and schedule sync',
        () async {
      final prefs = await SharedPreferences.getInstance();
      final sessionService = SessionService();
      final plugin = FlutterLocalNotificationsPlugin();
      const testUser = 'u_fail_cascade';

      var elecCalls = 0;
      var cardCalls = 0;
      var scheduleCalls = 0;

      final gateway = MockScheduleGateway(
        elecHandler: (username, password,
            {dormParams, forceRefresh = false}) async {
          elecCalls++;
          throw const AuthInvalidFailure('账号或密码错误');
        },
        cardHandler: (username, password, {forceRefresh = false}) async {
          cardCalls++;
          return '50.00';
        },
        scheduleHandler: (username, password,
            {semester, forceRefresh = false}) async {
          scheduleCalls++;
          return (courses: const <Course>[], remark: '');
        },
        sessionStore: sessionService,
      );

      final balanceSuccess = await runLocalAndroidBalanceChecks(
        prefs: prefs,
        plugin: plugin,
        username: testUser,
        password: 'pwd',
        elecThreshold: 10.0,
        cardThreshold: 20.0,
        dormParams: {'buildid': 'B2', 'roomid': '302'},
        sessionService: sessionService,
        gateway: gateway,
      );

      // Electricity check executed once and threw AuthInvalidFailure
      expect(elecCalls, 1);
      // Campus card check was short-circuited and never called!
      expect(cardCalls, 0);
      expect(balanceSuccess, isFalse);

      // Circuit breaker is tripped
      expect(await sessionService.isAuthCircuitBroken(testUser), isTrue);
      expect(await sessionService.canAttemptAutoLogin(testUser), isFalse);

      // Subsequent schedule sync in the same or next task is short-circuited!
      final syncResult = await runBackgroundScheduleSync(
        prefs: prefs,
        username: testUser,
        password: 'pwd',
        sessionService: sessionService,
        gateway: gateway,
      );

      expect(syncResult, isFalse);
      expect(scheduleCalls, 0);
    });

    test(
        'R2: runBackgroundScheduleSync skips network sync when isAuthCircuitBroken is true',
        () async {
      final prefs = await SharedPreferences.getInstance();
      final sessionService = SessionService();
      const testUser = 'u_already_broken';

      var scheduleCalls = 0;
      final gateway = MockScheduleGateway(
        scheduleHandler: (username, password,
            {semester, forceRefresh = false}) async {
          scheduleCalls++;
          return (courses: const <Course>[], remark: '');
        },
        sessionStore: sessionService,
      );

      // Pre-trip circuit breaker
      await sessionService.markAuthCircuitBroken(testUser);
      expect(await sessionService.isAuthCircuitBroken(testUser), isTrue);

      final syncResult = await runBackgroundScheduleSync(
        prefs: prefs,
        username: testUser,
        password: 'pwd',
        sessionService: sessionService,
        gateway: gateway,
      );

      expect(syncResult, isFalse);
      expect(scheduleCalls, 0);
    });

    test(
        'R2: runBackgroundScheduleSync trips circuit breaker when gateway throws AuthInvalidFailure',
        () async {
      final prefs = await SharedPreferences.getInstance();
      final sessionService = SessionService();
      const testUser = 'u_sched_auth_fail';

      final gateway = MockScheduleGateway(
        scheduleHandler: (username, password,
            {semester, forceRefresh = false}) async {
          throw const AuthInvalidFailure('密码错误');
        },
        sessionStore: sessionService,
      );

      expect(await sessionService.isAuthCircuitBroken(testUser), isFalse);

      final syncResult = await runBackgroundScheduleSync(
        prefs: prefs,
        username: testUser,
        password: 'pwd',
        sessionService: sessionService,
        gateway: gateway,
      );

      expect(syncResult, isFalse);
      expect(await sessionService.isAuthCircuitBroken(testUser), isTrue);
    });

    test(
        'R3: when electricity succeeds but card check fails with AuthInvalidFailure, breaker trips and schedule sync is skipped',
        () async {
      final prefs = await SharedPreferences.getInstance();
      final plugin = FlutterLocalNotificationsPlugin();
      final sessionService = SessionService();
      const testUser = 'u_card_auth_fail';

      var elecCalls = 0;
      var cardCalls = 0;
      var scheduleCalls = 0;

      final gateway = MockScheduleGateway(
        elecHandler: (username, password,
            {dormParams, forceRefresh = false}) async {
          elecCalls++;
          return '35.50';
        },
        cardHandler: (username, password, {forceRefresh = false}) async {
          cardCalls++;
          throw const AuthInvalidFailure('一卡通身份认证失效');
        },
        scheduleHandler: (username, password,
            {semester, forceRefresh = false}) async {
          scheduleCalls++;
          return (courses: const <Course>[], remark: '');
        },
        sessionStore: sessionService,
      );

      final balanceSuccess = await runLocalAndroidBalanceChecks(
        prefs: prefs,
        plugin: plugin,
        username: testUser,
        password: 'pwd',
        elecThreshold: 10.0,
        cardThreshold: 20.0,
        dormParams: {'buildid': 'B1', 'roomid': '101'},
        sessionService: sessionService,
        gateway: gateway,
      );

      expect(elecCalls, 1);
      expect(cardCalls, 1);
      expect(balanceSuccess, isFalse);
      expect(await sessionService.isAuthCircuitBroken(testUser), isTrue);

      final syncResult = await runBackgroundScheduleSync(
        prefs: prefs,
        username: testUser,
        password: 'pwd',
        sessionService: sessionService,
        gateway: gateway,
      );

      expect(syncResult, isFalse);
      expect(scheduleCalls, 0);
    });

    test(
        'R3: when dorm is not configured and card check fails with AuthInvalidFailure, breaker trips and schedule sync is skipped',
        () async {
      final prefs = await SharedPreferences.getInstance();
      final plugin = FlutterLocalNotificationsPlugin();
      final sessionService = SessionService();
      const testUser = 'u_no_dorm_card_fail';

      var elecCalls = 0;
      var cardCalls = 0;
      var scheduleCalls = 0;

      final gateway = MockScheduleGateway(
        elecHandler: (username, password,
            {dormParams, forceRefresh = false}) async {
          elecCalls++;
          return '35.50';
        },
        cardHandler: (username, password, {forceRefresh = false}) async {
          cardCalls++;
          throw const AuthInvalidFailure('密码错误');
        },
        scheduleHandler: (username, password,
            {semester, forceRefresh = false}) async {
          scheduleCalls++;
          return (courses: const <Course>[], remark: '');
        },
        sessionStore: sessionService,
      );

      final balanceSuccess = await runLocalAndroidBalanceChecks(
        prefs: prefs,
        plugin: plugin,
        username: testUser,
        password: 'pwd',
        elecThreshold: 10.0,
        cardThreshold: 20.0,
        dormParams: null, // dorm not configured
        sessionService: sessionService,
        gateway: gateway,
      );

      expect(elecCalls, 0);
      expect(cardCalls, 1);
      expect(balanceSuccess, isFalse);
      expect(await sessionService.isAuthCircuitBroken(testUser), isTrue);

      final syncResult = await runBackgroundScheduleSync(
        prefs: prefs,
        username: testUser,
        password: 'pwd',
        sessionService: sessionService,
        gateway: gateway,
      );

      expect(syncResult, isFalse);
      expect(scheduleCalls, 0);
    });

    test(
        'R3: when electricity encounters NetworkFailure, card check and schedule sync are short-circuited',
        () async {
      final prefs = await SharedPreferences.getInstance();
      final plugin = FlutterLocalNotificationsPlugin();
      final sessionService = SessionService();
      const testUser = 'u_elec_net_fail';

      var elecCalls = 0;
      var cardCalls = 0;
      var scheduleCalls = 0;

      final gateway = MockScheduleGateway(
        elecHandler: (username, password,
            {dormParams, forceRefresh = false}) async {
          elecCalls++;
          throw const NetworkFailure('CAS server unreachable (timeout)');
        },
        cardHandler: (username, password, {forceRefresh = false}) async {
          cardCalls++;
          return '50.00';
        },
        scheduleHandler: (username, password,
            {semester, forceRefresh = false}) async {
          scheduleCalls++;
          return (courses: const <Course>[], remark: '');
        },
        sessionStore: sessionService,
      );

      final balanceSuccess = await runLocalAndroidBalanceChecks(
        prefs: prefs,
        plugin: plugin,
        username: testUser,
        password: 'pwd',
        elecThreshold: 10.0,
        cardThreshold: 20.0,
        dormParams: {'buildid': 'B1', 'roomid': '101'},
        sessionService: sessionService,
        gateway: gateway,
      );

      expect(elecCalls, 1);
      // Card check must be skipped because elec had an unrecoverable network failure
      expect(cardCalls, 0);
      expect(balanceSuccess, isFalse);

      // In background cycle, schedule sync is gated on balanceSuccess
      final syncResult = balanceSuccess
          ? await runBackgroundScheduleSync(
              prefs: prefs,
              username: testUser,
              password: 'pwd',
              sessionService: sessionService,
              gateway: gateway,
            )
          : false;

      expect(syncResult, isFalse);
      expect(scheduleCalls, 0);
    });

    test(
        'R2: runBackgroundScheduleSync checks gateway.isAuthCircuitBroken in memory',
        () async {
      final prefs = await SharedPreferences.getInstance();
      final sessionService = SessionService();
      const testUser = 'u_in_mem_gw_broken';

      var scheduleCalls = 0;
      final gateway = MockScheduleGateway(
        scheduleHandler: (username, password,
            {semester, forceRefresh = false}) async {
          scheduleCalls++;
          return (courses: const <Course>[], remark: '');
        },
        sessionStore: sessionService,
      );

      // Gateway in-memory breaker is active
      await gateway.markAuthCircuitBroken(testUser);
      expect(await gateway.isAuthCircuitBroken(testUser), isTrue);

      final syncResult = await runBackgroundScheduleSync(
        prefs: prefs,
        username: testUser,
        password: 'pwd',
        sessionService: sessionService,
        gateway: gateway,
      );

      expect(syncResult, isFalse);
      expect(scheduleCalls, 0);
    });
  });
}

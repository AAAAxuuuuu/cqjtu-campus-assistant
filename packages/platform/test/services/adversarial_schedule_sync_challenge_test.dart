import 'dart:convert';
import 'dart:io';

import 'package:campus_platform/services/background_task.dart';
import 'package:campus_platform/services/session_service.dart';
import 'package:core/models/course.dart';
import 'package:core/utils/resource_cache_key.dart';
import 'package:data/data.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AdversarialMockGateway extends DirectSchoolCampusGateway {
  AdversarialMockGateway({
    this.scheduleHandler,
    super.sessionStore,
  });

  Future<({List<Course> courses, String remark})> Function(
    String username,
    String password, {
    String? semester,
    bool forceRefresh,
  })? scheduleHandler;

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
}

Course sampleCourse({
  String name = '软件工程导论',
  String classroom = 'B204',
  int dayOfWeek = 1,
  int timeSlot = 3,
  int endTimeSlot = 4,
}) {
  return Course(
    name: name,
    teacher: '李老师',
    timeStr: '3-4节',
    classroom: classroom,
    dayOfWeek: dayOfWeek,
    timeSlot: timeSlot,
    endTimeSlot: endTimeSlot,
    weekList: const [1, 2, 3, 4, 5, 6, 7, 8],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const widgetChannel = MethodChannel('campus_app/schedule_widget');
  const reminderChannel = MethodChannel('campus_app/class_reminder');
  const notificationsChannel =
      MethodChannel('dexterous.com/flutter/local_notifications');

  final widgetCalls = <MethodCall>[];
  final reminderCalls = <MethodCall>[];

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    widgetCalls.clear();
    reminderCalls.clear();

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(widgetChannel, (call) async {
      widgetCalls.add(call);
      return null;
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(reminderChannel, (call) async {
      reminderCalls.add(call);
      return null;
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(notificationsChannel, (call) async {
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
        .setMockMethodCallHandler(notificationsChannel, null);
  });

  group('Adversarial Challenge 1: 2-Hour Freshness Window Boundaries', () {
    test(
        'Boundary 119m: Cache updated 119 minutes ago MUST skip sync (0 network calls)',
        () async {
      final prefs = await SharedPreferences.getInstance();
      final now = DateTime(2026, 9, 19, 12, 0, 0);
      final cacheKey = resourceCacheKey('schedule',
          username: 'adv_u1', scope: '2026-2027-1');

      // Updated 119 minutes ago
      final updated119m = now.subtract(const Duration(minutes: 119));
      await prefs.setString(
        cacheKey,
        jsonEncode({
          'updatedAtMs': updated119m.millisecondsSinceEpoch,
          'data': {
            'courses': [sampleCourse().toJson()],
            'remark': '119m旧数据',
          },
        }),
      );

      final gateway = AdversarialMockGateway();

      final result = await runBackgroundScheduleSync(
        prefs: prefs,
        username: 'adv_u1',
        password: 'pwd',
        semester: '2026-2027-1',
        gateway: gateway,
        now: now,
      );

      expect(result, isFalse,
          reason: '119m is strictly inside the 2-hour window (< 120m)');
      expect(gateway.scheduleCallCount, 0,
          reason: 'Zero network calls allowed when fresh');
    });

    test('Boundary 119m 59s: Cache updated 119m 59s ago MUST skip sync',
        () async {
      final prefs = await SharedPreferences.getInstance();
      final now = DateTime(2026, 9, 19, 12, 0, 0);
      final cacheKey = resourceCacheKey('schedule',
          username: 'adv_u1', scope: '2026-2027-1');

      final updatedAlmost2h =
          now.subtract(const Duration(minutes: 119, seconds: 59));
      await prefs.setString(
        cacheKey,
        jsonEncode({
          'updatedAtMs': updatedAlmost2h.millisecondsSinceEpoch,
          'data': {
            'courses': [sampleCourse().toJson()],
            'remark': '119m59s旧数据',
          },
        }),
      );

      final gateway = AdversarialMockGateway();

      final result = await runBackgroundScheduleSync(
        prefs: prefs,
        username: 'adv_u1',
        password: 'pwd',
        semester: '2026-2027-1',
        gateway: gateway,
        now: now,
      );

      expect(result, isFalse,
          reason: '119m59s is still within the 2-hour window');
      expect(gateway.scheduleCallCount, 0);
    });

    test(
        'Boundary 120m: Cache updated exactly 120 minutes ago MUST proceed with sync',
        () async {
      final prefs = await SharedPreferences.getInstance();
      final now = DateTime(2026, 9, 19, 12, 0, 0);
      final cacheKey = resourceCacheKey('schedule',
          username: 'adv_u1', scope: '2026-2027-1');

      // Updated exactly 120 minutes ago
      final updated120m = now.subtract(const Duration(hours: 2));
      await prefs.setString(
        cacheKey,
        jsonEncode({
          'updatedAtMs': updated120m.millisecondsSinceEpoch,
          'data': {
            'courses': [sampleCourse(name: '旧课').toJson()],
            'remark': '120m旧数据',
          },
        }),
      );

      final gateway = AdversarialMockGateway(
        scheduleHandler: (u, p, {semester, forceRefresh = false}) async {
          return (courses: [sampleCourse(name: '新课120m')], remark: '已刷新');
        },
      );

      final result = await runBackgroundScheduleSync(
        prefs: prefs,
        username: 'adv_u1',
        password: 'pwd',
        semester: '2026-2027-1',
        gateway: gateway,
        now: now,
      );

      expect(result, isTrue,
          reason: 'Age >= 2h has expired, sync must proceed');
      expect(gateway.scheduleCallCount, 1);
    });

    test('Boundary 121m: Cache updated 121 minutes ago MUST proceed with sync',
        () async {
      final prefs = await SharedPreferences.getInstance();
      final now = DateTime(2026, 9, 19, 12, 0, 0);
      final cacheKey = resourceCacheKey('schedule',
          username: 'adv_u1', scope: '2026-2027-1');

      final updated121m = now.subtract(const Duration(minutes: 121));
      await prefs.setString(
        cacheKey,
        jsonEncode({
          'updatedAtMs': updated121m.millisecondsSinceEpoch,
          'data': {
            'courses': [sampleCourse(name: '旧课').toJson()],
            'remark': '121m旧数据',
          },
        }),
      );

      final gateway = AdversarialMockGateway(
        scheduleHandler: (u, p, {semester, forceRefresh = false}) async {
          return (courses: [sampleCourse(name: '新课121m')], remark: '已刷新121m');
        },
      );

      final result = await runBackgroundScheduleSync(
        prefs: prefs,
        username: 'adv_u1',
        password: 'pwd',
        semester: '2026-2027-1',
        gateway: gateway,
        now: now,
      );

      expect(result, isTrue,
          reason: '121m is older than 2 hours, sync must proceed');
      expect(gateway.scheduleCallCount, 1);
    });

    test(
        'Clock Skew / Future Timestamps: Cache timestamp in future does NOT skip sync and heals timestamp',
        () async {
      final prefs = await SharedPreferences.getInstance();
      final now = DateTime(2026, 9, 19, 12, 0, 0);
      final cacheKey = resourceCacheKey('schedule',
          username: 'adv_u1', scope: '2026-2027-1');

      // Future timestamp (e.g. clock skewed 30 minutes into future)
      final futureTime = now.add(const Duration(minutes: 30));
      await prefs.setString(
        cacheKey,
        jsonEncode({
          'updatedAtMs': futureTime.millisecondsSinceEpoch,
          'data': {
            'courses': [sampleCourse(name: '未来课程').toJson()],
            'remark': '异常未来时间戳',
          },
        }),
      );

      final gateway = AdversarialMockGateway(
        scheduleHandler: (u, p, {semester, forceRefresh = false}) async {
          return (courses: [sampleCourse(name: '校正后课程')], remark: '时间戳已校准');
        },
      );

      final result = await runBackgroundScheduleSync(
        prefs: prefs,
        username: 'adv_u1',
        password: 'pwd',
        semester: '2026-2027-1',
        gateway: gateway,
        now: now,
      );

      expect(result, isTrue,
          reason:
              'Future timestamp (negative age) must not be treated as fresh; sync proceeds to self-heal');
      expect(gateway.scheduleCallCount, 1);

      // Verify healed timestamp in cache
      final updatedRaw = prefs.getString(cacheKey)!;
      final decoded = jsonDecode(updatedRaw) as Map<String, dynamic>;
      expect(decoded['updatedAtMs'], now.millisecondsSinceEpoch,
          reason: 'Timestamp in cache must be healed to current time');
      expect(prefs.getInt('bg_schedule_last_sync_ms_adv_u1'),
          now.millisecondsSinceEpoch);
    });

    test(
        'Multi-source Freshness Selection: Picks latest between bg_schedule_last_sync_ms and cache updatedAtMs',
        () async {
      final prefs = await SharedPreferences.getInstance();
      final now = DateTime(2026, 9, 19, 12, 0, 0);
      final cacheKey = resourceCacheKey('schedule',
          username: 'adv_u1', scope: '2026-2027-1');

      // Case A: Cache updatedAt is stale (3 hours ago), but bg_schedule_last_sync_ms is fresh (30m ago)
      await prefs.setString(
        cacheKey,
        jsonEncode({
          'updatedAtMs':
              now.subtract(const Duration(hours: 3)).millisecondsSinceEpoch,
          'data': {
            'courses': [sampleCourse().toJson()],
            'remark': ''
          },
        }),
      );
      await prefs.setInt(
        'bg_schedule_last_sync_ms_adv_u1',
        now.subtract(const Duration(minutes: 30)).millisecondsSinceEpoch,
      );

      final gatewayA = AdversarialMockGateway();
      final resultA = await runBackgroundScheduleSync(
        prefs: prefs,
        username: 'adv_u1',
        password: 'pwd',
        semester: '2026-2027-1',
        gateway: gatewayA,
        now: now,
      );
      expect(resultA, isFalse,
          reason:
              'Latest of the two is 30m ago (< 2h), so sync should be skipped');
      expect(gatewayA.scheduleCallCount, 0);

      // Case B: bg_schedule_last_sync_ms is stale (3 hours ago), but foreground cache is fresh (10m ago)
      await prefs.setString(
        cacheKey,
        jsonEncode({
          'updatedAtMs':
              now.subtract(const Duration(minutes: 10)).millisecondsSinceEpoch,
          'data': {
            'courses': [sampleCourse().toJson()],
            'remark': ''
          },
        }),
      );
      await prefs.setInt(
        'bg_schedule_last_sync_ms_adv_u1',
        now.subtract(const Duration(hours: 3)).millisecondsSinceEpoch,
      );

      final gatewayB = AdversarialMockGateway();
      final resultB = await runBackgroundScheduleSync(
        prefs: prefs,
        username: 'adv_u1',
        password: 'pwd',
        semester: '2026-2027-1',
        gateway: gatewayB,
        now: now,
      );
      expect(resultB, isFalse,
          reason:
              'Foreground cache updated 10m ago (< 2h), so sync should be skipped');
      expect(gatewayB.scheduleCallCount, 0);
    });
  });

  group(
      'Adversarial Challenge 2: Auto-Login Rate Limiting (5th vs 6th Attempt)',
      () {
    test(
        'Attempt 6 allows sync; Attempt 7 blocks sync with ZERO network requests',
        () async {
      final prefs = await SharedPreferences.getInstance();
      final sessionService = SessionService();
      final now = DateTime(2026, 9, 19, 14, 0, 0);

      // Record 5 attempts in sliding 1-hour window (spaced by 6m to satisfy minInterval)
      for (var i = 1; i <= 5; i++) {
        await sessionService.recordAutoLoginAttempt(
          'adv_user',
          now: now.subtract(Duration(minutes: 36 - i * 6)),
        );
      }

      // Check remaining quota before 6th attempt
      expect(await sessionService.canAttemptAutoLogin('adv_user', now: now),
          isTrue);
      expect(
          await sessionService.getRemainingAutoLoginAttempts('adv_user',
              now: now),
          1);

      // Attempt 6: Must be allowed to sync
      final gateway6 = AdversarialMockGateway(
        scheduleHandler: (u, p, {semester, forceRefresh = false}) async {
          return (courses: [sampleCourse(name: '第6次获取成功')], remark: 'OK');
        },
      );

      final result6 = await runBackgroundScheduleSync(
        prefs: prefs,
        username: 'adv_user',
        password: 'pwd',
        semester: '2026-2027-1',
        gateway: gateway6,
        sessionService: sessionService,
        now: now,
      );

      expect(result6, isTrue,
          reason: '6th attempt is within quota (<= 6/hr)');
      expect(gateway6.scheduleCallCount, 1,
          reason: 'Network request executed for 6th attempt');

      // Now record the 6th attempt in session service
      await sessionService.recordAutoLoginAttempt('adv_user', now: now);

      // Now exactly 6 attempts in sliding 1-hour window
      expect(await sessionService.canAttemptAutoLogin('adv_user', now: now),
          isFalse);
      expect(
          await sessionService.getRemainingAutoLoginAttempts('adv_user',
              now: now),
          0);

      // Attempt 7: Must be BLOCKED immediately
      // Reset cache freshness to stale (> 2h) to isolate rate limiter check
      final cacheKey = resourceCacheKey('schedule',
          username: 'adv_user', scope: '2026-2027-1');
      await prefs.setString(
        cacheKey,
        jsonEncode({
          'updatedAtMs':
              now.subtract(const Duration(hours: 3)).millisecondsSinceEpoch,
          'data': {
            'courses': [sampleCourse().toJson()],
            'remark': ''
          },
        }),
      );
      await prefs.remove('bg_schedule_last_sync_ms_adv_user');

      final gateway7 = AdversarialMockGateway(
        scheduleHandler: (u, p, {semester, forceRefresh = false}) async {
          throw Exception('SHOULD NEVER BE CALLED ON 7TH ATTEMPT');
        },
      );

      final result7 = await runBackgroundScheduleSync(
        prefs: prefs,
        username: 'adv_user',
        password: 'pwd',
        semester: '2026-2027-1',
        gateway: gateway7,
        sessionService: sessionService,
        now: now,
      );

      expect(result7, isFalse,
          reason: '7th attempt must be blocked by rate limiter');
      expect(gateway7.scheduleCallCount, 0,
          reason: 'ZERO network calls made on 7th attempt');
    });

    test(
        'Sliding 1-Hour Window Roll-Off: Old attempt at 61 minutes rolls off, permitting attempt',
        () async {
      final prefs = await SharedPreferences.getInstance();
      final sessionService = SessionService();
      final now = DateTime(2026, 9, 19, 15, 0, 0);

      // 1 attempt 61 minutes ago (expired from sliding window)
      // 5 attempts within last 35 minutes (active, spaced by 6 min)
      await sessionService.recordAutoLoginAttempt('adv_user',
          now: now.subtract(const Duration(minutes: 61)));
      for (var i = 1; i <= 5; i++) {
        await sessionService.recordAutoLoginAttempt(
          'adv_user',
          now: now.subtract(Duration(minutes: 36 - i * 6)),
        );
      }

      // Active attempts count is 5, not 6
      expect(await sessionService.canAttemptAutoLogin('adv_user', now: now),
          isTrue);
      expect(
          await sessionService.getRemainingAutoLoginAttempts('adv_user',
              now: now),
          1);

      final gateway = AdversarialMockGateway(
        scheduleHandler: (u, p, {semester, forceRefresh = false}) async {
          return (courses: [sampleCourse()], remark: 'OK');
        },
      );

      final result = await runBackgroundScheduleSync(
        prefs: prefs,
        username: 'adv_user',
        password: 'pwd',
        semester: '2026-2027-1',
        gateway: gateway,
        sessionService: sessionService,
        now: now,
      );

      expect(result, isTrue,
          reason: 'Old attempt at 61m rolled off, so sync succeeds');
      expect(gateway.scheduleCallCount, 1);
    });

    test('Account Isolation: Rate limit on account A does NOT block account B',
        () async {
      final prefs = await SharedPreferences.getInstance();
      final sessionService = SessionService();
      final now = DateTime(2026, 9, 19, 16, 0, 0);

      // Max out account A (6 attempts spaced by 6m)
      for (var i = 0; i < 6; i++) {
        await sessionService.recordAutoLoginAttempt(
          'account_A',
          now: now.subtract(Duration(minutes: 40 - i * 6)),
        );
      }
      expect(await sessionService.canAttemptAutoLogin('account_A', now: now),
          isFalse);

      // Account B has 0 attempts
      expect(await sessionService.canAttemptAutoLogin('account_B', now: now),
          isTrue);

      final gatewayB = AdversarialMockGateway(
        scheduleHandler: (u, p, {semester, forceRefresh = false}) async {
          return (courses: [sampleCourse()], remark: 'B_OK');
        },
      );

      final resultB = await runBackgroundScheduleSync(
        prefs: prefs,
        username: 'account_B',
        password: 'pwd',
        semester: '2026-2027-1',
        gateway: gatewayB,
        sessionService: sessionService,
        now: now,
      );

      expect(resultB, isTrue,
          reason: 'Account B quota is separate from account A');
      expect(gatewayB.scheduleCallCount, 1);
    });
  });

  group('Adversarial Challenge 3: Defensive Cache Guard', () {
    test(
        'Remote empty response MUST NOT overwrite non-empty existing cache; widgets NOT wiped',
        () async {
      final prefs = await SharedPreferences.getInstance();
      final now = DateTime(2026, 9, 19, 16, 0, 0);
      final cacheKey = resourceCacheKey('schedule',
          username: 'def_user', scope: '2026-2027-1');

      // Pre-populate non-empty cache from 3 hours ago
      final existingCourse = sampleCourse(name: '不可丢失的课程');
      final originalCacheJson = jsonEncode({
        'updatedAtMs':
            now.subtract(const Duration(hours: 3)).millisecondsSinceEpoch,
        'data': {
          'courses': [existingCourse.toJson()],
          'remark': '重要原版数据',
        },
      });
      await prefs.setString(cacheKey, originalCacheJson);

      // Remote returns empty courses list
      final gateway = AdversarialMockGateway(
        scheduleHandler: (u, p, {semester, forceRefresh = false}) async {
          return (courses: const <Course>[], remark: '');
        },
      );

      final result = await runBackgroundScheduleSync(
        prefs: prefs,
        username: 'def_user',
        password: 'pwd',
        semester: '2026-2027-1',
        gateway: gateway,
        now: now,
      );

      expect(result, isFalse,
          reason:
              'Empty remote response blocked from overwriting non-empty cache');
      expect(gateway.scheduleCallCount, 1);

      // Cache strictly preserved byte-for-byte
      final afterCache = prefs.getString(cacheKey);
      expect(afterCache, equals(originalCacheJson),
          reason: 'Local cache must be completely unchanged');

      // Zero AppWidget updates
      expect(
        widgetCalls.where((c) => c.method == 'updateScheduleWidgets'),
        isEmpty,
        reason:
            'Widgets must NOT be wiped or updated when defensive guard fires',
      );
      // Zero class reminder updates
      expect(
        reminderCalls.where((c) => c.method == 'scheduleClassReminders'),
        isEmpty,
        reason:
            'Class reminders must NOT be wiped or updated when defensive guard fires',
      );
    });

    test(
        'Corrupted/malformed existing cache: Recovers gracefully when remote returns valid courses',
        () async {
      final prefs = await SharedPreferences.getInstance();
      final now = DateTime(2026, 9, 19, 16, 0, 0);
      final cacheKey = resourceCacheKey('schedule',
          username: 'def_user', scope: '2026-2027-1');

      // Malformed raw string in SharedPreferences
      await prefs.setString(cacheKey, '{bad-json: broken}');

      final gateway = AdversarialMockGateway(
        scheduleHandler: (u, p, {semester, forceRefresh = false}) async {
          return (courses: [sampleCourse(name: '恢复课程')], remark: '恢复成功');
        },
      );

      final result = await runBackgroundScheduleSync(
        prefs: prefs,
        username: 'def_user',
        password: 'pwd',
        semester: '2026-2027-1',
        gateway: gateway,
        now: now,
      );

      expect(result, isTrue, reason: 'Valid remote data heals malformed cache');
      expect(gateway.scheduleCallCount, 1);

      final healed = prefs.getString(cacheKey)!;
      final decoded = jsonDecode(healed) as Map<String, dynamic>;
      expect(decoded['updatedAtMs'], now.millisecondsSinceEpoch);
      final courses = (decoded['data'] as Map)['courses'] as List;
      expect(courses.first['name'], '恢复课程');
    });

    test(
        'Brand new user cold start (no cache): Empty remote response DOES write valid empty cache',
        () async {
      final prefs = await SharedPreferences.getInstance();
      final now = DateTime(2026, 9, 19, 16, 0, 0);
      final cacheKey = resourceCacheKey('schedule',
          username: 'brand_new_user', scope: '2026-2027-1');

      // No existing cache at all
      expect(prefs.containsKey(cacheKey), isFalse);

      final gateway = AdversarialMockGateway(
        scheduleHandler: (u, p, {semester, forceRefresh = false}) async {
          return (courses: const <Course>[], remark: '新学期未排课');
        },
      );

      final result = await runBackgroundScheduleSync(
        prefs: prefs,
        username: 'brand_new_user',
        password: 'pwd',
        semester: '2026-2027-1',
        gateway: gateway,
        now: now,
      );

      expect(result, isTrue, reason: 'Cold start empty schedule is valid');
      expect(prefs.containsKey(cacheKey), isTrue);
      final decoded =
          jsonDecode(prefs.getString(cacheKey)!) as Map<String, dynamic>;
      expect((decoded['data'] as Map)['courses'], isEmpty);
      expect((decoded['data'] as Map)['remark'], '新学期未排课');
    });
  });

  group(
      'Adversarial Challenge 4: Silent Error Resiliency Under Simulated Failures',
      () {
    test(
        'Simulated BotChallengeFailure: Caught silently, no unhandled throw, cache preserved',
        () async {
      final prefs = await SharedPreferences.getInstance();
      final now = DateTime(2026, 9, 19, 17, 0, 0);
      final cacheKey = resourceCacheKey('schedule',
          username: 'err_user', scope: '2026-2027-1');
      final originalJson = jsonEncode({
        'updatedAtMs':
            now.subtract(const Duration(hours: 3)).millisecondsSinceEpoch,
        'data': {
          'courses': [sampleCourse().toJson()],
          'remark': '保留'
        },
      });
      await prefs.setString(cacheKey, originalJson);

      final gateway = AdversarialMockGateway(
        scheduleHandler: (u, p, {semester, forceRefresh = false}) async {
          throw const BotChallengeFailure('安全验证挑战 (WAF Cloudflare/Hillstone)');
        },
      );

      // Must complete without throwing
      final result = await runBackgroundScheduleSync(
        prefs: prefs,
        username: 'err_user',
        password: 'pwd',
        semester: '2026-2027-1',
        gateway: gateway,
        now: now,
      );

      expect(result, isFalse);
      expect(prefs.getString(cacheKey), equals(originalJson));
    });

    test(
        'Simulated CaptchaRequiredFailure: Caught silently, no unhandled throw, cache preserved',
        () async {
      final prefs = await SharedPreferences.getInstance();
      final now = DateTime(2026, 9, 19, 17, 0, 0);
      final cacheKey = resourceCacheKey('schedule',
          username: 'err_user', scope: '2026-2027-1');
      final originalJson = jsonEncode({
        'updatedAtMs':
            now.subtract(const Duration(hours: 3)).millisecondsSinceEpoch,
        'data': {
          'courses': [sampleCourse().toJson()],
          'remark': '保留'
        },
      });
      await prefs.setString(cacheKey, originalJson);

      final gateway = AdversarialMockGateway(
        scheduleHandler: (u, p, {semester, forceRefresh = false}) async {
          throw const CaptchaRequiredFailure('触发图形验证码');
        },
      );

      final result = await runBackgroundScheduleSync(
        prefs: prefs,
        username: 'err_user',
        password: 'pwd',
        semester: '2026-2027-1',
        gateway: gateway,
        now: now,
      );

      expect(result, isFalse);
      expect(prefs.getString(cacheKey), equals(originalJson));
    });

    test(
        'Simulated SessionExpiredFailure: Caught silently, no unhandled throw, cache preserved',
        () async {
      final prefs = await SharedPreferences.getInstance();
      final now = DateTime(2026, 9, 19, 17, 0, 0);
      final cacheKey = resourceCacheKey('schedule',
          username: 'err_user', scope: '2026-2027-1');
      final originalJson = jsonEncode({
        'updatedAtMs':
            now.subtract(const Duration(hours: 3)).millisecondsSinceEpoch,
        'data': {
          'courses': [sampleCourse().toJson()],
          'remark': '保留'
        },
      });
      await prefs.setString(cacheKey, originalJson);

      final gateway = AdversarialMockGateway(
        scheduleHandler: (u, p, {semester, forceRefresh = false}) async {
          throw const SessionExpiredFailure('教务系统会话过期');
        },
      );

      final result = await runBackgroundScheduleSync(
        prefs: prefs,
        username: 'err_user',
        password: 'pwd',
        semester: '2026-2027-1',
        gateway: gateway,
        now: now,
      );

      expect(result, isFalse);
      expect(prefs.getString(cacheKey), equals(originalJson));
    });

    test(
        'Simulated DioException (connectionTimeout, badResponse, badCertificate, cancel, etc.)',
        () async {
      final prefs = await SharedPreferences.getInstance();
      final now = DateTime(2026, 9, 19, 17, 0, 0);
      final cacheKey = resourceCacheKey('schedule',
          username: 'err_user', scope: '2026-2027-1');
      final originalJson = jsonEncode({
        'updatedAtMs':
            now.subtract(const Duration(hours: 3)).millisecondsSinceEpoch,
        'data': {
          'courses': [sampleCourse().toJson()],
          'remark': '保留'
        },
      });

      final dioErrorTypes = [
        DioExceptionType.connectionTimeout,
        DioExceptionType.sendTimeout,
        DioExceptionType.receiveTimeout,
        DioExceptionType.badCertificate,
        DioExceptionType.badResponse,
        DioExceptionType.cancel,
        DioExceptionType.connectionError,
        DioExceptionType.unknown,
      ];

      for (final type in dioErrorTypes) {
        await prefs.setString(cacheKey, originalJson);
        final gateway = AdversarialMockGateway(
          scheduleHandler: (u, p, {semester, forceRefresh = false}) async {
            throw DioException(
              requestOptions: RequestOptions(path: '/schedule'),
              type: type,
            );
          },
        );

        final result = await runBackgroundScheduleSync(
          prefs: prefs,
          username: 'err_user',
          password: 'pwd',
          semester: '2026-2027-1',
          gateway: gateway,
          now: now,
        );

        expect(result, isFalse,
            reason: 'DioException ($type) must be handled silently');
        expect(prefs.getString(cacheKey), equals(originalJson),
            reason: 'Cache must not be wiped on $type');
      }
    });

    test(
        'Simulated SocketException / HttpException / FormatException / arbitrary Error',
        () async {
      final prefs = await SharedPreferences.getInstance();
      final now = DateTime(2026, 9, 19, 17, 0, 0);
      final cacheKey = resourceCacheKey('schedule',
          username: 'err_user', scope: '2026-2027-1');
      final originalJson = jsonEncode({
        'updatedAtMs':
            now.subtract(const Duration(hours: 3)).millisecondsSinceEpoch,
        'data': {
          'courses': [sampleCourse().toJson()],
          'remark': '保留'
        },
      });

      final exceptions = [
        const SocketException('Failed host lookup: jwgl.cqjtu.edu.cn'),
        const HttpException('502 Bad Gateway'),
        const FormatException('Unexpected character in JSON response'),
        ArgumentError('Invalid semester format'),
      ];

      for (final exc in exceptions) {
        await prefs.setString(cacheKey, originalJson);
        final gateway = AdversarialMockGateway(
          scheduleHandler: (u, p, {semester, forceRefresh = false}) async {
            throw exc;
          },
        );

        final result = await runBackgroundScheduleSync(
          prefs: prefs,
          username: 'err_user',
          password: 'pwd',
          semester: '2026-2027-1',
          gateway: gateway,
          now: now,
        );

        expect(result, isFalse,
            reason: '${exc.runtimeType} must be handled silently');
        expect(prefs.getString(cacheKey), equals(originalJson));
      }
    });

    test(
        'Downstream widget failure does NOT crash sync and cache is still successfully committed',
        () async {
      final prefs = await SharedPreferences.getInstance();
      final now = DateTime(2026, 9, 19, 17, 0, 0);
      final cacheKey = resourceCacheKey('schedule',
          username: 'widget_err_user', scope: '2026-2027-1');

      // Make widget channel throw PlatformException
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(widgetChannel, (call) async {
        throw PlatformException(
            code: 'WIDGET_ERROR', message: 'Failed to update remote views');
      });

      final gateway = AdversarialMockGateway(
        scheduleHandler: (u, p, {semester, forceRefresh = false}) async {
          return (courses: [sampleCourse(name: '新课程')], remark: '成功');
        },
      );

      final result = await runBackgroundScheduleSync(
        prefs: prefs,
        username: 'widget_err_user',
        password: 'pwd',
        semester: '2026-2027-1',
        gateway: gateway,
        now: now,
      );

      expect(result, isTrue,
          reason:
              'Sync succeeds and commits cache even if downstream widget service throws');
      final cached = prefs.getString(cacheKey)!;
      expect(cached, contains('新课程'));
    });

    test(
        'Downstream reminder failure does NOT crash sync and cache is still successfully committed',
        () async {
      final prefs = await SharedPreferences.getInstance();
      final now = DateTime(2026, 9, 19, 17, 0, 0);
      final cacheKey = resourceCacheKey('schedule',
          username: 'reminder_err_user', scope: '2026-2027-1');

      // Make reminder channel throw PlatformException
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(reminderChannel, (call) async {
        throw PlatformException(
            code: 'ALARM_PERMISSION_DENIED',
            message: 'Exact alarm not allowed on Android 14');
      });

      final gateway = AdversarialMockGateway(
        scheduleHandler: (u, p, {semester, forceRefresh = false}) async {
          return (courses: [sampleCourse(name: '新课程提醒')], remark: '成功');
        },
      );

      final result = await runBackgroundScheduleSync(
        prefs: prefs,
        username: 'reminder_err_user',
        password: 'pwd',
        semester: '2026-2027-1',
        gateway: gateway,
        now: now,
      );

      expect(result, isTrue,
          reason:
              'Sync succeeds and commits cache even if downstream alarm/notification throws');
      final cached = prefs.getString(cacheKey)!;
      expect(cached, contains('新课程提醒'));
    });
  });
}

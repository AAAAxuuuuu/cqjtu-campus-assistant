import 'dart:convert';

import 'package:core/models/course.dart';
import 'package:core/models/schedule_calendar_rules.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import '../src/class_reminder_schedule.dart';

class NotificationService {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static const _classReminderChannel = MethodChannel(
    'campus_app/class_reminder',
  );

  static const _elecThresholdKey = 'elec_threshold';
  static const _cardThresholdKey = 'card_threshold';
  static const _courseReminderKey = 'course_reminder';
  static const _courseReminderMinutesKey = 'course_reminder_minutes';
  static const _legacyClassReminderCleanupKey =
      'class_reminder_legacy_plugin_cleanup_done';
  static const _reminderCoverageUntilKey = 'class_reminder_scheduled_until_ms';
  static const _reminderSeedKey = 'class_reminder_seed_v1';
  static const defaultReminderLookAheadDays = 14;

  static const double defaultElecThreshold = 10.0;
  static const double defaultCardThreshold = 20.0;
  static const bool defaultCourseReminder = true;
  static const int defaultCourseReminderMinutes = 15;
  static const int minCourseReminderMinutes = 15;
  static const int maxCourseReminderMinutes = 60;

  static const double defaultThreshold = defaultElecThreshold;

  static const _classChannelId = 'class_reminder_v2';
  static const _classChannelName = '上课提醒';
  static const _elecChannelId = 'elec_alert_v2';
  static const _cardChannelId = 'card_alert_v2';

  static bool _timezoneReady = false;
  static bool _pluginReady = false;

  /// Initializes the timezone database and local location exactly once.
  ///
  /// Callable from both the main isolate and the WorkManager background
  /// isolate: the background reminder replenish path needs it before any
  /// zonedSchedule call, and the background isolate never runs [init].
  static Future<void> ensureTimeZoneInitialized() async {
    if (_timezoneReady) return;
    tz.initializeTimeZones();
    try {
      final tzInfo = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(tzInfo.identifier));
      debugPrint('[NOTIF] timezone initialized: ${tzInfo.identifier}');
    } catch (error) {
      debugPrint('[NOTIF] timezone lookup failed ($error); fallback to CST');
      tz.setLocalLocation(tz.getLocation('Asia/Shanghai'));
    }
    _timezoneReady = true;
  }

  /// Initializes the static plugin instance.
  ///
  /// [init] is only run on the main isolate; the background isolate
  /// performs its own plugin setup through the dispatcher. This helper
  /// lets the background replenish path set up the shared static instance
  /// too.
  static Future<void> ensurePluginInitialized() async {
    if (_pluginReady) return;
    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    const settings = InitializationSettings(android: androidSettings);
    await _plugin.initialize(settings);
    _pluginReady = true;
  }

  static Future<void> init() async {
    debugPrint('[NOTIF] init() start');
    await ensureTimeZoneInitialized();
    await ensurePluginInitialized();

    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();

    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        _classChannelId,
        _classChannelName,
        description: '课前提醒，带声音与震动',
        importance: Importance.high,
        playSound: true,
        enableVibration: true,
        enableLights: true,
      ),
    );
    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        _elecChannelId,
        '电费预警',
        description: '电费余额低于预警阈值时通知',
        importance: Importance.high,
        playSound: true,
        enableVibration: true,
      ),
    );
    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        _cardChannelId,
        '校园卡预警',
        description: '校园卡余额低于预警阈值时通知',
        importance: Importance.high,
        playSound: true,
        enableVibration: true,
      ),
    );

    final notifGranted =
        await androidPlugin?.requestNotificationsPermission() ?? false;
    debugPrint('[NOTIF] notification permission: $notifGranted');

    final alarmGranted =
        await androidPlugin?.requestExactAlarmsPermission() ?? false;
    debugPrint('[NOTIF] exact alarm permission: $alarmGranted');
  }

  static Future<void> scheduleClassReminders(
    List<Course> courses,
    DateTime semesterStart, {
    int totalWeeks = 20,
    ScheduleCalendarRules calendarRules = ScheduleCalendarRules.empty,
    String? accountId,
    int lookAheadDays = defaultReminderLookAheadDays,
  }) async {
    final isReminderEnabled = await getCourseReminderEnabled(
      accountId: accountId,
    );
    final reminderMinutes = await getCourseReminderMinutes(
      accountId: accountId,
    );
    final reminders = buildClassReminders(
      courses: courses,
      semesterStart: semesterStart,
      now: DateTime.now(),
      reminderMinutes: reminderMinutes,
      totalWeeks: totalWeeks,
      calendarRules: calendarRules,
      includeActiveReminders: _usesNativeAndroidClassReminders,
      lookAheadDays: lookAheadDays,
    );

    debugPrint(
      '[NOTIF] scheduleClassReminders enabled=$isReminderEnabled '
      'minutes=$reminderMinutes reminders=${reminders.length}',
    );

    if (!isReminderEnabled) {
      await cancelAllClassReminders();
      await _clearReminderSeed();
      return;
    }

    if (_usesNativeAndroidClassReminders) {
      try {
        await _scheduleNativeAndroidClassReminders(reminders);
        await _cleanupLegacyPluginClassRemindersOnce();
        await _persistReminderSeed(
          courses: courses,
          semesterStart: semesterStart,
          totalWeeks: totalWeeks,
          calendarRules: calendarRules,
          accountId: accountId,
          lookAheadDays: lookAheadDays,
        );
        return;
      } catch (error, stackTrace) {
        debugPrint('[NOTIF] native class reminder scheduling failed: $error');
        debugPrint('$stackTrace');
      }
    }

    await _schedulePluginClassReminders(reminders, reminderMinutes);

    await _persistReminderSeed(
      courses: courses,
      semesterStart: semesterStart,
      totalWeeks: totalWeeks,
      calendarRules: calendarRules,
      accountId: accountId,
      lookAheadDays: lookAheadDays,
    );
  }

  static bool get _usesNativeAndroidClassReminders =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static Future<Map<String, Object?>> getLiveReminderCapabilities() async {
    if (!_usesNativeAndroidClassReminders) {
      return const {'isAndroid': false};
    }

    try {
      final result = await _classReminderChannel
          .invokeMapMethod<String, Object?>('getLiveReminderCapabilities');
      return result ?? const {'isAndroid': true};
    } catch (error) {
      debugPrint('[NOTIF] getLiveReminderCapabilities failed: $error');
      return const {'isAndroid': true, 'error': true};
    }
  }

  static Future<void> _scheduleNativeAndroidClassReminders(
    List<ClassReminder> reminders,
  ) async {
    await _classReminderChannel.invokeMethod<void>('scheduleClassReminders', {
      'reminders': reminders.map((r) => r.toPlatformMap()).toList(),
    });
  }

  static Future<void> _cancelNativeAndroidClassReminders() async {
    await _classReminderChannel.invokeMethod<void>('cancelClassReminders');
  }

  static Future<void> _schedulePluginClassReminders(
    List<ClassReminder> reminders,
    int reminderMinutes,
  ) async {
    // The plugin path needs the timezone database and the shared plugin
    // instance even when init() never ran (WorkManager background isolate).
    await ensureTimeZoneInitialized();
    await ensurePluginInitialized();

    if (_usesNativeAndroidClassReminders) {
      await _cancelLegacyPluginClassReminderIds();
    } else {
      await _plugin.cancelAll();
    }

    for (final reminder in reminders) {
      final tzRemindTime = tz.TZDateTime.from(reminder.remindAt, tz.local);
      final titlePrefix = reminder.isExam ? '考试提醒' : '上课提醒';
      final actionText = reminder.isExam ? '考试' : '上课';
      final seatText = reminder.isExam && reminder.seatNumber.trim().isNotEmpty
          ? '，座位号 ${reminder.seatNumber.trim()}'
          : '';
      await _plugin.zonedSchedule(
        reminder.id,
        '$titlePrefix：${reminder.courseName}',
        '将在 $reminderMinutes 分钟后（${reminder.timeText}）在 ${reminder.classroom} $actionText$seatText',
        tzRemindTime,
        NotificationDetails(
          android: AndroidNotificationDetails(
            _classChannelId,
            _classChannelName,
            channelDescription: '课前提醒，带声音与震动',
            importance: Importance.high,
            priority: Priority.high,
            playSound: true,
            enableVibration: true,
            enableLights: true,
            vibrationPattern: Int64List.fromList([0, 200, 200, 400, 200, 400]),
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
    }
  }

  static Future<void> _cleanupLegacyPluginClassRemindersOnce() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_legacyClassReminderCleanupKey) ?? false) return;

    await _cancelLegacyPluginClassReminderIds();
    await prefs.setBool(_legacyClassReminderCleanupKey, true);
  }

  /// Best-effort cancellation of legacy plugin-scheduled ids.
  ///
  /// In the WorkManager background isolate the local-notifications plugin is
  /// not registered, so these calls throw; that must never break the native
  /// scheduling path.
  static Future<void> _cancelLegacyPluginClassReminderIds() async {
    try {
      for (var week = 1; week <= 20; week++) {
        for (var weekday = 1; weekday <= 7; weekday++) {
          for (final timeSlot in classSlotStartTimes.keys) {
            await _plugin.cancel(week * 1000 + weekday * 100 + timeSlot);
          }
        }
      }
    } catch (error) {
      debugPrint('[NOTIF] legacy plugin cleanup skipped: $error');
    }
  }

  static Future<void> checkAndNotify(String balanceStr) async {
    final match = RegExp(r'-?[\d.]+').firstMatch(balanceStr);
    if (match == null) return;
    final balance = double.tryParse(match.group(0)!);
    if (balance == null) return;

    final threshold = await getElecThreshold();
    if (threshold <= 0 || balance >= threshold) return;

    await _plugin.show(
      1,
      '电费不足提醒',
      '寝室剩余电费 ¥$balanceStr，已低于 ¥${threshold.toStringAsFixed(0)}，请及时充值。',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _elecChannelId,
          '电费预警',
          channelDescription: '电费余额低于预警阈值时通知',
          importance: Importance.high,
          priority: Priority.high,
          playSound: true,
          enableVibration: true,
        ),
      ),
    );
  }

  static Future<double> getElecThreshold() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble(_elecThresholdKey) ?? defaultElecThreshold;
  }

  static Future<void> setElecThreshold(double value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_elecThresholdKey, value);
  }

  static Future<double> getThreshold() => getElecThreshold();
  static Future<void> setThreshold(double value) => setElecThreshold(value);

  static Future<double> getCardThreshold() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble(_cardThresholdKey) ?? defaultCardThreshold;
  }

  static Future<void> setCardThreshold(double value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_cardThresholdKey, value);
  }

  static String? _scopedPreferenceKey(String key, String? accountId) {
    final account = accountId?.trim();
    if (account == null || account.isEmpty) return null;
    return 'user_${account}_$key';
  }

  static Future<bool> getCourseReminderEnabled({String? accountId}) async {
    final prefs = await SharedPreferences.getInstance();
    final scopedKey = _scopedPreferenceKey(_courseReminderKey, accountId);
    if (scopedKey != null && prefs.containsKey(scopedKey)) {
      return prefs.getBool(scopedKey) ?? defaultCourseReminder;
    }
    if (scopedKey != null && prefs.containsKey(_courseReminderKey)) {
      final legacy = prefs.getBool(_courseReminderKey) ?? defaultCourseReminder;
      await prefs.setBool(scopedKey, legacy);
      await prefs.remove(_courseReminderKey);
      return legacy;
    }
    return prefs.getBool(_courseReminderKey) ?? defaultCourseReminder;
  }

  static Future<void> setCourseReminderEnabled(
    bool value, {
    String? accountId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(
      _scopedPreferenceKey(_courseReminderKey, accountId) ?? _courseReminderKey,
      value,
    );
  }

  static Future<int> getCourseReminderMinutes({String? accountId}) async {
    final prefs = await SharedPreferences.getInstance();
    final scopedKey = _scopedPreferenceKey(
      _courseReminderMinutesKey,
      accountId,
    );
    int value;
    if (scopedKey != null && prefs.containsKey(scopedKey)) {
      value = prefs.getInt(scopedKey) ?? defaultCourseReminderMinutes;
    } else if (scopedKey != null &&
        prefs.containsKey(_courseReminderMinutesKey)) {
      value = prefs.getInt(_courseReminderMinutesKey) ??
          defaultCourseReminderMinutes;
      await prefs.setInt(scopedKey, value);
      await prefs.remove(_courseReminderMinutesKey);
    } else {
      value = prefs.getInt(_courseReminderMinutesKey) ??
          defaultCourseReminderMinutes;
    }
    return value
        .clamp(minCourseReminderMinutes, maxCourseReminderMinutes)
        .toInt();
  }

  static Future<void> setCourseReminderMinutes(
    int value, {
    String? accountId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final safeValue =
        value.clamp(minCourseReminderMinutes, maxCourseReminderMinutes).toInt();
    await prefs.setInt(
      _scopedPreferenceKey(_courseReminderMinutesKey, accountId) ??
          _courseReminderMinutesKey,
      safeValue,
    );
  }

  static Future<void> _persistReminderSeed({
    required List<Course> courses,
    required DateTime semesterStart,
    required int totalWeeks,
    required ScheduleCalendarRules calendarRules,
    required String? accountId,
    required int lookAheadDays,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(
      _reminderCoverageUntilKey,
      DateTime.now().add(Duration(days: lookAheadDays)).millisecondsSinceEpoch,
    );
    await prefs.setString(
      _reminderSeedKey,
      jsonEncode({
        'courses': courses.map((course) => course.toJson()).toList(),
        'semesterStartIso': semesterStart.toIso8601String(),
        'totalWeeks': totalWeeks,
        'calendarRules': calendarRules.toJson(),
        'accountId': accountId,
      }),
    );
  }

  static Future<void> _clearReminderSeed() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_reminderCoverageUntilKey);
    await prefs.remove(_reminderSeedKey);
  }

  /// Milliseconds timestamp until which class reminders are covered.
  static Future<int> reminderCoverageUntilMs() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_reminderCoverageUntilKey) ?? 0;
  }

  /// True when the persisted reminder window is about to lapse.
  ///
  /// Coverage lapses [defaultReminderLookAheadDays] days after the last
  /// successful scheduling; the window is considered stale two days before
  /// that point so background replenishment runs with a safety margin.
  static Future<bool> isReminderCoverageStale({DateTime? now}) async {
    final current = now ?? DateTime.now();
    final until = await reminderCoverageUntilMs();
    if (until <= 0) return false;
    final threshold =
        current.add(const Duration(days: 2)).millisecondsSinceEpoch;
    return until < threshold;
  }

  /// Re-schedules class reminders from the persisted seed when the coverage
  /// window is stale. Used by the background task so reminders survive long
  /// periods without opening the app. Returns true when a re-schedule ran.
  static Future<bool> replenishFromSeedIfNeeded({
    required String username,
    DateTime? now,
  }) async {
    if (!await isReminderCoverageStale(now: now)) return false;

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_reminderSeedKey);
    if (raw == null || raw.isEmpty) return false;

    try {
      // The background isolate never runs init(): prepare the timezone
      // database and the static plugin instance before rescheduling.
      await ensureTimeZoneInitialized();
      await ensurePluginInitialized();

      final seed = jsonDecode(raw);
      if (seed is! Map) return false;
      final seedAccount = seed['accountId']?.toString().trim() ?? '';
      if (seedAccount.isNotEmpty && seedAccount != username.trim()) {
        return false;
      }
      final semesterStart = DateTime.tryParse(
        seed['semesterStartIso']?.toString() ?? '',
      );
      if (semesterStart == null) return false;
      final courses = (seed['courses'] as List? ?? const [])
          .whereType<Map>()
          .map((item) => Course.fromJson(Map<String, dynamic>.from(item)))
          .toList();
      if (courses.isEmpty) return false;

      await scheduleClassReminders(
        courses,
        semesterStart,
        totalWeeks: seed['totalWeeks'] as int? ?? 20,
        calendarRules: ScheduleCalendarRules.fromJson(seed['calendarRules']),
        accountId: seedAccount.isEmpty ? null : seedAccount,
      );
      return true;
    } catch (error) {
      debugPrint('[NOTIF] replenishFromSeedIfNeeded failed: $error');
      return false;
    }
  }

  static Future<void> cancelAllClassReminders() async {
    debugPrint('[NOTIF] cancelAllClassReminders');
    // Turning reminders off must also drop the persisted seed, otherwise the
    // background replenish would re-enable reminders the user disabled.
    await _clearReminderSeed();

    if (_usesNativeAndroidClassReminders) {
      try {
        await _cancelNativeAndroidClassReminders();
      } catch (error) {
        debugPrint('[NOTIF] native class reminder cancel failed: $error');
      }
      await _cancelLegacyPluginClassReminderIds();
      return;
    }

    try {
      await _plugin.cancelAll();
    } catch (error) {
      debugPrint('[NOTIF] plugin cancelAll failed: $error');
    }
  }
}

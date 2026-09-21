import 'dart:convert';
import 'dart:io';

import 'package:core/models/course.dart';
import 'package:data/data.dart';
import 'package:flutter_test/flutter_test.dart';

const _loginPageHtml = '''
<html><body>
<input name="execution" value="exec-token-123"/>
<input id="pwdEncryptSalt" value="1234567890abcdef"/>
</body></html>
''';

const _scheduleFrameworkHtml =
    '<html><body>jsxsd timetable framework page</body></html>';

const _validTimetableHtml = '''
<html><body>
<table id="timetable">
<tr><th></th><th>一</th><th>二</th><th>三</th><th>四</th><th>五</th><th>六</th><th>日</th></tr>
<tr>
  <td><div class="kbcontent">
    <font>计算机网络</font><br>
    <font title="教师">李老师</font><br>
    <font title="周次(节次)">1-16(周)[01-02节]</font><br>
    <font title="教室">B201</font>
  </div></td>
  <td></td><td></td><td></td><td></td><td></td><td></td><td></td>
</tr>
</table>
</body></html>
''';

class _ScriptedTransport {
  final List<
      ({
        String method,
        Uri uri,
        Map<String, String>? headers,
        List<int>? body,
      })> requests = [];
  final List<Future<SchoolHttpResponse> Function(String method, Uri uri)>
      handlers = [];

  Future<SchoolHttpResponse> call(
    String method,
    Uri uri, {
    Map<String, String>? headers,
    List<int>? body,
  }) async {
    requests.add((method: method, uri: uri, headers: headers, body: body));
    if (handlers.isEmpty) {
      return SchoolHttpResponse(statusCode: 404, headers: const {}, body: '');
    }
    final handler = handlers.removeAt(0);
    return handler(method, uri);
  }
}

SchoolHttpResponse _html(
  String body, {
  int status = 200,
  List<Cookie> cookies = const [],
}) {
  return SchoolHttpResponse(
    statusCode: status,
    headers: const {'content-type': 'text/html'},
    body: body,
    cookies: cookies,
  );
}

SchoolHttpResponse _redirect(String location, {int status = 302}) {
  return SchoolHttpResponse(
    statusCode: status,
    headers: {'location': location},
    body: '',
  );
}

void _scriptCasLogin(_ScriptedTransport transport) {
  transport.handlers.addAll([
    (method, uri) async => _html(_loginPageHtml),
    (method, uri) async => _redirect(
          'http://jwgln.cqjtu.edu.cn/jsxsd/framework/xsMain.jsp',
        ),
    (method, uri) async => _html(
          _scheduleFrameworkHtml,
          cookies: [Cookie('JSESSIONID', 'sess-abc')],
        ),
  ]);
}

/// A sliding-window session store implementation mirroring platform SessionService.
class _SlidingWindowSessionStore extends SelfHostedSessionStore {
  final Map<String, List<DateTime>> attemptsByUser = {};
  final Map<String, List<DateTime>> manualAttemptsByUser = {};
  final Map<String, int> securityFailuresByUser = {};
  final Map<String, DateTime> securityCooldownUntil = {};
  final Map<String, String> storedCas = {};
  final Map<String, String> storedJwg = {};
  DateTime? simulatedNow;

  @override
  Future<bool> canAttemptManualLogin(
    String username, {
    DateTime? now,
    int maxManualAttemptsPerHour = 5,
  }) async {
    final current = now ?? simulatedNow ?? DateTime.now();
    final cutoff = current.subtract(const Duration(hours: 1));
    final attempts = manualAttemptsByUser[username] ?? [];
    final valid = attempts.where((t) => t.isAfter(cutoff)).length;
    return valid < maxManualAttemptsPerHour;
  }

  @override
  Future<void> recordManualLoginAttempt(String username, {DateTime? now}) async {
    final current = now ?? simulatedNow ?? DateTime.now();
    manualAttemptsByUser.putIfAbsent(username, () => []).add(current);
  }

  @override
  Future<void> clearManualLoginAttempts(String username) async {
    manualAttemptsByUser.remove(username);
  }

  @override
  Future<bool> isInSecurityCooldown(String username, {DateTime? now}) async {
    final until = securityCooldownUntil[username];
    if (until == null) return false;
    final current = now ?? simulatedNow ?? DateTime.now();
    return until.isAfter(current);
  }

  @override
  Future<void> recordSecurityFailure(String username, {DateTime? now}) async {
    final count = (securityFailuresByUser[username] ?? 0) + 1;
    securityFailuresByUser[username] = count;
    if (count >= 3) {
      final current = now ?? simulatedNow ?? DateTime.now();
      securityCooldownUntil[username] = current.add(const Duration(minutes: 30));
    }
  }

  @override
  Future<void> resetSecurityFailures(String username) async {
    securityFailuresByUser.remove(username);
    securityCooldownUntil.remove(username);
  }

  @override
  Future<bool> canAttemptAutoLogin(
    String username, {
    DateTime? now,
    int maxAttemptsPerHour = 10,
  }) async {
    final current = now ?? simulatedNow ?? DateTime.now();
    final cutoff = current.subtract(const Duration(hours: 1));
    final attempts = attemptsByUser[username] ?? [];
    final valid = attempts.where((t) => t.isAfter(cutoff)).length;
    return valid < maxAttemptsPerHour;
  }

  @override
  Future<void> recordAutoLoginAttempt(String username, {DateTime? now}) async {
    final current = now ?? simulatedNow ?? DateTime.now();
    attemptsByUser.putIfAbsent(username, () => []).add(current);
  }

  @override
  Future<String?> loadCasCookies(String username) async => storedCas[username];
  @override
  Future<void> saveCasCookies(String username, String cookies) async {
    storedCas[username] = cookies;
  }

  @override
  Future<String?> loadJwgCookies(String username) async => storedJwg[username];
  @override
  Future<void> saveJwgCookies(String username, String cookies) async {
    storedJwg[username] = cookies;
  }

  @override
  Future<String?> loadEcardCookies(String username) async => null;
  @override
  Future<void> saveEcardCookies(String username, String cookies) async {}
  @override
  Future<String?> loadSessionId(String username) async => null;
  @override
  Future<void> saveSessionId(String username, String sessionId) async {}
  @override
  Future<String?> loadTicket(String username) async => null;
  @override
  Future<void> saveTicket(String username, String ticket) async {}
  @override
  Future<void> clearTicket(String username) async {}
  @override
  Future<void> clearLoginArtifacts(String username) async {
    storedCas.remove(username);
    storedJwg.remove(username);
    attemptsByUser.remove(username);
  }

  @override
  Future<String?> loadZoveToken(String username) async => null;
  @override
  Future<void> saveZoveToken(String username, String token) async {}
}

void main() {
  group('Empirical Challenge 1: ScheduleParser extreme and malformed HTML', () {
    test('empty string input throws SchoolSystemChangedFailure', () {
      expect(
        () => ScheduleParser.parse(''),
        throwsA(isA<SchoolSystemChangedFailure>().having(
          (f) => f.message,
          'message',
          contains('未在响应中找到课程表结构(#timetable)'),
        )),
      );
    });

    test(
        'whitespace-only input (spaces, tabs, newlines) throws SchoolSystemChangedFailure',
        () {
      expect(
        () => ScheduleParser.parse('   \t\r\n   \n\t  '),
        throwsA(isA<SchoolSystemChangedFailure>()),
      );
    });

    test('plain text without HTML tags throws SchoolSystemChangedFailure', () {
      expect(
        () => ScheduleParser.parse('Fatal Error: Gateway Timeout from nginx'),
        throwsA(isA<SchoolSystemChangedFailure>()),
      );
    });

    test(
        '500 internal error page without #timetable throws SchoolSystemChangedFailure',
        () {
      const errorHtml = '''
<!DOCTYPE html>
<html>
<head><title>500 Internal Server Error</title></head>
<body>
<h1>Internal Server Error</h1>
<p>The server encountered an internal error and was unable to complete your request.</p>
</body>
</html>
''';
      expect(
        () => ScheduleParser.parse(errorHtml),
        throwsA(isA<SchoolSystemChangedFailure>()),
      );
    });

    test('tables without id="timetable" throw SchoolSystemChangedFailure', () {
      const wrongTableHtml = '''
<html><body>
<table id="mainTable"><tr><td>Not timetable</td></tr></table>
<table class="timetable"><tr><td>Class timetable</td></tr></table>
<table name="timetable"><tr><td>Name timetable</td></tr></table>
<table data-id="timetable"><tr><td>Data-id timetable</td></tr></table>
</body></html>
''';
      expect(
        () => ScheduleParser.parse(wrongTableHtml),
        throwsA(isA<SchoolSystemChangedFailure>()),
      );
    });

    test('script tag containing "timetable" variable does not fool parser', () {
      const scriptHtml = '''
<html><head>
<script type="text/javascript">
  var timetable = { courses: [], semester: "2026-2027-1" };
  console.log("Loading timetable data...");
</script>
</head>
<body>
  <div>Timetable could not be loaded. Please refresh.</div>
</body></html>
''';
      expect(
        () => ScheduleParser.parse(scriptHtml),
        throwsA(isA<SchoolSystemChangedFailure>()),
      );
    });

    test('commented-out #timetable DOM throws SchoolSystemChangedFailure', () {
      const commentedHtml = '''
<html><body>
<!--
<table id="timetable">
  <tr><th></th><th>一</th></tr>
  <tr><td><div class="kbcontent"><font>已隐藏课程</font></div></td></tr>
</table>
-->
<div>The schedule is currently offline for maintenance.</div>
</body></html>
''';
      expect(
        () => ScheduleParser.parse(commentedHtml),
        throwsA(isA<SchoolSystemChangedFailure>()),
      );
    });

    test('element with id="timetable" that is not a table or has no table rows',
        () {
      const divTimetableHtml =
          '<html><body><div id="timetable">课表加载失败，请重试</div></body></html>';
      // Let's see what it does
      final result = ScheduleParser.parse(divTimetableHtml);
      // If it returns empty courses, this is an interesting edge case observation
      expect(result.courses, isEmpty);
    });

    test(
        'malformed HTML with unclosed tags before #timetable throws SchoolSystemChangedFailure',
        () {
      const unclosedHtml =
          '<html><body><div><p><span><table class="other"><tr><td>Unclosed';
      expect(
        () => ScheduleParser.parse(unclosedHtml),
        throwsA(isA<SchoolSystemChangedFailure>()),
      );
    });

    test('truncated HTML inside #timetable recovers gracefully without crash',
        () {
      const truncatedTableHtml = '''
<html><body>
<table id="timetable">
<tr><th></th><th>一</th><th>二</th></tr>
<tr>
  <td><div class="kbcontent">
    <font>操作系统
''';
      // Should not throw unhandled FormatException or StateError
      final result = ScheduleParser.parse(truncatedTableHtml);
      expect(result.courses, isA<List<Course>>());
    });

    test(
        'huge timetable (200 rows, 1400 cells, 200 courses) stress test completes fast',
        () {
      final buffer = StringBuffer();
      buffer.writeln('<html><body><table id="timetable">');
      buffer.writeln(
          '<tr><th></th><th>一</th><th>二</th><th>三</th><th>四</th><th>五</th><th>六</th><th>日</th></tr>');
      for (var r = 1; r <= 200; r++) {
        buffer.writeln('<tr>');
        for (var c = 0; c < 8; c++) {
          if (c == 1) {
            buffer.writeln('<td><div class="kbcontent">');
            buffer.writeln('<font>压力测试课程$r</font><br>');
            buffer.writeln('<font title="教师">测试教师$r</font><br>');
            buffer.writeln('<font title="周次(节次)">1-16(周)[01-02节]</font><br>');
            buffer.writeln('<font title="教室">C$r</font>');
            buffer.writeln('</div></td>');
          } else {
            buffer.writeln('<td></td>');
          }
        }
        buffer.writeln('</tr>');
      }
      buffer.writeln('</table></body></html>');

      final stopwatch = Stopwatch()..start();
      final result = ScheduleParser.parse(buffer.toString());
      stopwatch.stop();

      expect(result.courses, hasLength(200));
      expect(stopwatch.elapsedMilliseconds, lessThan(1000),
          reason: 'Parsing 200 courses should execute well within 1 second');
    });

    test(
        'multi-course cell with 3 sequential courses parses all 3 courses correctly',
        () {
      const multiCourseHtml = '''
<html><body>
<table id="timetable">
<tr><th></th><th>一</th><th>二</th><th>三</th><th>四</th><th>五</th><th>六</th><th>日</th></tr>
<tr>
  <td><div class="kbcontent">
    <font>高等数学A</font><br>
    <font title="教师">王老师</font><br>
    <font title="周次(节次)">1-8(周)[01-02节]</font><br>
    <font title="教室">A101</font><br>
    ----------------------<br>
    <font>大学物理B</font><br>
    <font title="教师">赵老师</font><br>
    <font title="周次(节次)">9-16(周)[01-02节]</font><br>
    <font title="教室">B202</font><br>
    ----------------------<br>
    <font>线性代数</font><br>
    <font title="教师">孙老师</font><br>
    <font title="周次(节次)">1-16(单周)[01-02节]</font><br>
    <font title="教室">C303</font>
  </div></td>
  <td></td><td></td><td></td><td></td><td></td><td></td><td></td>
</tr>
</table>
</body></html>
''';
      final result = ScheduleParser.parse(multiCourseHtml);
      expect(result.courses, hasLength(3));
      expect(result.courses[0].name, '高等数学A');
      expect(result.courses[1].name, '大学物理B');
      expect(result.courses[2].name, '线性代数');
    });

    test('cell with malformed time slot clamps slot between 1 and 13', () {
      const malformedSlotHtml = '''
<html><body>
<table id="timetable">
<tr><th></th><th>一</th><th>二</th><th>三</th><th>四</th><th>五</th><th>六</th><th>日</th></tr>
<tr>
  <td><div class="kbcontent">
    <font>超限课程</font><br>
    <font title="教师">周老师</font><br>
    <font title="周次(节次)">1-16(周)[00-99节]</font><br>
    <font title="教室">D404</font>
  </div></td>
  <td></td><td></td><td></td><td></td><td></td><td></td><td></td>
</tr>
</table>
</body></html>
''';
      final result = ScheduleParser.parse(malformedSlotHtml);
      expect(result.courses, hasLength(1));
      expect(result.courses.first.timeSlot, 1);
      expect(result.courses.first.endTimeSlot, 13);
    });

    test('timetable with remark row extracts remark text cleanly', () {
      const timetableWithRemarkHtml = '''
<html><body>
<table id="timetable">
<tr><th></th><th>一</th><th>二</th><th>三</th><th>四</th><th>五</th><th>六</th><th>日</th></tr>
<tr>
  <td><div class="kbcontent">
    <font>编译原理</font><br>
    <font title="周次(节次)">1-16(周)[03-04节]</font>
  </div></td>
  <td></td><td></td><td></td><td></td><td></td><td></td><td></td>
</tr>
<tr>
  <th>备注信息</th>
  <td>第18周为考试周，课程停上。</td>
</tr>
</table>
</body></html>
''';
      final result = ScheduleParser.parse(timetableWithRemarkHtml);
      expect(result.courses, hasLength(1));
      expect(result.remark, '第18周为考试周，课程停上。');
    });

    test(
        'valid timetable containing authserver/login link in footer parses normally without throwing',
        () {
      const timetableWithFooterHtml = '''
<html><body>
<table id="timetable">
<tr><th></th><th>一</th></tr>
<tr>
  <td><div class="kbcontent">
    <font>软件工程</font><br>
    <font title="教师">刘老师</font><br>
    <font title="周次(节次)">1-16(周)[01-02节]</font><br>
    <font title="教室">E505</font>
  </div></td>
</tr>
</table>
<footer><a href="https://ids.cqjtu.edu.cn/authserver/login">退出系统</a></footer>
</body></html>
''';
      final result = ScheduleParser.parse(timetableWithFooterHtml);
      expect(result.courses, hasLength(1));
      expect(result.courses.first.name, '软件工程');
    });

    test('WAF marker has precedence over CAS login marker when both present',
        () {
      const mixedHtml = '''
<html><head>
<script>var \$_ts = window["\$_ts"];</script>
</head><body>
<form id="casLoginForm" action="authserver/login"></form>
</body></html>
''';
      expect(
        () => ScheduleParser.parse(mixedHtml),
        throwsA(isA<BotChallengeFailure>()),
      );
    });

    test(
        'CAS login marker has precedence over Captcha marker when both present',
        () {
      const mixedHtml = '''
<html><body>
<div id="casLoginForm">请重新登录</div>
<div>请输入验证码</div>
</body></html>
''';
      expect(
        () => ScheduleParser.parse(mixedHtml),
        throwsA(isA<SessionExpiredFailure>()),
      );
    });
  });

  group('Empirical Challenge 2: Semester fallback edge cases', () {
    test('tab and newline characters fall back to current semester', () async {
      final transport = _ScriptedTransport();
      _scriptCasLogin(transport);
      transport.handlers.add((method, uri) async => _html(_validTimetableHtml));

      final gateway = DirectSchoolCampusGateway(transport: transport.call);
      await gateway.getSchedule('123456789012', 'secret',
          semester: '\t\n\r  \t');

      final scheduleReq = transport.requests.last;
      final bodyString = utf8.decode(scheduleReq.body!);
      final match =
          RegExp(r'xnxq01id=(\d{4}-\d{4}-[12])').firstMatch(bodyString);
      expect(match, isNotNull);
    });

    test('third term (summer session) semester string is preserved exactly',
        () async {
      final transport = _ScriptedTransport();
      _scriptCasLogin(transport);
      transport.handlers.add((method, uri) async => _html(_validTimetableHtml));

      final gateway = DirectSchoolCampusGateway(transport: transport.call);
      await gateway.getSchedule('123456789012', 'secret',
          semester: '2025-2026-3');

      final scheduleReq = transport.requests.last;
      final bodyString = utf8.decode(scheduleReq.body!);
      expect(bodyString, 'xnxq01id=2025-2026-3');
    });

    test('custom school term string is preserved exactly', () async {
      final transport = _ScriptedTransport();
      _scriptCasLogin(transport);
      transport.handlers.add((method, uri) async => _html(_validTimetableHtml));

      final gateway = DirectSchoolCampusGateway(transport: transport.call);
      await gateway.getSchedule('123456789012', 'secret',
          semester: '2026-summer-short');

      final scheduleReq = transport.requests.last;
      final bodyString = utf8.decode(scheduleReq.body!);
      expect(bodyString, 'xnxq01id=2026-summer-short');
    });
  });

  group(
      'Empirical Challenge 3: Rate limiting sliding window, boundaries, and concurrency',
      () {
    test(
        'boundary condition: exactly 10 attempts pass, 11th attempt is blocked',
        () async {
      final store = _SlidingWindowSessionStore();
      final baseTime = DateTime(2026, 9, 19, 10, 0, 0);

      // Record 9 attempts within the last 40 minutes
      for (var i = 0; i < 9; i++) {
        await store.recordAutoLoginAttempt(
          'user_boundary',
          now: baseTime.add(Duration(minutes: i * 4)),
        );
      }

      // At 10:45, 9 attempts recorded -> canAttemptAutoLogin should be true
      expect(
        await store.canAttemptAutoLogin(
          'user_boundary',
          now: baseTime.add(const Duration(minutes: 45)),
        ),
        isTrue,
      );

      // Record 10th attempt at 10:45
      await store.recordAutoLoginAttempt(
        'user_boundary',
        now: baseTime.add(const Duration(minutes: 45)),
      );

      // At 10:50, exactly 10 attempts in the hour -> canAttemptAutoLogin must be FALSE
      expect(
        await store.canAttemptAutoLogin(
          'user_boundary',
          now: baseTime.add(const Duration(minutes: 50)),
        ),
        isFalse,
      );
    });

    test(
        'sliding window: 10 attempts expire after 1 hour, unblocking auto-login',
        () async {
      final store = _SlidingWindowSessionStore();
      final baseTime = DateTime(2026, 9, 19, 10, 0, 0);

      // 10 attempts all made at 10:00:00
      for (var i = 0; i < 10; i++) {
        await store.recordAutoLoginAttempt('user_expire', now: baseTime);
      }

      // At 10:59:59 (59 minutes later), still blocked
      expect(
        await store.canAttemptAutoLogin(
          'user_expire',
          now: baseTime.add(const Duration(minutes: 59, seconds: 59)),
        ),
        isFalse,
      );

      // At 11:00:01 (60 minutes and 1 second later), window has slid past 10:00:00
      expect(
        await store.canAttemptAutoLogin(
          'user_expire',
          now: baseTime.add(const Duration(minutes: 60, seconds: 1)),
        ),
        isTrue,
      );
    });

    test(
        'sliding window with staggered attempts partially unblocks as old ones roll out',
        () async {
      final store = _SlidingWindowSessionStore();
      final baseTime = DateTime(2026, 9, 19, 10, 0, 0);

      // 6 attempts at 10:00:00
      for (var i = 0; i < 6; i++) {
        await store.recordAutoLoginAttempt('user_stagger', now: baseTime);
      }

      // 4 attempts at 10:30:00
      final halfHour = baseTime.add(const Duration(minutes: 30));
      for (var i = 0; i < 4; i++) {
        await store.recordAutoLoginAttempt('user_stagger', now: halfHour);
      }

      // Total is 10 attempts in window at 10:45:00 -> BLOCKED
      final check1 = baseTime.add(const Duration(minutes: 45));
      expect(await store.canAttemptAutoLogin('user_stagger', now: check1),
          isFalse);

      // At 11:01:00 (61 minutes after baseTime):
      // The 6 attempts from 10:00 have expired. Only 4 attempts (from 10:30) remain.
      final check2 = baseTime.add(const Duration(minutes: 61));
      expect(
          await store.canAttemptAutoLogin('user_stagger', now: check2), isTrue);

      // We can record up to 6 more attempts before being blocked again
      for (var i = 0; i < 6; i++) {
        await store.recordAutoLoginAttempt('user_stagger', now: check2);
      }

      // Now 4 + 6 = 10 attempts active -> BLOCKED again
      expect(await store.canAttemptAutoLogin('user_stagger', now: check2),
          isFalse);
    });

    test('multi-user isolation: User A blocked does not affect User B',
        () async {
      final store = _SlidingWindowSessionStore();
      final now = DateTime(2026, 9, 19, 10, 0, 0);

      for (var i = 0; i < 10; i++) {
        await store.recordAutoLoginAttempt('user_A', now: now);
      }

      expect(await store.canAttemptAutoLogin('user_A', now: now), isFalse);
      expect(await store.canAttemptAutoLogin('user_B', now: now), isTrue);
    });

    test(
        'concurrency: 10 simultaneous getSchedule calls deduplicate CAS login to exactly 1 request',
        () async {
      final store = _SlidingWindowSessionStore();
      final transport = _ScriptedTransport();

      // Script exactly ONE CAS login sequence + 10 schedule responses
      _scriptCasLogin(transport);
      for (var i = 0; i < 10; i++) {
        transport.handlers
            .add((method, uri) async => _html(_validTimetableHtml));
      }

      final gateway = DirectSchoolCampusGateway(
        sessionStore: store,
        transport: transport.call,
      );

      // Launch 10 simultaneous getSchedule calls on the same account
      final futures = List.generate(
        10,
        (_) => gateway.getSchedule('123456789012', 'secret'),
      );

      final results = await Future.wait(futures);

      // All 10 succeeded with 1 course each
      for (final res in results) {
        expect(res.courses, hasLength(1));
      }

      // CAS login POST to ids.cqjtu.edu.cn must be executed EXACTLY ONCE
      final casPosts = transport.requests.where(
        (r) => r.method == 'POST' && r.uri.host == 'ids.cqjtu.edu.cn',
      );
      expect(casPosts, hasLength(1));

      // Auto-login attempts recorded must be EXACTLY ONE, not 10!
      expect(store.attemptsByUser['123456789012'], hasLength(1));
    });

    test(
        'concurrency: 10 simultaneous calls when rate limit exhausted all fail with SessionExpiredFailure without hitting network',
        () async {
      final store = _SlidingWindowSessionStore();
      final baseTime = DateTime(2026, 9, 19, 10, 0, 0);
      store.simulatedNow = baseTime;

      // Exhaust 10 attempts
      for (var i = 0; i < 10; i++) {
        await store.recordAutoLoginAttempt('rate_limited_user', now: baseTime);
      }

      final transport = _ScriptedTransport();
      final gateway = DirectSchoolCampusGateway(
        sessionStore: store,
        transport: transport.call,
      );

      final futures = List.generate(
        10,
        (_) => gateway.getSchedule('rate_limited_user', 'secret'),
      );

      // All 10 must throw SessionExpiredFailure
      for (final f in futures) {
        expect(
          f,
          throwsA(
            isA<SessionExpiredFailure>().having(
              (e) => e.message,
              'message',
              contains('自动登录已达每小时上限（6次）'),
            ),
          ),
        );
      }

      // Zero network requests made
      expect(transport.requests, isEmpty);
      // Still exactly 10 attempts recorded (none added)
      expect(store.attemptsByUser['rate_limited_user'], hasLength(10));
    });

    test(
        'manual loginWithPassword succeeds and does not increment auto-login attempt counter',
        () async {
      final store = _SlidingWindowSessionStore();
      final baseTime = DateTime(2026, 9, 19, 10, 0, 0);
      store.simulatedNow = baseTime;

      // Pre-fill 10 attempts to exhaust auto-login
      for (var i = 0; i < 10; i++) {
        await store.recordAutoLoginAttempt('manual_user', now: baseTime);
      }
      expect(await store.canAttemptAutoLogin('manual_user', now: baseTime),
          isFalse);

      final transport = _ScriptedTransport();
      _scriptCasLogin(transport);

      final gateway = DirectSchoolCampusGateway(
        sessionStore: store,
        transport: transport.call,
      );

      // Manual login must succeed even when auto-login is blocked
      await gateway.loginWithPassword('manual_user', 'secret');

      // 1 CAS login POST was performed
      final casPosts = transport.requests.where(
        (r) => r.method == 'POST' && r.uri.host == 'ids.cqjtu.edu.cn',
      );
      expect(casPosts, hasLength(1));

      // Attempt count remains 10 (manual login does not call recordAutoLoginAttempt)
      expect(store.attemptsByUser['manual_user'], hasLength(10));
    });

    test(
        'manual login fails 5 times with AuthInvalidFailure then 6th attempt is blocked with ManualLoginRateLimitedFailure',
        () async {
      final store = _SlidingWindowSessionStore();
      final baseTime = DateTime(2026, 9, 19, 10, 0, 0);
      store.simulatedNow = baseTime;

      final transport = _ScriptedTransport();
      // Script 5 login failures (GET login page, then POST resulting in error message)
      for (var i = 0; i < 5; i++) {
        transport.handlers.addAll([
          (m, u) async => _html(_loginPageHtml),
          (m, u) async => _html('<html><body><form id="casLoginForm"><input name="execution" value="e$i"/></form><span id="msg">用户名或密码错误</span></body></html>'),
        ]);
      }

      final gateway = DirectSchoolCampusGateway(
        sessionStore: store,
        transport: transport.call,
      );

      // Perform 5 failed manual logins
      for (var i = 0; i < 5; i++) {
        await expectLater(
          gateway.loginWithPassword('manual_fail_user', 'wrong_pwd'),
          throwsA(isA<AuthInvalidFailure>()),
        );
      }

      expect(store.manualAttemptsByUser['manual_fail_user'], hasLength(5));

      // 6th attempt is blocked immediately by ManualLoginRateLimitedFailure without network call
      final reqCountBefore = transport.requests.length;
      await expectLater(
        gateway.loginWithPassword('manual_fail_user', 'any_pwd'),
        throwsA(isA<ManualLoginRateLimitedFailure>()),
      );
      expect(transport.requests.length, reqCountBefore);

      // Web ticket login clears manual login failures
      final ticketTransport = _ScriptedTransport();
      ticketTransport.handlers.add((method, uri) async {
        return _html(
          _scheduleFrameworkHtml,
          cookies: [Cookie('JSESSIONID', 'sess-t')],
        );
      });
      final gatewayTicket = DirectSchoolCampusGateway(
        sessionStore: store,
        transport: ticketTransport.call,
      );
      await gatewayTicket.loginWithTicket('manual_fail_user', 'ST-valid-ticket');
      expect(store.manualAttemptsByUser['manual_fail_user'], isNull);
    });

    test(
        'security failures enter 30-min cooldown and block silent auto-login',
        () async {
      final store = _SlidingWindowSessionStore();
      final baseTime = DateTime(2026, 9, 19, 10, 0, 0);
      store.simulatedNow = baseTime;

      // 3 security failures recorded
      await store.recordSecurityFailure('sec_user', now: baseTime);
      await store.recordSecurityFailure('sec_user', now: baseTime);
      await store.recordSecurityFailure('sec_user', now: baseTime);

      expect(await store.isInSecurityCooldown('sec_user', now: baseTime), isTrue);

      final transport = _ScriptedTransport();
      final gateway = DirectSchoolCampusGateway(
        sessionStore: store,
        transport: transport.call,
      );

      // Silent ensureAuth must throw SessionExpiredFailure('触发安全防护，请稍后手动登录')
      expect(
        () => gateway.getSchedule('sec_user', 'pwd'),
        throwsA(
          isA<SessionExpiredFailure>().having(
            (e) => e.message,
            'message',
            contains('触发安全防护，请稍后手动登录'),
          ),
        ),
      );
      expect(transport.requests, isEmpty);
    });
  });
}

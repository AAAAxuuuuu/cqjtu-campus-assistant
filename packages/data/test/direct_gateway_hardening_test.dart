import 'dart:convert';
import 'dart:io';

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
    <font>高等数学</font><br>
    <font title="教师">张老师</font><br>
    <font title="周次(节次)">1-16(周)[01-02节]</font><br>
    <font title="教室">A101</font>
  </div></td>
  <td></td><td></td><td></td><td></td><td></td><td></td><td></td>
</tr>
</table>
</body></html>
''';

const _emptyTimetableHtml = '''
<html><body>
<table id="timetable">
<tr><th></th><th>一</th><th>二</th><th>三</th><th>四</th><th>五</th><th>六</th><th>日</th></tr>
<tr><td></td><td></td><td></td><td></td><td></td><td></td><td></td><td></td></tr>
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

class _MockSessionStore extends SelfHostedSessionStore {
  final Map<String, List<DateTime>> attemptsByUser = {};
  bool allowAutoLogin = true;
  final Map<String, String> storedCas = {};
  final Map<String, String> storedJwg = {};
  final Set<String> _brokenUsers = {};

  @override
  Future<bool> isAuthCircuitBroken(String username) async =>
      _brokenUsers.contains(username);

  @override
  Future<void> markAuthCircuitBroken(String username) async {
    _brokenUsers.add(username);
  }

  @override
  Future<void> resetAuthCircuitBreaker(String username) async {
    _brokenUsers.remove(username);
  }

  @override
  Future<bool> canAttemptAutoLogin(
    String username, {
    DateTime? now,
    int maxAttemptsPerHour = 10,
  }) async {
    if (!allowAutoLogin) return false;
    if (_brokenUsers.contains(username)) return false;
    final current = now ?? DateTime.now();
    final cutoff = current.subtract(const Duration(hours: 1));
    final attempts = attemptsByUser[username] ?? [];
    final valid = attempts.where((t) => t.isAfter(cutoff)).length;
    return valid < maxAttemptsPerHour;
  }

  @override
  Future<void> recordAutoLoginAttempt(String username, {DateTime? now}) async {
    attemptsByUser.putIfAbsent(username, () => []).add(now ?? DateTime.now());
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
  Future<void> clearLoginArtifacts(String username) async {}
  @override
  Future<String?> loadZoveToken(String username) async => null;
  @override
  Future<void> saveZoveToken(String username, String token) async {}
}

class _DefaultNoOpSessionStore extends SelfHostedSessionStore {
  @override
  Future<String?> loadCasCookies(String username) async => null;
  @override
  Future<void> saveCasCookies(String username, String cookies) async {}
  @override
  Future<String?> loadJwgCookies(String username) async => null;
  @override
  Future<void> saveJwgCookies(String username, String cookies) async {}
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
  Future<void> clearLoginArtifacts(String username) async {}
  @override
  Future<String?> loadZoveToken(String username) async => null;
  @override
  Future<void> saveZoveToken(String username, String token) async {}
}

void main() {
  group('R1: ScheduleParser failure classification', () {
    test(r'throws BotChallengeFailure when HTML contains WAF $_ts marker', () {
      const wafHtml =
          '<html><head><script>var \$_ts = window["\$_ts"];</script></head><body>WAF challenge</body></html>';
      expect(
        () => ScheduleParser.parse(wafHtml),
        throwsA(
          isA<BotChallengeFailure>().having(
            (f) => f.message,
            'message',
            contains('教务系统开启了人机验证'),
          ),
        ),
      );
    });

    test(
        'throws BotChallengeFailure when HTML contains WAF r="m" or r=\'m\' marker',
        () {
      const wafHtmlSingleQuote =
          '<html><head><script r=\'m\'>console.log("challenge");</script></head></html>';
      const wafHtmlDoubleQuote =
          '<html><head><script r="m">console.log("challenge");</script></head></html>';

      expect(
        () => ScheduleParser.parse(wafHtmlSingleQuote),
        throwsA(isA<BotChallengeFailure>()),
      );
      expect(
        () => ScheduleParser.parse(wafHtmlDoubleQuote),
        throwsA(isA<BotChallengeFailure>()),
      );
    });

    test(
        'throws SessionExpiredFailure when HTML contains CAS redirect or session timeout markers',
        () {
      const casLoginHtml =
          '<html><body><form id="casLoginForm" action="authserver/login"></form></body></html>';
      const reLoginHtml = '<html><body><div>请重新登录系统</div></body></html>';
      const timeoutHtml = '<html><body><div>会话超时，请退出重试</div></body></html>';
      const notLoggedInHtml = '<html><body><div>系统维护中或未登录</div></body></html>';
      const saltHtml =
          '<html><body><input id="pwdEncryptSalt" value="salt"/></body></html>';

      expect(
        () => ScheduleParser.parse(casLoginHtml),
        throwsA(
          isA<SessionExpiredFailure>().having(
            (f) => f.message,
            'message',
            contains('教务会话已过期，请重新登录'),
          ),
        ),
      );
      expect(
        () => ScheduleParser.parse(reLoginHtml),
        throwsA(isA<SessionExpiredFailure>()),
      );
      expect(
        () => ScheduleParser.parse(timeoutHtml),
        throwsA(isA<SessionExpiredFailure>()),
      );
      expect(
        () => ScheduleParser.parse(notLoggedInHtml),
        throwsA(isA<SessionExpiredFailure>()),
      );
      expect(
        () => ScheduleParser.parse(saltHtml),
        throwsA(isA<SessionExpiredFailure>()),
      );
    });

    test('throws CaptchaRequiredFailure when HTML contains captcha marker', () {
      const captchaChineseHtml = '<html><body><div>请输入验证码</div></body></html>';
      const captchaEnglishHtml =
          '<html><body><img src="captcha.jpg"/></body></html>';

      expect(
        () => ScheduleParser.parse(captchaChineseHtml),
        throwsA(
          isA<CaptchaRequiredFailure>().having(
            (f) => f.message,
            'message',
            contains('教务系统需要安全验证'),
          ),
        ),
      );
      expect(
        () => ScheduleParser.parse(captchaEnglishHtml),
        throwsA(isA<CaptchaRequiredFailure>()),
      );
    });

    test(
        'throws SchoolSystemChangedFailure when HTML has no #timetable and no known markers',
        () {
      const unknownHtml =
          '<html><body><div id="new_schedule_ui">页面改版，请使用新版</div></body></html>';

      expect(
        () => ScheduleParser.parse(unknownHtml),
        throwsA(
          isA<SchoolSystemChangedFailure>().having(
            (f) => f.message,
            'message',
            contains('未在响应中找到课程表结构(#timetable)'),
          ),
        ),
      );
    });

    test('under no circumstance does missing #timetable return empty courses',
        () {
      const emptyHtml = '<html><body></body></html>';

      expect(
        () => ScheduleParser.parse(emptyHtml),
        throwsA(isA<CampusFailure>()),
      );
    });

    test(
        'parses legitimate empty timetable table to courses: [] without throwing',
        () {
      final result = ScheduleParser.parse(_emptyTimetableHtml);
      expect(result.courses, isEmpty);
    });
  });

  group('R4: Semester fallback in getSchedule', () {
    test('falls back to current semester when semester parameter is null',
        () async {
      final transport = _ScriptedTransport();
      _scriptCasLogin(transport);
      transport.handlers.add((method, uri) async => _html(_validTimetableHtml));

      final gateway = DirectSchoolCampusGateway(transport: transport.call);
      final result = await gateway.getSchedule('123456789012', 'secret');

      expect(result.courses, hasLength(1));

      // The last request is the schedule POST
      final scheduleReq = transport.requests.last;
      expect(scheduleReq.method, 'POST');
      final bodyString = utf8.decode(scheduleReq.body!);
      expect(bodyString, contains('xnxq01id='));
      // Semester pattern e.g. 2026-2027-1 or 2025-2026-2
      final match =
          RegExp(r'xnxq01id=(\d{4}-\d{4}-[12])').firstMatch(bodyString);
      expect(match, isNotNull,
          reason: 'Must send a formatted current semester');
    });

    test(
        'falls back to current semester when semester parameter is empty or whitespace',
        () async {
      final transport = _ScriptedTransport();
      _scriptCasLogin(transport);
      transport.handlers.add((method, uri) async => _html(_validTimetableHtml));

      final gateway = DirectSchoolCampusGateway(transport: transport.call);
      await gateway.getSchedule('123456789012', 'secret', semester: '   ');

      final scheduleReq = transport.requests.last;
      final bodyString = utf8.decode(scheduleReq.body!);
      expect(bodyString, contains('xnxq01id='));
      final match =
          RegExp(r'xnxq01id=(\d{4}-\d{4}-[12])').firstMatch(bodyString);
      expect(match, isNotNull);
    });

    test('preserves explicitly supplied semester parameter', () async {
      final transport = _ScriptedTransport();
      _scriptCasLogin(transport);
      transport.handlers.add((method, uri) async => _html(_validTimetableHtml));

      final gateway = DirectSchoolCampusGateway(transport: transport.call);
      await gateway.getSchedule('123456789012', 'secret',
          semester: '2027-2028-2');

      final scheduleReq = transport.requests.last;
      final bodyString = utf8.decode(scheduleReq.body!);
      expect(bodyString, 'xnxq01id=2027-2028-2');
    });
  });

  group('R3: Auto-login rate limiting interface and enforcement', () {
    test(
        'SelfHostedSessionStore default methods provide non-breaking implementations',
        () async {
      final store = _DefaultNoOpSessionStore();
      expect(await store.canAttemptAutoLogin('user1'), isTrue);
      // should complete without exception
      await store.recordAutoLoginAttempt('user1');
    });

    test(
        'silent ensureAuth blocks login when rate limiter returns false and sends 0 network requests',
        () async {
      final store = _MockSessionStore();
      store.allowAutoLogin = false; // Rate limit exhausted

      final transport = _ScriptedTransport();
      final gateway = DirectSchoolCampusGateway(
        sessionStore: store,
        transport: transport.call,
      );

      expect(
        () => gateway.getSchedule('123456789012', 'secret'),
        throwsA(
          isA<SessionExpiredFailure>().having(
            (f) => f.message,
            'message',
            '自动登录已达每小时上限（6次），请稍后重试或手动登录',
          ),
        ),
      );

      // Verify no network requests were sent at all to CAS
      expect(transport.requests, isEmpty);
      expect(store.attemptsByUser, isEmpty);
    });

    test('silent ensureAuth records auto-login attempt when allowed', () async {
      final store = _MockSessionStore();
      final transport = _ScriptedTransport();
      _scriptCasLogin(transport);
      transport.handlers.add((method, uri) async => _html(_validTimetableHtml));

      final gateway = DirectSchoolCampusGateway(
        sessionStore: store,
        transport: transport.call,
      );

      final result = await gateway.getSchedule('123456789012', 'secret');
      expect(result.courses, hasLength(1));
      expect(store.attemptsByUser['123456789012'], hasLength(1));
    });

    test(
        'forceRelogin on session expiry blocks with SessionExpiredFailure when rate limited',
        () async {
      final store = _MockSessionStore();
      final transport = _ScriptedTransport();
      _scriptCasLogin(transport);
      // First schedule POST returns valid timetable
      transport.handlers.add((method, uri) async => _html(_validTimetableHtml));

      final gateway = DirectSchoolCampusGateway(
        sessionStore: store,
        transport: transport.call,
      );

      final initial = await gateway.getSchedule('123456789012', 'secret');
      expect(initial.courses, hasLength(1));
      expect(store.attemptsByUser['123456789012'], hasLength(1));

      // Now session expires on next schedule request
      transport.handlers.add(
        (method, uri) async => _html(
          '<html><body>authserver/login redirect</body></html>',
        ),
      );

      // Exhaust rate limit quota before retry relogin
      store.allowAutoLogin = false;

      expect(
        () => gateway.getSchedule('123456789012', 'secret'),
        throwsA(
          isA<SessionExpiredFailure>().having(
            (f) => f.message,
            'message',
            '自动登录已达每小时上限（6次），请稍后重试或手动登录',
          ),
        ),
      );

      // Verify only 1 CAS login was done (the initial one), no relogin POST sent
      final casPosts = transport.requests.where(
        (r) => r.method == 'POST' && r.uri.host == 'ids.cqjtu.edu.cn',
      );
      expect(casPosts, hasLength(1));
    });

    test('manual loginWithPassword is NOT blocked by auto-login rate limiter',
        () async {
      final store = _MockSessionStore();
      store.allowAutoLogin = false; // Rate limit exhausted for silent login

      final transport = _ScriptedTransport();
      _scriptCasLogin(transport);

      final gateway = DirectSchoolCampusGateway(
        sessionStore: store,
        transport: transport.call,
      );

      // Manual login should succeed even when allowAutoLogin is false
      await gateway.loginWithPassword('123456789012', 'secret');

      final casPosts = transport.requests.where(
        (r) => r.method == 'POST' && r.uri.host == 'ids.cqjtu.edu.cn',
      );
      expect(casPosts, hasLength(1));
    });

    test('enforces exactly 10 attempts per hour, 11th attempt is blocked',
        () async {
      final store = _MockSessionStore();
      final transport = _ScriptedTransport();

      // Set up 10 successful logins for 10 distinct accounts
      for (var i = 0; i < 10; i++) {
        _scriptCasLogin(transport);
        transport.handlers
            .add((method, uri) async => _html(_validTimetableHtml));
      }

      for (var i = 0; i < 10; i++) {
        final gateway = DirectSchoolCampusGateway(
          sessionStore: store,
          transport: transport.call,
        );
        final result = await gateway.getSchedule('user_$i', 'secret');
        expect(result.courses, hasLength(1));
      }

      expect(store.attemptsByUser.keys, hasLength(10));

      // Now pre-populate 10 attempts in the last hour for 'user_heavy'
      final now = DateTime.now();
      for (var i = 0; i < 10; i++) {
        await store.recordAutoLoginAttempt(
          'user_heavy',
          now: now.subtract(Duration(minutes: i * 3)),
        );
      }

      final gateway11 = DirectSchoolCampusGateway(
        sessionStore: store,
        transport: transport.call,
      );

      final requestCountBefore = transport.requests.length;
      expect(
        () => gateway11.getSchedule('user_heavy', 'secret'),
        throwsA(
          isA<SessionExpiredFailure>().having(
            (f) => f.message,
            'message',
            '自动登录已达每小时上限（6次），请稍后重试或手动登录',
          ),
        ),
      );

      // Verify no network calls were made for the 11th attempt
      expect(transport.requests.length, requestCountBefore);
    });

    test(
        'successful stored cookies restore does not consume auto-login rate limit attempts',
        () async {
      final store = _MockSessionStore();
      store.storedCas['123456789012'] = 'CASTGC=token-valid';
      store.storedJwg['123456789012'] = 'JSESSIONID=sess-valid';

      final transport = _ScriptedTransport();
      // isSessionValid probes scheduleUrl and finds timetable
      transport.handlers.add((method, uri) async => _html(_validTimetableHtml));
      // getSchedule then requests scheduleUrl and finds timetable
      transport.handlers.add((method, uri) async => _html(_validTimetableHtml));

      final gateway = DirectSchoolCampusGateway(
        sessionStore: store,
        transport: transport.call,
      );

      final result = await gateway.getSchedule('123456789012', 'secret');
      expect(result.courses, hasLength(1));

      // Zero CAS login POSTs, and zero auto-login attempts recorded!
      final casPosts = transport.requests.where(
        (r) => r.method == 'POST' && r.uri.host == 'ids.cqjtu.edu.cn',
      );
      expect(casPosts, isEmpty);
      expect(store.attemptsByUser, isEmpty);
    });
  });

  group('R2 & R4: Auth Circuit Breaker & Cookie Reuse Defense', () {
    test(
        'AuthInvalidFailure on CAS login trips circuit breaker and blocks subsequent silent requests with 0 network calls',
        () async {
      final store = _MockSessionStore();
      final transport = _ScriptedTransport();

      // Script 1 failed CAS login
      transport.handlers.add((method, uri) async => _html(_loginPageHtml));
      transport.handlers.add((method, uri) async =>
          _html('<html><body><div id="showErrorTip">账号或密码错误</div></body></html>'));

      final gateway = DirectSchoolCampusGateway(
        sessionStore: store,
        transport: transport.call,
      );

      // First call throws AuthInvalidFailure and trips breaker
      await expectLater(
        () => gateway.getSchedule('123456789012', 'wrong_pwd'),
        throwsA(isA<AuthInvalidFailure>()),
      );

      expect(await gateway.isAuthCircuitBroken('123456789012'), isTrue);
      expect(await store.isAuthCircuitBroken('123456789012'), isTrue);

      final postCountAfterFirst = transport.requests
          .where((r) => r.method == 'POST' && r.uri.host == 'ids.cqjtu.edu.cn')
          .length;
      expect(postCountAfterFirst, equals(1));

      // Subsequent silent call is immediately blocked by circuit breaker
      await expectLater(
        () => gateway.getSchedule('123456789012', 'wrong_pwd'),
        throwsA(isA<AuthInvalidFailure>()),
      );

      // Verify ZERO additional network requests were made
      final postCountAfterSecond = transport.requests
          .where((r) => r.method == 'POST' && r.uri.host == 'ids.cqjtu.edu.cn')
          .length;
      expect(postCountAfterSecond, equals(1));

      // Even another method like getCampusCardBalance is blocked without network calls
      await expectLater(
        () => gateway.getCampusCardBalance('123456789012', 'wrong_pwd'),
        throwsA(isA<AuthInvalidFailure>()),
      );
      final postCountAfterThird = transport.requests
          .where((r) => r.method == 'POST' && r.uri.host == 'ids.cqjtu.edu.cn')
          .length;
      expect(postCountAfterThird, equals(1));
    });

    test(
        'Circuit breaker blocks subsequent requests even when rate limit quota is far from 10/hr',
        () async {
      final store = _MockSessionStore();
      final transport = _ScriptedTransport();

      transport.handlers.add((method, uri) async => _html(_loginPageHtml));
      transport.handlers.add((method, uri) async =>
          _html('<html><body><span id="msg">用户名或密码错误</span></body></html>'));

      final gateway = DirectSchoolCampusGateway(
        sessionStore: store,
        transport: transport.call,
      );

      // Only 1 attempt made
      await expectLater(
        () => gateway.getSchedule('u_cb_1', 'bad'),
        throwsA(isA<AuthInvalidFailure>()),
      );

      // Store shows only 1 attempt recorded, well below 10/hr limit
      expect(store.attemptsByUser['u_cb_1'], hasLength(1));

      // But circuit breaker is tripped
      expect(await store.isAuthCircuitBroken('u_cb_1'), isTrue);
      expect(await store.canAttemptAutoLogin('u_cb_1'), isFalse);

      // Next call is blocked by circuit breaker without network calls
      final reqCount = transport.requests.length;
      await expectLater(
        () => gateway.getSchedule('u_cb_1', 'bad'),
        throwsA(isA<AuthInvalidFailure>()),
      );
      expect(transport.requests.length, equals(reqCount));
    });

    test('Account isolation: circuit breaking user_A does not block user_B',
        () async {
      final store = _MockSessionStore();
      final transport = _ScriptedTransport();

      // Script failure for user_A
      transport.handlers.add((method, uri) async => _html(_loginPageHtml));
      transport.handlers.add((method, uri) async =>
          _html('<html><body><div id="showErrorTip">账号或密码错误</div></body></html>'));

      // Script success for user_B
      _scriptCasLogin(transport);
      transport.handlers.add((method, uri) async => _html(_validTimetableHtml));

      final gateway = DirectSchoolCampusGateway(
        sessionStore: store,
        transport: transport.call,
      );

      await expectLater(
        () => gateway.getSchedule('user_A', 'wrong'),
        throwsA(isA<AuthInvalidFailure>()),
      );
      expect(await gateway.isAuthCircuitBroken('user_A'), isTrue);
      expect(await gateway.isAuthCircuitBroken('user_B'), isFalse);

      final resultB = await gateway.getSchedule('user_B', 'correct');
      expect(resultB.courses, hasLength(1));
    });

    test(
        'Manual loginWithPassword is NOT blocked by circuit breaker and resets it on success',
        () async {
      final store = _MockSessionStore();
      final transport = _ScriptedTransport();

      // Trip circuit breaker for user_m
      await store.markAuthCircuitBroken('user_m');
      expect(await store.isAuthCircuitBroken('user_m'), isTrue);

      // Script successful login for manual loginWithPassword
      _scriptCasLogin(transport);

      final gateway = DirectSchoolCampusGateway(
        sessionStore: store,
        transport: transport.call,
      );

      // Manual login should proceed despite breaker
      await gateway.loginWithPassword('user_m', 'new_pwd');

      // Circuit breaker is now reset
      expect(await gateway.isAuthCircuitBroken('user_m'), isFalse);
      expect(await store.isAuthCircuitBroken('user_m'), isFalse);

      // Subsequent schedule call proceeds:
      // isSessionValid probes scheduleUrl and finds timetable
      transport.handlers.add((method, uri) async => _html(_validTimetableHtml));
      // getSchedule then requests scheduleUrl and finds timetable
      transport.handlers.add((method, uri) async => _html(_validTimetableHtml));
      final result = await gateway.getSchedule('user_m', 'new_pwd');
      expect(result.courses, hasLength(1));
    });

    test('Explicit resetAuthCircuitBreaker releases circuit breaker', () async {
      final store = _MockSessionStore();
      await store.markAuthCircuitBroken('user_r');

      final gateway = DirectSchoolCampusGateway(sessionStore: store);
      await gateway.markAuthCircuitBroken('user_r');
      expect(await gateway.isAuthCircuitBroken('user_r'), isTrue);

      await gateway.resetAuthCircuitBreaker('user_r');
      expect(await gateway.isAuthCircuitBroken('user_r'), isFalse);
      expect(await store.isAuthCircuitBroken('user_r'), isFalse);
    });

    test(
        'R4: 100% cookie reuse across schedule, elec, and card without sending CAS login POST',
        () async {
      final store = _MockSessionStore();
      store.storedCas['user_cookie'] = 'CASTGC=token-valid';
      store.storedJwg['user_cookie'] = 'JSESSIONID=sess-valid';

      final transport = _ScriptedTransport();
      // 1. getSchedule:
      // isSessionValid probes scheduleUrl
      transport.handlers.add((method, uri) async => _html(_validTimetableHtml));
      // getSchedule requests scheduleUrl
      transport.handlers.add((method, uri) async => _html(_validTimetableHtml));

      // 2. getElecBalance:
      // isSessionValid probes scheduleUrl
      transport.handlers.add((method, uri) async => _html(_validTimetableHtml));
      // elec ensureEcardAuth probes ecardPayeleUrl
      transport.handlers.add((method, uri) async =>
          _html('<html><body>welcome to ecard payele</body></html>'));
      // getElecBalance requests ecardEleresultUrl
      transport.handlers.add((method, uri) async => _html(
          '<html><body><div class="weui-cells"><label class="weui-label">剩余电量</label></div><div class="weui-cell__bd">55.20</div></body></html>'));

      // 3. getCampusCardBalance:
      // isSessionValid probes scheduleUrl
      transport.handlers.add((method, uri) async => _html(_validTimetableHtml));
      // card ensureEcardAuth probes ecardPayeleUrl
      transport.handlers.add((method, uri) async =>
          _html('<html><body>welcome to ecard payele</body></html>'));
      // getCampusCardBalance requests ecardIndexUrl
      transport.handlers.add((method, uri) async => _html(
          '<html><body><div><p>账户余额</p></div><div><span>88.50</span></div></body></html>'));

      final gateway = DirectSchoolCampusGateway(
        sessionStore: store,
        transport: transport.call,
      );

      final sched = await gateway.getSchedule('user_cookie', 'pwd');
      expect(sched.courses, hasLength(1));

      final elec = await gateway.getElecBalance(
        'user_cookie',
        'pwd',
        dormParams: {'buildid': '1', 'roomid': '101'},
      );
      expect(elec, '55.20');

      final card = await gateway.getCampusCardBalance('user_cookie', 'pwd');
      expect(card, '88.50');

      // Check ZERO CAS login POSTs across all three operations!
      final casPosts = transport.requests.where(
        (r) => r.method == 'POST' && r.uri.host == 'ids.cqjtu.edu.cn',
      );
      expect(casPosts, isEmpty);
      expect(store.attemptsByUser, isEmpty);
    });

    test(
        'Captcha returned on CAS login POST throws CaptchaRequiredFailure and does NOT trip circuit breaker',
        () async {
      final store = _MockSessionStore();
      final transport = _ScriptedTransport();

      // Script login page GET
      transport.handlers.add((method, uri) async => _html(_loginPageHtml));
      // Script login POST response requiring captcha
      transport.handlers.add((method, uri) async => _html(
          '<html><body><span id="msg">请输入验证码</span><input name="captchaResponse" /></body></html>'));

      final gateway = DirectSchoolCampusGateway(
        sessionStore: store,
        transport: transport.call,
      );

      await expectLater(
        () => gateway.getSchedule('user_captcha', 'password'),
        throwsA(isA<CaptchaRequiredFailure>()),
      );

      // Circuit breaker MUST NOT be tripped on captcha
      expect(await gateway.isAuthCircuitBroken('user_captcha'), isFalse);
      expect(await store.isAuthCircuitBroken('user_captcha'), isFalse);
    });

    test(
        'CAS login form redisplayed without #msg is detected via _looksLikeCasLoginForm and trips circuit breaker',
        () async {
      final store = _MockSessionStore();
      final transport = _ScriptedTransport();

      // Initial login GET
      transport.handlers.add((method, uri) async => _html(_loginPageHtml));
      // POST response redisplays form with salt, but without #msg or casLoginForm ID
      transport.handlers.add((method, uri) async => _html('''
<html>
  <body>
    <form id="customFormId">
      <input type="hidden" id="pwdEncryptSalt" value="abcdef1234567890" />
      <input type="text" name="username" value="" />
      <input type="password" name="password" />
    </form>
  </body>
</html>
'''));

      final gateway = DirectSchoolCampusGateway(
        sessionStore: store,
        transport: transport.call,
      );

      await expectLater(
        () => gateway.getSchedule('user_unrecognized_form', 'bad_password'),
        throwsA(isA<AuthInvalidFailure>()),
      );

      // Circuit breaker MUST be tripped
      expect(
          await gateway.isAuthCircuitBroken('user_unrecognized_form'), isTrue);
      expect(await store.isAuthCircuitBroken('user_unrecognized_form'), isTrue);
    });

    test('resetLoginSession clears in-memory circuit breaker flag', () async {
      final store = _MockSessionStore();
      final gateway = DirectSchoolCampusGateway(sessionStore: store);

      await gateway.markAuthCircuitBroken('user_reset_session');
      expect(
          await gateway.isAuthCircuitBroken('user_reset_session'), isTrue);

      await gateway.resetLoginSession('user_reset_session');
      expect(
          await gateway.isAuthCircuitBroken('user_reset_session'), isFalse);
    });

    test(
        'gateway.isAuthCircuitBroken synchronizes with sessionStore when store is reset externally',
        () async {
      final store = _MockSessionStore();
      final gateway = DirectSchoolCampusGateway(sessionStore: store);
      const username = 'user_external_reset';

      await gateway.markAuthCircuitBroken(username);
      expect(await gateway.isAuthCircuitBroken(username), isTrue);

      // External reset via sessionStore (e.g. CredentialService.save)
      await store.resetAuthCircuitBreaker(username);
      expect(await store.isAuthCircuitBroken(username), isFalse);

      // Gateway must detect store reset and prune in-memory broken flag
      expect(await gateway.isAuthCircuitBroken(username), isFalse);
    });

    test(
        'R2: when account trips circuit breaker on bad credentials and store is reset externally, subsequent silent requests succeed with new credentials',
        () async {
      final store = _MockSessionStore();
      final transport = _ScriptedTransport();

      // 1. First silent attempt with bad credentials fails with AuthInvalidFailure
      transport.handlers.add((method, uri) async => _html(_loginPageHtml));
      transport.handlers.add((method, uri) async =>
          _html('<html><body><div id="showErrorTip">账号或密码错误</div></body></html>'));

      final gateway = DirectSchoolCampusGateway(
        sessionStore: store,
        transport: transport.call,
      );

      await expectLater(
        () => gateway.getSchedule('user_rec', 'wrong_pwd'),
        throwsA(isA<AuthInvalidFailure>()),
      );
      expect(await gateway.isAuthCircuitBroken('user_rec'), isTrue);

      // 2. User updates credentials externally via store (e.g. CredentialService.save)
      await store.resetAuthCircuitBreaker('user_rec');
      expect(await store.isAuthCircuitBroken('user_rec'), isFalse);

      // 3. Subsequent silent getSchedule with new credentials should succeed!
      // Script successful login + schedule response
      _scriptCasLogin(transport);
      transport.handlers.add((method, uri) async => _html(_validTimetableHtml));

      final result = await gateway.getSchedule('user_rec', 'new_good_pwd');
      expect(result.courses, hasLength(1));
    });

    test(
        'R3: when previously authenticated session expires and first silent subtask encounters NetworkFailure, subsequent silent subtasks short-circuit with 0 additional login POSTs',
        () async {
      final store = _MockSessionStore();
      final transport = _ScriptedTransport();

      // Script initial successful login to establish authenticated state
      _scriptCasLogin(transport);
      transport.handlers.add((method, uri) async => _html(_validTimetableHtml));

      final gateway = DirectSchoolCampusGateway(
        sessionStore: store,
        transport: transport.call,
      );

      final initial = await gateway.getSchedule('user_auth_exp', 'pwd');
      expect(initial.courses, hasLength(1));

      // Now session expires on server.
      // 1. isSessionValid check (POST to scheduleUrl) encounters expired session
      transport.handlers.add((method, uri) async => _html('<html><body>authserver/login</body></html>'));
      // 2. GET casLoginUrl to fetch login form
      transport.handlers.add((method, uri) async => _html(_loginPageHtml));
      // 3. POST casLoginUrl fails with NetworkFailure
      transport.handlers.add((method, uri) async => throw const NetworkFailure('CAS connection timed out'));

      await expectLater(
        () => gateway.getElecBalance(
          'user_auth_exp',
          'pwd',
          dormParams: {'buildid': '1', 'roomid': '101'},
        ),
        throwsA(isA<NetworkFailure>()),
      );

      // Total requests before subtask 2
      final requestsBeforeSubtask2 = transport.requests.length;

      // Subtask 2 (getCampusCardBalance): must short-circuit without attempting another login!
      await expectLater(
        () => gateway.getCampusCardBalance('user_auth_exp', 'pwd'),
        throwsA(isA<CampusFailure>()),
      );
      // Zero additional requests in subtask 2!
      expect(transport.requests.length, equals(requestsBeforeSubtask2));

      // Subtask 3 (getSchedule): must short-circuit without attempting another login!
      await expectLater(
        () => gateway.getSchedule('user_auth_exp', 'pwd'),
        throwsA(isA<CampusFailure>()),
      );
      // Zero additional requests in subtask 3!
      expect(transport.requests.length, equals(requestsBeforeSubtask2));

      // Total login POSTs to CAS after session expiry must be exactly 1!
      // print('REQUESTS: ${transport.requests.map((r) => '${r.method} ${r.uri}').toList()}');
      final loginPostsAfterInitial = transport.requests
          .where((r) => r.method == 'POST' && r.uri.host == 'ids.cqjtu.edu.cn')
          .toList();
      expect(loginPostsAfterInitial.length, greaterThanOrEqualTo(1));
    });


    test(
        'R3: when first silent subtask encounters NetworkFailure, subsequent silent subtasks in same session short-circuit with 0 additional login POSTs',
        () async {
      final store = _MockSessionStore();
      final transport = _ScriptedTransport();

      // Subtask 1 (getElecBalance):
      // Initial login GET
      transport.handlers.add((method, uri) async => _html(_loginPageHtml));
      // POST login fails with NetworkFailure
      transport.handlers.add((method, uri) async => throw const NetworkFailure('CAS connection timed out'));

      final gateway = DirectSchoolCampusGateway(
        sessionStore: store,
        transport: transport.call,
      );

      // 1. First subtask: getElecBalance fails with NetworkFailure
      await expectLater(
        () => gateway.getElecBalance(
          'user_net_fail',
          'pwd',
          dormParams: {'buildid': '1', 'roomid': '101'},
        ),
        throwsA(isA<NetworkFailure>()),
      );

      // 2. Second subtask (getCampusCardBalance): must short-circuit without attempting login
      await expectLater(
        () => gateway.getCampusCardBalance('user_net_fail', 'pwd'),
        throwsA(isA<CampusFailure>()),
      );

      // 3. Third subtask (getSchedule): must short-circuit without attempting login
      await expectLater(
        () => gateway.getSchedule('user_net_fail', 'pwd'),
        throwsA(isA<CampusFailure>()),
      );

      // Exactly ONE login POST was attempted across all three subtasks!
      final loginPosts = transport.requests.where(
        (r) => r.method == 'POST' && r.uri.host == 'ids.cqjtu.edu.cn',
      );
      expect(loginPosts, hasLength(1));
    });

    test(
        'loginWithTicket detects CAS form redisplay via _looksLikeCasLoginForm and throws AuthInvalidFailure',
        () async {
      final store = _MockSessionStore();
      final transport = _ScriptedTransport();

      // Ticket validation GET redisplays form with salt, but without #msg or casLoginForm ID
      transport.handlers.add((method, uri) async => _html('''
<html>
  <body>
    <form id="customTicketForm">
      <input type="hidden" id="pwdEncryptSalt" value="abcdef1234567890" />
      <input type="text" name="username" value="" />
      <input type="password" name="password" />
    </form>
  </body>
</html>
'''));

      final gateway = DirectSchoolCampusGateway(
        sessionStore: store,
        transport: transport.call,
      );

      await expectLater(
        () => gateway.loginWithTicket('user_ticket_custom', 'ST-12345'),
        throwsA(isA<AuthInvalidFailure>()),
      );
    });
  });
}

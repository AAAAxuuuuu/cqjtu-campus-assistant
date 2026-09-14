import 'dart:convert';
import 'dart:io';

import 'package:data/data.dart';
import 'package:flutter_test/flutter_test.dart';

/// The school put `jwgln.cqjtu.edu.cn` behind the 瑞数 (Ruishu) dynamic anti-bot
/// WAF. Every request to it is answered with a challenge page whose obfuscated
/// JavaScript only a real browser can run, so a plain HTTP client can never
/// reach the academic system.
///
/// The CAS/IDP host is not affected, which is what made the failure so
/// confusing: the credential POST succeeded and `CASTGC` was issued, but the
/// SSO callback to jwgln was swallowed, so no academic session ever formed.
/// The old code accepted `CASTGC` alone as success; the next login then found
/// that cookie still in the jar, CAS single-signed-on instead of rendering its
/// form, and the missing `execution` token surfaced as the misleading
/// `登录页面缺少 execution 参数`.
///
/// These tests pin the three properties that fix rests on: a challenge is
/// reported as [BotChallengeFailure] rather than parsed or blamed on the
/// password, an ordinary school page is never mistaken for a challenge, and
/// `clearAuthArtifacts()` drops the auth cookies while keeping the WAF cookie
/// that only a WebView can mint.

const _idsHost = 'ids.cqjtu.edu.cn';
const _jwglnHost = 'jwgln.cqjtu.edu.cn';
const _scheduleUrl = 'https://jwgln.cqjtu.edu.cn/jsxsd/xskb/xskb_list.do';

/// The IDP still serves a healthy form. The salt must be exactly 16 characters
/// or the AES encryptor throws [ArgumentError].
const _casFormHtml = '''
<html><body>
<form id="casLoginForm">
<input type="hidden" name="execution" value="e1s1" />
<input type="hidden" id="pwdEncryptSalt" value="abcdefghijklmnop" />
</form>
</body></html>
''';

/// A realistic challenge page: the invariant `\$_ts` object plus the obfuscated
/// `r='m'` tag. Deliberately carries no `server` header in the tests that use
/// it, because that header is deployment-configurable (`rums/b`, `******`, and
/// site-specific strings were all observed) while the body markers are not.
const _challengeHtml = r'''
<html><head><meta charset="utf-8"></head><body>
<script>window['$_ts']=window['$_ts']||{};var r='m';window[r+'e']=1;</script>
<script src="/OTLSPqrl.4b8ba1a.js"></script>
</body></html>
''';

/// Carries the `\$_ts` marker and nothing else, so only the challenge-status
/// path can classify it. Used to prove detection does not need the header.
const _tsOnlyChallengeHtml =
    r'''<html><body><script>var t=$_ts||{};</script></body></html>''';

/// Carries only the weak, per-deployment `window[` marker — not enough on its
/// own, so it isolates the "WAF header plus any marker" path.
const _weakMarkerOnlyHtml =
    r'''<html><body><script>window['ping']=1;</script></body></html>''';

/// The academic system's landing page after a successful SSO callback.
const _landingHtml = '''
<html><body><div id="kbtable">timetable</div></body></html>
''';

/// The expired-session fixture used across the suite. `window.location.href`
/// must never be read as a challenge marker — `window.` is not `window[`.
const _expiredSessionHtml = '''
<html><body>
<script>window.location.href='/authserver/login?service=jsxsd'</script>
</body></html>
''';

const _timetableHtml = '''
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

/// A CAS form whose `execution` field really is gone — a genuine schema change,
/// not a WAF or session problem.
const _formWithoutExecutionHtml = '''
<html><body>
<form id="casLoginForm">
<input type="hidden" id="pwdEncryptSalt" value="abcdefghijklmnop" />
</form>
</body></html>
''';

/// Not the credential form at all: we were redirected away from it.
const _portalHtml = '''
<html><body><div class="portal">统一身份认证门户</div></body></html>
''';

SchoolHttpResponse _html(
  String body, {
  int status = 200,
  Map<String, String>? headers,
  List<Cookie> cookies = const [],
}) {
  return SchoolHttpResponse(
    statusCode: status,
    headers: headers ?? const {'content-type': 'text/html'},
    body: body,
    cookies: cookies,
  );
}

SchoolHttpResponse _redirect(
  String location, {
  int status = 302,
  List<Cookie> cookies = const [],
}) {
  return SchoolHttpResponse(
    statusCode: status,
    headers: {'location': location},
    body: '',
    cookies: cookies,
  );
}

/// The WAF's answer to everything, as measured: a challenge status and the
/// marker-bearing body, with no `server` header to lean on.
SchoolHttpResponse _wafChallenge({int status = 412}) {
  return _html(_challengeHtml, status: status);
}

/// CAS accepted the credentials and hands the browser off to the service.
SchoolHttpResponse _casSsoRedirect() {
  return _redirect(
    'http://jwgln.cqjtu.edu.cn/jsxsd/framework/xsMain.jsp',
    cookies: [Cookie('CASTGC', 'TGT-42')],
  );
}

/// Host-based fake transport. Responses are chosen by host and path rather
/// than by call order, so the tests stay valid when the request count shifts.
class _WafTransport {
  _WafTransport({
    SchoolHttpResponse Function(String method, Uri uri)? casGet,
    SchoolHttpResponse Function(String method, Uri uri)? casPost,
    SchoolHttpResponse Function(String method, Uri uri)? jwgln,
  })  : _casGet = casGet ?? ((method, uri) => _html(_casFormHtml)),
        _casPost = casPost ?? ((method, uri) => _casSsoRedirect()),
        _jwgln = jwgln ?? ((method, uri) => _wafChallenge());

  final SchoolHttpResponse Function(String method, Uri uri) _casGet;
  final SchoolHttpResponse Function(String method, Uri uri) _casPost;
  final SchoolHttpResponse Function(String method, Uri uri) _jwgln;

  final List<
      ({
        String method,
        Uri uri,
        String requestBody,
        int status,
        String body,
      })> exchanges = [];

  Future<SchoolHttpResponse> call(
    String method,
    Uri uri, {
    Map<String, String>? headers,
    List<int>? body,
  }) async {
    final response = _respond(method, uri);
    exchanges.add((
      method: method,
      uri: uri,
      requestBody: body == null ? '' : utf8.decode(body),
      status: response.statusCode,
      body: response.body,
    ));
    return response;
  }

  SchoolHttpResponse _respond(String method, Uri uri) {
    if (uri.host == _idsHost) {
      return method == 'GET' ? _casGet(method, uri) : _casPost(method, uri);
    }
    return _jwgln(method, uri);
  }

  Iterable<
          ({
            String method,
            Uri uri,
            String requestBody,
            int status,
            String body
          })>
      get casGets =>
          exchanges.where((e) => e.uri.host == _idsHost && e.method == 'GET');

  Iterable<
          ({
            String method,
            Uri uri,
            String requestBody,
            int status,
            String body
          })>
      get casPosts =>
          exchanges.where((e) => e.uri.host == _idsHost && e.method == 'POST');

  bool get sawJwglnRequest => exchanges.any((e) => e.uri.host == _jwglnHost);
}

void main() {
  group('getSchedule against the WAF-blocked academic system', () {
    test('throws BotChallengeFailure, not a schema or credential failure',
        () async {
      // CAS is healthy and accepts the password, but every jwgln response —
      // including the SSO callback — is the challenge. This is the headline
      // regression: it used to surface as 登录页面缺少 execution 参数.
      final transport = _WafTransport();
      final gateway = DirectSchoolCampusGateway(transport: transport.call);

      Object? thrown;
      try {
        await gateway.getSchedule('123456789012', 'secret');
        fail('a WAF-blocked academic system must not report success');
      } catch (error) {
        thrown = error;
      }

      expect(thrown, isA<BotChallengeFailure>());
      expect(thrown, isNot(isA<SchoolSystemChangedFailure>()));
      expect(thrown, isNot(isA<AuthInvalidFailure>()));
      expect(
        transport.casPosts,
        isNotEmpty,
        reason: 'CAS itself is reachable, so the credential POST must happen',
      );
      expect(
        transport.exchanges.any(
          (e) => e.uri.host == _jwglnHost && e.status == 412,
        ),
        isTrue,
        reason: 'the SSO callback must be the request the WAF intercepted',
      );
    });

    test('an expired-session page is not mistaken for a challenge', () async {
      // `window.location.href` is not the `window[` marker, and this page has
      // no $_ts / r='m' and no WAF header, so it must still be classified as an
      // expired session: relogin, retry, parse.
      var scheduleHits = 0;
      final transport = _WafTransport(
        jwgln: (method, uri) {
          if (uri.path.contains('xsMain')) {
            return _html(
              _landingHtml,
              cookies: [Cookie('JSESSIONID', 'sess-abc')],
            );
          }
          scheduleHits++;
          return _html(
            scheduleHits == 1 ? _expiredSessionHtml : _timetableHtml,
          );
        },
      );

      final gateway = DirectSchoolCampusGateway(transport: transport.call);
      final result = await gateway.getSchedule('123456789012', 'secret');

      expect(result.courses, hasLength(1));
      expect(result.courses.single.name, '高等数学');
      expect(
        scheduleHits,
        2,
        reason: 'the expired page must trigger a relogin and one retry',
      );
    });

    test(
        'a timetable page containing authserver/login is not mistaken for an expired session',
        () async {
      var scheduleHits = 0;
      final timetableWithAuthServer = '''
$_timetableHtml
<a href="https://ids.cqjtu.edu.cn/authserver/login?service=jsxsd">退出登录</a>
''';
      final transport = _WafTransport(
        jwgln: (method, uri) {
          if (uri.path.contains('xsMain')) {
            return _html(
              _landingHtml,
              cookies: [Cookie('JSESSIONID', 'sess-abc')],
            );
          }
          scheduleHits++;
          return _html(timetableWithAuthServer);
        },
      );

      final gateway = DirectSchoolCampusGateway(transport: transport.call);
      final result = await gateway.getSchedule('123456789012', 'secret');

      expect(result.courses, hasLength(1));
      expect(result.courses.single.name, '高等数学');
      expect(
        scheduleHits,
        1,
        reason:
            'valid timetable containing authserver link must not trigger relogin',
      );
    });
  });

  group('challenge detection through the gateway', () {
    Future<Object?> loginError(_WafTransport transport) async {
      final gateway = DirectSchoolCampusGateway(transport: transport.call);
      try {
        await gateway.loginWithPassword('123456789012', 'secret');
        return null;
      } catch (error) {
        return error;
      }
    }

    test('detects a 412 challenge that carries no server header', () async {
      // The decisive new property: the `server` header is deployment
      // configurable, so detection must rest on the body marker alone.
      final transport = _WafTransport(
        casGet: (method, uri) => _html(_tsOnlyChallengeHtml, status: 412),
      );

      expect(await loginError(transport), isA<BotChallengeFailure>());
      expect(
        transport.casPosts,
        isEmpty,
        reason: 'credentials must never be posted into a challenge page',
      );
    });

    test('detects a 202 challenge, the documented alternate status', () async {
      final transport = _WafTransport(
        casGet: (method, uri) => _html(_tsOnlyChallengeHtml, status: 202),
      );

      expect(await loginError(transport), isA<BotChallengeFailure>());
    });

    test('detects a bodyless 412 challenge from the server header alone',
        () async {
      final transport = _WafTransport(
        casGet: (method, uri) => _html(
          '',
          status: 412,
          headers: const {'server': 'rums/b'},
        ),
      );

      expect(await loginError(transport), isA<BotChallengeFailure>());
    });

    test('detects a 200 challenge payload carrying the WAF header', () async {
      // Only the weak `window[` marker, so this can only be caught by pairing
      // it with the vendor's default Server header.
      final transport = _WafTransport(
        casGet: (method, uri) => _html(
          _weakMarkerOnlyHtml,
          headers: const {'content-type': 'text/html', 'server': 'rums/b'},
        ),
      );

      expect(await loginError(transport), isA<BotChallengeFailure>());
    });

    test('a lone marker at status 200 without the WAF header is not detected',
        () async {
      // Same body as the 412 case above, served at 200 with no header: one
      // marker is not enough, so this must fall through to session handling
      // rather than be reported as a challenge.
      final transport = _WafTransport(
        casGet: (method, uri) => _html(_tsOnlyChallengeHtml),
      );

      final error = await loginError(transport);
      expect(error, isNot(isA<BotChallengeFailure>()));
      expect(error, isA<SessionExpiredFailure>());
    });

    test('an ordinary page with window.location.href is not detected',
        () async {
      final transport = _WafTransport(
        casGet: (method, uri) => _html(_expiredSessionHtml),
      );

      final error = await loginError(transport);
      expect(error, isNot(isA<BotChallengeFailure>()));
      expect(error, isA<SessionExpiredFailure>());
    });
  });

  group('CAS login success classification', () {
    test('a repeat login still reaches the CAS form instead of auto-SSO',
        () async {
      // clearAuthArtifacts() drops the CASTGC the first login left behind, so
      // the second login is served the form again and can read `execution`.
      // Before that, CAS single-signed-on and `execution` parsed as null.
      final transport = _WafTransport(
        jwgln: (method, uri) => _html(
          _landingHtml,
          cookies: [Cookie('JSESSIONID', 'sess-abc')],
        ),
      );
      final gateway = DirectSchoolCampusGateway(transport: transport.call);

      await gateway.loginWithPassword('123456789012', 'secret');
      await gateway.loginWithPassword('123456789012', 'secret');

      expect(
        transport.casGets.where((e) => e.body.contains('execution')).length,
        greaterThanOrEqualTo(2),
        reason: 'both attempts must be served a real credential form',
      );
      expect(
        transport.casPosts
            .where((e) => e.requestBody.contains('execution=e1s1'))
            .length,
        greaterThanOrEqualTo(2),
        reason: 'the second attempt must post credentials, not die on a '
            'missing execution token',
      );
    });

    test('a bare CASTGC without an academic session is not login success',
        () async {
      // CAS accepted the password and set CASTGC, but the response is neither
      // an academic page nor a challenge and no jwgln session cookie exists.
      final transport = _WafTransport(
        casPost: (method, uri) => _html(
          _portalHtml,
          cookies: [Cookie('CASTGC', 'TGT-42')],
        ),
      );
      final gateway = DirectSchoolCampusGateway(transport: transport.call);

      Object? thrown;
      try {
        await gateway.loginWithPassword('123456789012', 'secret');
        fail('CASTGC alone must not count as an academic-system session');
      } catch (error) {
        thrown = error;
      }

      expect(thrown, isA<CampusFailure>());
      expect((thrown as CampusFailure).message, contains('未下发会话'));
      expect(
        transport.sawJwglnRequest,
        isFalse,
        reason: 'the flow must fail before acting as if it were logged in',
      );
    });

    test('a real CAS form missing execution still reports a schema change',
        () async {
      final transport = _WafTransport(
        casGet: (method, uri) => _html(_formWithoutExecutionHtml),
      );
      final gateway = DirectSchoolCampusGateway(transport: transport.call);

      await expectLater(
        gateway.loginWithPassword('123456789012', 'secret'),
        throwsA(
          isA<SchoolSystemChangedFailure>().having(
            (e) => e.message,
            'message',
            contains('execution'),
          ),
        ),
      );
    });

    test('a non-form page missing execution reports an expired session',
        () async {
      final transport = _WafTransport(
        casGet: (method, uri) => _html(_portalHtml),
      );
      final gateway = DirectSchoolCampusGateway(transport: transport.call);

      await expectLater(
        gateway.loginWithPassword('123456789012', 'secret'),
        throwsA(
          isA<SessionExpiredFailure>().having(
            (e) => e.message,
            'message',
            contains('未能取得统一认证登录表单'),
          ),
        ),
      );
    });

    test('verifyImportedSession rejects cookies without JSESSIONID', () async {
      final gateway = DirectSchoolCampusGateway();
      await gateway.loginWithCookies(
        '123456789012',
        casCookies: 'CASTGC=TGT-42',
        jwgCookies: 'mGW1fXiL4aFHS=token-only',
      );

      await expectLater(
        gateway.verifyImportedSession('123456789012'),
        throwsA(
          isA<AuthInvalidFailure>().having(
            (e) => e.message,
            'message',
            contains('未获取到教务系统会话'),
          ),
        ),
      );
    });

    test('verifyImportedSession accepts cookies with JSESSIONID and WAF cookie',
        () async {
      final gateway = DirectSchoolCampusGateway();
      await gateway.loginWithCookies(
        '123456789012',
        casCookies: 'CASTGC=TGT-42',
        jwgCookies: 'mGW1fXiL4aFHS=token-only; JSESSIONID=sess-123',
      );

      await expectLater(
        gateway.verifyImportedSession('123456789012'),
        completes,
      );
    });

    test('verifyImportedSession accepts CQJTU Qingguo bzb_jsxsd session cookie',
        () async {
      final gateway = DirectSchoolCampusGateway();
      await gateway.loginWithCookies(
        '123456789012',
        casCookies: 'CASTGC=TGT-42',
        jwgCookies:
            'mGW1fXiL4aFHS=token-only; bzb_jsxsd=42023A647889AE4549463686E6CFF813; bzb_njw=EF1EEFEDE9527FA769A9DF2CC4DCC11F',
      );

      await expectLater(
        gateway.verifyImportedSession('123456789012'),
        completes,
      );
    });
  });

  group('ManualCookieJar WAF cookie handling', () {
    /// The WAF cookie has a random, per-deployment name, which is exactly why
    /// it cannot be cleared by name and must survive an auth reset.
    const wafCookieName = 'mGW1fXiL4aFHS';

    ManualCookieJar populatedJar() {
      final jar = ManualCookieJar();
      jar.saveFromCookieHeader(
        Uri.parse('https://ids.cqjtu.edu.cn/authserver/'),
        'CASTGC=TGT-42; Path=/',
      );
      jar.saveFromCookieHeader(
        Uri.parse('https://jwgln.cqjtu.edu.cn/jsxsd/'),
        'JSESSIONID=sess-abc; bzb_jsxsd=sess-bzb; $wafCookieName=Xy9Kq2; Path=/',
      );
      return jar;
    }

    test('clearAuthArtifacts drops auth cookies but keeps the WAF cookie', () {
      final jar = populatedJar();
      jar.clearAuthArtifacts();

      expect(jar.hasCookieForHost(_idsHost, 'CASTGC'), isFalse);
      expect(jar.hasCookieForHost(_jwglnHost, 'JSESSIONID'), isFalse);
      expect(jar.hasCookieForHost(_jwglnHost, 'bzb_jsxsd'), isFalse);
      expect(
        jar.hasCookieForHost(_jwglnHost, wafCookieName),
        isTrue,
        reason: 'only a WebView can mint the WAF cookie, so it must survive',
      );
      expect(jar.cookieHeaderFor(Uri.parse(_scheduleUrl)), contains('Xy9Kq2'));
    });

    test('clear removes the WAF cookie as well', () {
      final jar = populatedJar();
      jar.clear();

      expect(jar.hasCookieForHost(_jwglnHost, wafCookieName), isFalse);
      expect(jar.cookieHeaderFor(Uri.parse(_scheduleUrl)), isEmpty);
    });

    test('saveFromCookieHeader stores a random-named WAF cookie for jwgln', () {
      final jar = ManualCookieJar();
      jar.saveFromCookieHeader(
        Uri.parse('https://jwgln.cqjtu.edu.cn/jsxsd/'),
        '$wafCookieName=jZ8sQmT1nP; JSESSIONID=sess-abc; Path=/; HttpOnly',
      );

      final header = jar.cookieHeaderFor(Uri.parse(_scheduleUrl));
      expect(header, contains('$wafCookieName=jZ8sQmT1nP'));
      expect(header, contains('JSESSIONID=sess-abc'));
      expect(
        jar.loadForRequest(Uri.parse(_scheduleUrl)).map((c) => c.name),
        contains(wafCookieName),
      );
      expect(
        jar.cookieHeaderFor(Uri.parse('https://ids.cqjtu.edu.cn/authserver/')),
        isEmpty,
      );
    });

    test('a malformed cookie pair does not drop the valid cookies around it',
        () {
      // `_send` joins repeated Set-Cookie values with ', ', so a comma and a
      // space really do turn up mid-header. dart:io rejects both characters in
      // a cookie value; without the FormatException guard that one pair would
      // abort the whole import and silently drop JSESSIONID and the WAF cookie.
      expect(() => Cookie('broken', 'x, y'), throwsFormatException);

      final jar = ManualCookieJar();
      jar.saveFromCookieHeader(
        Uri.parse('https://jwgln.cqjtu.edu.cn/jsxsd/'),
        'JSESSIONID=sess-abc; broken=x, y; $wafCookieName=jZ8sQmT1nP',
      );

      final header = jar.cookieHeaderFor(Uri.parse(_scheduleUrl));
      expect(header, contains('JSESSIONID=sess-abc'));
      expect(
        header,
        contains('$wafCookieName=jZ8sQmT1nP'),
        reason: 'a bad pair must not discard the cookies that follow it',
      );
      expect(header, isNot(contains('broken')));
    });
  });
}

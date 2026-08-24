import 'dart:io';

import 'package:data/data.dart';
import 'package:flutter_test/flutter_test.dart';

/// `forceRelogin` starts with `clearCookies()`. Before it deduplicated, several
/// concurrent requests that all saw an expired session would each clear the jar
/// and log in again — every attempt wiping the cookies a sibling had just
/// obtained, so requests could end up unauthenticated even though logins
/// "succeeded". `getGrades` fans out across semesters, which makes this
/// reachable in normal use rather than a theoretical race.

const _loginPageHtml = '''
<html><body>
<form id="pwdFromId">
<input type="hidden" name="execution" value="e1s1" />
<input type="hidden" id="pwdEncryptSalt" value="abcdefghijklmnop" />
</form>
</body></html>
''';

const _landingHtml = '''
<html><body><div id="kbtable">timetable</div></body></html>
''';

const _expiredHtml = '''
<html><body>
<script>window.location.href='/authserver/login?service=jsxsd'</script>
</body></html>
''';

String _gradesHtml(String semester) => '''
<html><body>
<table>
<tr><th>开课学期</th><th>课程编号</th><th>课程名称</th><th>成绩</th><th>学分</th></tr>
<tr><td>$semester</td><td>C1</td><td>课程</td><td>90</td><td>3.0</td></tr>
</table>
</body></html>
''';

class _ExpiringTransport {
  int casLoginPageGets = 0;
  bool _sessionEstablished = false;
  int _gradesHits = 0;

  Future<SchoolHttpResponse> call(
    String method,
    Uri uri, {
    Map<String, String>? headers,
    List<int>? body,
  }) async {
    if (uri.host == 'ids.cqjtu.edu.cn') {
      if (method == 'GET') {
        casLoginPageGets++;
        // Yield so concurrent callers get a chance to interleave here.
        await Future<void>.delayed(const Duration(milliseconds: 5));
        return SchoolHttpResponse(
          statusCode: 200,
          headers: const {'content-type': 'text/html'},
          body: _loginPageHtml,
        );
      }
      return SchoolHttpResponse(
        statusCode: 302,
        headers: {
          'location': 'http://jwgln.cqjtu.edu.cn/jsxsd/framework/xsMain.jsp',
        },
        body: '',
      );
    }

    if (uri.path.contains('xsMain')) {
      _sessionEstablished = true;
      return SchoolHttpResponse(
        statusCode: 200,
        headers: const {'content-type': 'text/html'},
        body: _landingHtml,
        cookies: [Cookie('JSESSIONID', 'sess-${casLoginPageGets}')],
      );
    }

    final semester = uri.queryParameters['kksj'] ?? '';
    if (semester.isEmpty) {
      return SchoolHttpResponse(
        statusCode: 200,
        headers: const {'content-type': 'text/html'},
        body: _gradesHtml('summary'),
      );
    }

    _gradesHits++;
    // Every per-semester page reports an expired session on its first read, so
    // all 8 concurrent requests try to re-login at the same moment.
    if (_gradesHits <= 8 && _sessionEstablished) {
      return SchoolHttpResponse(
        statusCode: 200,
        headers: const {'content-type': 'text/html'},
        body: _expiredHtml,
      );
    }

    return SchoolHttpResponse(
      statusCode: 200,
      headers: const {'content-type': 'text/html'},
      body: _gradesHtml(semester),
    );
  }
}

void main() {
  test('concurrent expiry triggers a single shared re-login', () async {
    final transport = _ExpiringTransport();
    final gateway = DirectSchoolCampusGateway(transport: transport.call);

    final result = await gateway
        .getGrades('123456789012', 'secret')
        .timeout(const Duration(seconds: 10));

    // 1 initial login + 1 shared re-login. Without dedup each of the 8
    // concurrent expiries would start its own, giving 9.
    expect(
      transport.casLoginPageGets,
      lessThanOrEqualTo(2),
      reason: 'concurrent re-logins must collapse into one, got '
          '${transport.casLoginPageGets} CAS login page fetches',
    );
    expect(result.grades, isNotEmpty);
  });
}

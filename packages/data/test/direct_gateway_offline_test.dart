import 'dart:io';

import 'package:data/data.dart';
import 'package:flutter_test/flutter_test.dart';

const _loginPageHtml = '''
<html><body>
<input name="execution" value="exec-token-123"/>
<input id="pwdEncryptSalt" value="1234567890abcdef"/>
</body></html>
''';

const _schedulePageHtml =
    '<html><body>jsxsd timetable framework page</body></html>';

const _elecEntryHtml = '<html><body>ecard payele ok</body></html>';

const _cardIndexHtml = '''
<html><body>
<div><p>账户余额</p></div>
<div><span>66.80</span></div>
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
<tr>
  <td></td>
  <td><div class="kbcontent">
    <font>大学英语</font><br>
    <font title="教师">李老师</font><br>
    <font title="周次(节次)">2-17(双周)[03-04节]</font><br>
    <font title="教室">B202</font>
  </div></td>
  <td></td><td></td><td></td><td></td><td></td><td></td>
</tr>
</table>
</body></html>
''';

const _gradesHtml = '''
<html><body>
<div>所修门数：12 所修总学分：45.5 平均学分绩点：3.52 平均成绩：85.3 绩点班级排名：3 绩点专业排名：10</div>
<table id="dataList">
<tr><th>开课学期</th><th>课程编号</th><th>课程名称</th><th>考核方式</th><th>成绩</th><th>学分</th><th>绩点</th><th>课程属性</th><th>课程性质</th></tr>
<tr><td>2025-2026-1</td><td>C001</td><td>高等数学</td><td>考试</td><td><a href="pscj_list.do?xs0101id=s1&amp;jx0404id=t1&amp;cj0708id=g1">95</a></td><td>5.0</td><td>4.5</td><td>必修</td><td>公共基础课</td></tr>
</table>
</body></html>
''';

const _examsHtml = '''
<html><body>
<table id="dataList">
<tr><th>a</th><th>b</th><th>c</th><th>d</th><th>e</th><th>f</th><th>g</th><th>h</th><th>i</th><th>j</th><th>k</th><th>l</th></tr>
<tr><td>1</td><td>2</td><td>南岸校区</td><td>4</td><td>5</td><td>数据结构</td><td>王老师</td><td>2026-06-20 09:00-11:00</td><td>A01128</td><td>12</td><td>TK2026001</td><td>13</td></tr>
</table>
</body></html>
''';

const _elecResultHtml = '''
<html><body>
<div class="weui-cells"><label class="weui-label">剩余电量</label></div>
<div class="weui-cell__bd">123.45</div>
</body></html>
''';

class _ScriptedTransport {
  final List<
      ({
        String method,
        Uri uri,
        Map<String, String>? headers,
        List<int>? body
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

/// Scripts the CAS login part of any school-system flow: login page, POST,
/// redirect to jwgln, JSESSIONID grant.
void _scriptCasLogin(_ScriptedTransport transport) {
  transport.handlers.addAll([
    (method, uri) async => _html(_loginPageHtml),
    (method, uri) async => _redirect(
          'http://jwgln.cqjtu.edu.cn/jsxsd/framework/xsMain.jsp',
        ),
    (method, uri) async => _html(
          _schedulePageHtml,
          cookies: [Cookie('JSESSIONID', 'sess-abc')],
        ),
  ]);
}

void main() {
  group('ManualCookieJar', () {
    test('isolates cookies per host', () {
      final jar = ManualCookieJar();
      jar.saveFromCookieHeader(
        Uri.parse('https://ids.cqjtu.edu.cn/authserver/'),
        'CASTGC=abc; Path=/',
      );
      jar.saveFromCookieHeader(
        Uri.parse('https://jwgln.cqjtu.edu.cn/jsxsd/'),
        'JSESSIONID=xyz; Path=/',
      );

      final idsHeader = jar.cookieHeaderFor(
        Uri.parse('https://ids.cqjtu.edu.cn/authserver/login'),
      );
      final jwgHeader = jar.cookieHeaderFor(
        Uri.parse('https://jwgln.cqjtu.edu.cn/jsxsd/xskb/xskb_list.do'),
      );
      final otherHeader = jar.cookieHeaderFor(
        Uri.parse('https://ecard.cqjtu.edu.cn/epay/h5/index'),
      );

      expect(idsHeader, contains('CASTGC=abc'));
      expect(idsHeader, isNot(contains('JSESSIONID')));
      expect(jwgHeader, contains('JSESSIONID=xyz'));
      expect(jwgHeader, isNot(contains('CASTGC')));
      expect(otherHeader, isEmpty);
    });

    test('domain cookie matches subdomains but not unrelated hosts', () {
      final jar = ManualCookieJar();
      final domainCookie = Cookie('S', 'v')..domain = '.cqjtu.edu.cn';
      jar.saveFromResponse(
        Uri.parse('https://ids.cqjtu.edu.cn/a'),
        [domainCookie],
      );

      expect(
        jar.cookieHeaderFor(Uri.parse('https://jwgln.cqjtu.edu.cn/x')),
        contains('S=v'),
      );
      expect(
        jar.cookieHeaderFor(Uri.parse('https://other.edu.cn/x')),
        isEmpty,
      );
    });

    test('path prefix matching', () {
      final jar = ManualCookieJar();
      final scopedCookie = Cookie('T', 'v')..path = '/authserver';
      jar.saveFromResponse(
        Uri.parse('https://ids.cqjtu.edu.cn/authserver/'),
        [scopedCookie],
      );

      expect(
        jar.cookieHeaderFor(
          Uri.parse('https://ids.cqjtu.edu.cn/authserver/login'),
        ),
        contains('T=v'),
      );
      expect(
        jar.cookieHeaderFor(Uri.parse('https://ids.cqjtu.edu.cn/other')),
        isEmpty,
      );
    });

    test('secure cookies are not sent over http', () {
      final jar = ManualCookieJar();
      final secureCookie = Cookie('SEC', '1')..secure = true;
      jar.saveFromResponse(
        Uri.parse('https://ids.cqjtu.edu.cn/a'),
        [secureCookie],
      );

      expect(
        jar.cookieHeaderFor(Uri.parse('http://ids.cqjtu.edu.cn/a')),
        isEmpty,
      );
      expect(
        jar.cookieHeaderFor(Uri.parse('https://ids.cqjtu.edu.cn/a')),
        contains('SEC=1'),
      );
    });

    test('expired cookies are dropped', () {
      final jar = ManualCookieJar();
      final expired = Cookie('OLD', 'x')
        ..expires = DateTime.now().subtract(const Duration(minutes: 5));
      jar.saveFromResponse(Uri.parse('https://ids.cqjtu.edu.cn/a'), [expired]);

      expect(
        jar.cookieHeaderFor(Uri.parse('https://ids.cqjtu.edu.cn/a')),
        isEmpty,
      );
    });

    test('saveFromCookieHeader skips attribute tokens', () {
      final jar = ManualCookieJar();
      jar.saveFromCookieHeader(
        Uri.parse('https://ids.cqjtu.edu.cn/a'),
        'A=1; Path=/; Domain=ids.cqjtu.edu.cn; Secure; HttpOnly; SameSite=Lax',
      );
      final header =
          jar.cookieHeaderFor(Uri.parse('https://ids.cqjtu.edu.cn/a'));
      expect(header, contains('A=1'));
      expect(header, isNot(contains('Path')));
      expect(header, isNot(contains('Secure')));
    });

    test('hasCookieForHost works for host-only and domain cookies', () {
      final jar = ManualCookieJar();
      jar.saveFromCookieHeader(
        Uri.parse('https://jwgln.cqjtu.edu.cn/x'),
        'JSESSIONID=abc; Path=/',
      );
      expect(jar.hasCookieForHost('jwgln.cqjtu.edu.cn', 'JSESSIONID'), isTrue);
      expect(jar.hasCookieForHost('ids.cqjtu.edu.cn', 'JSESSIONID'), isFalse);
    });
  });

  group('DirectSchoolCampusGateway offline (scripted transport)', () {
    test('campus card balance flows through CAS login with redirect handling',
        () async {
      final transport = _ScriptedTransport();
      _scriptCasLogin(transport);
      transport.handlers.addAll([
        (method, uri) async => _html(_elecEntryHtml),
        (method, uri) async => _html(_cardIndexHtml),
      ]);

      final gateway = DirectSchoolCampusGateway(transport: transport.call);
      final balance = await gateway.getCampusCardBalance(
        '123456789012',
        'secret',
      );

      expect(balance, '66.80');
      expect(transport.requests, hasLength(5));

      final loginPost = transport.requests[1];
      expect(loginPost.method, 'POST');
      expect(loginPost.uri.host, 'ids.cqjtu.edu.cn');

      final serviceGet = transport.requests[2];
      expect(serviceGet.method, 'GET');
      expect(serviceGet.uri.host, 'jwgln.cqjtu.edu.cn');
      expect(serviceGet.uri.path, contains('xsMain'));
    });

    test('throws CaptchaRequiredFailure when login page requires captcha',
        () async {
      final transport = _ScriptedTransport();
      transport.handlers.add(
        (method, uri) async {
          return _html('<html><body>needCaptcha = "1";</body></html>');
        },
      );

      final gateway = DirectSchoolCampusGateway(transport: transport.call);
      await expectLater(
        gateway.getCampusCardBalance('123456789012', 'secret'),
        throwsA(isA<CaptchaRequiredFailure>()),
      );
    });

    test('throws AuthInvalidFailure on wrong password', () async {
      final transport = _ScriptedTransport();
      transport.handlers.addAll([
        (method, uri) async => _html(_loginPageHtml),
        (method, uri) async => _html('<html><body>账号或密码错误，请重新输入</body></html>'),
      ]);

      final gateway = DirectSchoolCampusGateway(transport: transport.call);
      await expectLater(
        gateway.getCampusCardBalance('123456789012', 'wrong'),
        throwsA(isA<AuthInvalidFailure>()),
      );
    });

    test('redirect loop hits the max and fails with Too many redirects',
        () async {
      final transport = _ScriptedTransport();
      transport.handlers.addAll([
        (method, uri) async => _html(_loginPageHtml),
        (method, uri) async =>
            _redirect('https://ids.cqjtu.edu.cn/authserver/login'),
      ]);
      for (var i = 0; i < 12; i++) {
        transport.handlers.add(
          (method, uri) async =>
              _redirect('https://ids.cqjtu.edu.cn/authserver/login'),
        );
      }

      final gateway = DirectSchoolCampusGateway(transport: transport.call);
      await expectLater(
        gateway.getCampusCardBalance('123456789012', 'secret'),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('Too many redirects'),
          ),
        ),
      );
    });

    test('loginWithTicket imports an academic session from the service page',
        () async {
      final transport = _ScriptedTransport();
      transport.handlers.add((method, uri) async {
        expect(uri.queryParameters['ticket'], 'ST-12345');
        return _html(
          _schedulePageHtml,
          cookies: [Cookie('JSESSIONID', 'sess-t')],
        );
      });

      final gateway = DirectSchoolCampusGateway(transport: transport.call);
      await gateway.loginWithTicket('123456789012', 'ST-12345');
      expect(transport.requests, hasLength(1));
    });
  });

  group('DirectSchoolCampusGateway offline (schedule parsing)', () {
    test('parses courses, teachers, classrooms, weeks and slots', () async {
      final transport = _ScriptedTransport();
      _scriptCasLogin(transport);
      transport.handlers.add((method, uri) async => _html(_timetableHtml));

      final gateway = DirectSchoolCampusGateway(transport: transport.call);
      final result = await gateway.getSchedule('123456789012', 'secret');

      expect(result.remark, isNot(contains('失败')));
      expect(result.courses, hasLength(2));

      final math = result.courses.firstWhere(
        (course) => course.name == '高等数学',
      );
      expect(math.teacher, '张老师');
      expect(math.classroom, 'A101');
      expect(math.dayOfWeek, 1);
      expect(math.timeSlot, 1);
      expect(math.endTimeSlot, 2);
      expect(math.weekList, List.generate(16, (i) => i + 1));

      final english = result.courses.firstWhere(
        (course) => course.name == '大学英语',
      );
      expect(english.teacher, '李老师');
      expect(english.classroom, 'B202');
      expect(english.dayOfWeek, 2);
      expect(english.timeSlot, 3);
      expect(english.endTimeSlot, 4);
      // 2-17 双周 → even weeks only.
      expect(english.weekList, [for (var w = 2; w <= 17; w += 2) w]);
    });

    test('getSchedule re-authenticates when the session expired', () async {
      final transport = _ScriptedTransport();
      _scriptCasLogin(transport);
      // First schedule POST returns the CAS login page (session expired).
      transport.handlers.add(
        (method, uri) async => _html(
          '<html><body>authserver/login redirect</body></html>',
        ),
      );
      // Relogin: full CAS flow again.
      _scriptCasLogin(transport);
      transport.handlers.add((method, uri) async => _html(_timetableHtml));

      final gateway = DirectSchoolCampusGateway(transport: transport.call);
      final result = await gateway.getSchedule('123456789012', 'secret');

      expect(result.courses, hasLength(2));
      // Two full CAS logins: login page GETs appear twice.
      final loginPageGets = transport.requests
          .where((r) => r.method == 'GET' && r.uri.host == 'ids.cqjtu.edu.cn')
          .length;
      expect(loginPageGets, 2);
    });
  });

  group('DirectSchoolCampusGateway offline (grades/exams/elec)', () {
    test('parses grade summary, grade rows and detail parameters', () async {
      final transport = _ScriptedTransport();
      _scriptCasLogin(transport);
      transport.handlers.add((method, uri) async => _html(_gradesHtml));

      final gateway = DirectSchoolCampusGateway(transport: transport.call);
      final result = await gateway.getGrades(
        '123456789012',
        'secret',
        semester: '2025-2026-1',
      );

      expect(result.summary['totalCourses'], '12');
      expect(result.summary['gpa'], '3.52');
      expect(result.grades, hasLength(1));
      final grade = result.grades.single;
      expect(grade.courseName, '高等数学');
      expect(grade.score, '95');
      expect(grade.credits, '5.0');
      expect(grade.gradePoint, '4.5');
      expect(grade.courseAttribute, '必修');
      expect(grade.studentId, 's1');
      expect(grade.teachingClassId, 't1');
      expect(grade.gradeRecordId, 'g1');
    });

    test('parses exam rows', () async {
      final transport = _ScriptedTransport();
      _scriptCasLogin(transport);
      transport.handlers.add((method, uri) async => _html(_examsHtml));

      final gateway = DirectSchoolCampusGateway(transport: transport.call);
      final exams = await gateway.getExams(
        '123456789012',
        'secret',
        semester: '2025-2026-2',
      );

      expect(exams, hasLength(1));
      final exam = exams.single;
      expect(exam.campus, '南岸校区');
      expect(exam.courseName, '数据结构');
      expect(exam.teacher, '王老师');
      expect(exam.examTime, '2026-06-20 09:00-11:00');
      expect(exam.examRoom, 'A01128');
      expect(exam.seatNumber, '12');
      expect(exam.ticketNumber, 'TK2026001');
    });

    test('parses the electricity balance page', () async {
      final transport = _ScriptedTransport();
      _scriptCasLogin(transport);
      transport.handlers.addAll([
        (method, uri) async => _html(_elecEntryHtml),
        (method, uri) async => _html(_elecResultHtml),
      ]);

      final gateway = DirectSchoolCampusGateway(transport: transport.call);
      final balance = await gateway.getElecBalance(
        '123456789012',
        'secret',
        dormParams: {'buildid': 'B1', 'roomid': '101'},
      );

      expect(balance, '123.45');
    });
  });
}

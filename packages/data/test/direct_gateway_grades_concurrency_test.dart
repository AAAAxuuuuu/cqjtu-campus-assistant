import 'dart:async';
import 'dart:io';

import 'package:data/data.dart';
import 'package:flutter_test/flutter_test.dart';

/// `getGrades` with an empty semester fetches the summary page plus one page
/// per recent semester (8). Those were issued strictly serially, so wall time
/// was the sum of 9 round trips — on the campus network (~5.4s measured TTFB,
/// dominated by the TLS handshake) roughly 48 seconds of spinner.
///
/// The per-semester reads are independent, so they now fan out. These tests pin
/// the three properties that fan-out must not break: it really is concurrent,
/// row order is unchanged (dedupe picks the same winner), and one failing
/// semester does not discard the others.

const _loginPageHtml = '''
<html><body>
<form id="pwdFromId">
<input type="hidden" name="execution" value="e1s1" />
<input type="hidden" id="pwdEncryptSalt" value="abcdefghijklmnop" />
</form>
</body></html>
''';

const _scheduleLandingHtml = '''
<html><body><div id="kbtable">timetable</div></body></html>
''';

String _gradesHtmlFor(String semester, {required String courseName}) => '''
<html><body>
<table>
<tr><th>开课学期</th><th>课程编号</th><th>课程名称</th><th>成绩</th><th>学分</th></tr>
<tr>
  <td>$semester</td><td>C-$semester</td><td>$courseName</td>
  <td>88</td><td>3.0</td>
</tr>
</table>
</body></html>
''';

/// Transport that answers by URL rather than by call order, so several requests
/// can legitimately be in flight at once.
class _ConcurrentTransport {
  _ConcurrentTransport({this.gradesResponder});

  final Future<SchoolHttpResponse> Function(String semester)? gradesResponder;

  final List<Uri> requests = [];
  int _inFlight = 0;
  int peakInFlight = 0;

  Future<SchoolHttpResponse> call(
    String method,
    Uri uri, {
    Map<String, String>? headers,
    List<int>? body,
  }) async {
    requests.add(uri);
    _inFlight++;
    peakInFlight = peakInFlight > _inFlight ? peakInFlight : _inFlight;
    try {
      return await _respond(method, uri);
    } finally {
      _inFlight--;
    }
  }

  Future<SchoolHttpResponse> _respond(String method, Uri uri) async {
    // CAS login handshake.
    if (uri.host == 'ids.cqjtu.edu.cn') {
      if (method == 'GET') {
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
      return SchoolHttpResponse(
        statusCode: 200,
        headers: const {'content-type': 'text/html'},
        body: _scheduleLandingHtml,
        cookies: [Cookie('JSESSIONID', 'sess-abc')],
      );
    }

    // Grades pages carry the semester in `kksj`.
    final semester = uri.queryParameters['kksj'] ?? '';
    if (gradesResponder != null) {
      return gradesResponder!(semester);
    }
    return SchoolHttpResponse(
      statusCode: 200,
      headers: const {'content-type': 'text/html'},
      body: _gradesHtmlFor(semester, courseName: 'course-$semester'),
    );
  }
}

void main() {
  group('getGrades all-semesters fan-out', () {
    test('issues the per-semester requests concurrently', () async {
      final gate = Completer<void>();
      var gradeRequests = 0;

      final transport = _ConcurrentTransport(
        gradesResponder: (semester) async {
          // The summary request (empty semester) must settle on its own so the
          // session is established before the fan-out starts.
          if (semester.isEmpty) {
            return SchoolHttpResponse(
              statusCode: 200,
              headers: const {'content-type': 'text/html'},
              body: _gradesHtmlFor('summary', courseName: 'summary'),
            );
          }

          gradeRequests++;
          // Block every per-semester request until they have all arrived. If
          // the implementation were serial this would deadlock, because the
          // second request would never be issued.
          if (gradeRequests >= 8) {
            if (!gate.isCompleted) gate.complete();
          }
          await gate.future;

          return SchoolHttpResponse(
            statusCode: 200,
            headers: const {'content-type': 'text/html'},
            body: _gradesHtmlFor(semester, courseName: 'course-$semester'),
          );
        },
      );

      final gateway = DirectSchoolCampusGateway(transport: transport.call);
      final result = await gateway
          .getGrades('123456789012', 'secret')
          .timeout(const Duration(seconds: 5));

      expect(gradeRequests, 8, reason: 'all recent semesters must be queried');
      expect(
        transport.peakInFlight,
        greaterThan(1),
        reason: 'per-semester requests must overlap, not run one at a time',
      );
      expect(result.grades, isNotEmpty);
    });

    test('preserves semester order so dedupe keeps the same winner', () async {
      final transport = _ConcurrentTransport(
        gradesResponder: (semester) async {
          // Answer later semesters faster, so completion order differs from
          // request order. Output order must still follow request order.
          final isEmpty = semester.isEmpty;
          await Future<void>.delayed(
            Duration(milliseconds: isEmpty ? 0 : 10 - semester.length),
          );
          return SchoolHttpResponse(
            statusCode: 200,
            headers: const {'content-type': 'text/html'},
            body: _gradesHtmlFor(
              isEmpty ? 'summary' : semester,
              courseName: isEmpty ? 'summary' : 'course-$semester',
            ),
          );
        },
      );

      final gateway = DirectSchoolCampusGateway(transport: transport.call);
      final result = await gateway.getGrades('123456789012', 'secret');

      final semesters = result.grades.map((g) => g.semester).toList();
      final sortedDescending = [...semesters]..sort((a, b) => b.compareTo(a));
      expect(
        semesters,
        sortedDescending,
        reason: 'rows must stay in newest-first request order',
      );
    });

    test('one failing semester does not discard the others', () async {
      var failures = 0;

      final transport = _ConcurrentTransport(
        gradesResponder: (semester) async {
          if (semester.isEmpty) {
            return SchoolHttpResponse(
              statusCode: 200,
              headers: const {'content-type': 'text/html'},
              body: _gradesHtmlFor('summary', courseName: 'summary'),
            );
          }
          // Fail exactly one semester.
          if (semester.endsWith('-2') && failures == 0) {
            failures++;
            throw const SocketException('connection reset');
          }
          return SchoolHttpResponse(
            statusCode: 200,
            headers: const {'content-type': 'text/html'},
            body: _gradesHtmlFor(semester, courseName: 'course-$semester'),
          );
        },
      );

      final gateway = DirectSchoolCampusGateway(transport: transport.call);
      final result = await gateway.getGrades('123456789012', 'secret');

      expect(failures, 1);
      expect(
        result.grades,
        hasLength(7),
        reason: 'the seven reachable semesters must still be returned',
      );
    });
  });
}

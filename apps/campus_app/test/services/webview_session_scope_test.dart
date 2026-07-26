import 'package:campus_app/services/webview_session_scope.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('WebView account session scope', () {
    test('keeps the session for the same account', () {
      expect(requiresWebViewSessionReset('student_a', 'student_a'), isFalse);
    });

    test('resets when switching accounts', () {
      expect(requiresWebViewSessionReset('student_a', 'student_b'), isTrue);
    });

    test('resets when the first authenticated account has no marker', () {
      expect(requiresWebViewSessionReset(null, 'student_a'), isTrue);
      expect(requiresWebViewSessionReset('', 'student_a'), isTrue);
    });
  });
}

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:campus_platform/services/session_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  test('clearing a ticket removes both its value and timestamp', () async {
    final service = SessionService();

    await service.saveTicket('student-a', 'single-use-ticket');
    expect(await service.loadTicket('student-a'), 'single-use-ticket');
    expect(await service.loadTicketUpdatedAt('student-a'), isNotNull);

    await service.clearTicket('student-a');

    expect(await service.loadTicket('student-a'), isNull);
    expect(await service.loadTicketUpdatedAt('student-a'), isNull);
  });

  test(
    'clearing login artifacts keeps no session data for that account',
    () async {
      final service = SessionService();

      await service.saveSessionId('student-a', 'session-a');
      await service.saveTicket('student-a', 'ticket-a');
      await service.saveCasCookies('student-a', 'cas=a');
      await service.saveJwgCookies('student-a', 'jwg=a');
      await service.saveEcardCookies('student-a', 'ecard=a');
      await service.saveZoveToken('student-a', 'token-a');

      await service.clearLoginArtifacts('student-a');

      expect(await service.loadSessionId('student-a'), isNull);
      expect(await service.loadTicket('student-a'), isNull);
      expect(await service.loadCasCookies('student-a'), isNull);
      expect(await service.loadJwgCookies('student-a'), isNull);
      expect(await service.loadEcardCookies('student-a'), isNull);
      expect(await service.loadZoveToken('student-a'), isNull);
    },
  );
}

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:campus_platform/services/credential_service.dart';
import 'package:campus_platform/services/session_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
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
      expect(await service.loadAutoLoginAttempts('student-a'), isEmpty);
      expect(await service.loadManualLoginAttempts('student-a'), isEmpty);
      expect(await service.isInSecurityCooldown('student-a'), isFalse);
      expect(await service.loadSportsLoginAttempts('student-a'), isEmpty);
    },
  );

  test(
      'auto-login rate limiter enforces 6 attempts per hour limit and 5-min interval',
      () async {
    final service = SessionService();
    final baseTime = DateTime(2026, 9, 16, 12, 0, 0);

    // Initial state: full quota of 6
    expect(
        await service.canAttemptAutoLogin('student-a', now: baseTime), isTrue);
    expect(
      await service.getRemainingAutoLoginAttempts('student-a', now: baseTime),
      6,
    );

    // Record 1st attempt at t=0
    await service.recordAutoLoginAttempt('student-a', now: baseTime);
    expect((await service.loadAutoLoginAttempts('student-a')).length, 1);

    // At t=3 min: rejected by 5-min minimum interval check
    final at3Min = baseTime.add(const Duration(minutes: 3));
    expect(
        await service.canAttemptAutoLogin('student-a', now: at3Min), isFalse);

    // Anti-race guard in recordAutoLoginAttempt: calling record at t=3min does not append
    await service.recordAutoLoginAttempt('student-a', now: at3Min);
    expect((await service.loadAutoLoginAttempts('student-a')).length, 1);

    // At t=5 min: interval elapsed, permitted
    final at5Min = baseTime.add(const Duration(minutes: 5));
    expect(await service.canAttemptAutoLogin('student-a', now: at5Min), isTrue);

    // Record remaining 5 attempts spaced 6 minutes apart (t=6, 12, 18, 24, 30)
    for (var i = 1; i <= 5; i++) {
      await service.recordAutoLoginAttempt(
        'student-a',
        now: baseTime.add(Duration(minutes: i * 6)),
      );
    }
    expect((await service.loadAutoLoginAttempts('student-a')).length, 6);

    // Quota reached: at t=36 min, canAttempt is false, remaining is 0
    final at36Min = baseTime.add(const Duration(minutes: 36));
    expect(
        await service.canAttemptAutoLogin('student-a', now: at36Min), isFalse);
    expect(
      await service.getRemainingAutoLoginAttempts('student-a', now: at36Min),
      0,
    );

    // 61 minutes after the first attempt: first attempt expires, quota opens up to 1
    final afterOneHour = baseTime.add(const Duration(minutes: 61));
    expect(
      await service.canAttemptAutoLogin('student-a', now: afterOneHour),
      isTrue,
    );
    expect(
      await service.getRemainingAutoLoginAttempts('student-a',
          now: afterOneHour),
      1,
    );

    // Manual login clears quota
    await service.clearAutoLoginAttempts('student-a');
    expect(
      await service.canAttemptAutoLogin(
        'student-a',
        now: at36Min,
      ),
      isTrue,
    );
    expect(
      await service.getRemainingAutoLoginAttempts(
        'student-a',
        now: at36Min,
      ),
      6,
    );
  });

  test('manual login rate limiter enforces 5 failures per hour', () async {
    final service = SessionService();
    final baseTime = DateTime(2026, 9, 16, 12, 0, 0);
    const user = 'manual-student';

    expect(await service.canAttemptManualLogin(user, now: baseTime), isTrue);

    // Record 4 failures
    for (var i = 0; i < 4; i++) {
      await service.recordManualLoginAttempt(
        user,
        now: baseTime.add(Duration(minutes: i * 2)),
      );
    }
    expect(
        await service.canAttemptManualLogin(user,
            now: baseTime.add(const Duration(minutes: 10))),
        isTrue);

    // 5th failure reaches the limit
    await service.recordManualLoginAttempt(
      user,
      now: baseTime.add(const Duration(minutes: 10)),
    );
    expect(
        await service.canAttemptManualLogin(user,
            now: baseTime.add(const Duration(minutes: 10))),
        isFalse);

    // Clear restores quota
    await service.clearManualLoginAttempts(user);
    expect(
        await service.canAttemptManualLogin(user,
            now: baseTime.add(const Duration(minutes: 10))),
        isTrue);
  });

  test('security failures trigger 30-minute cooldown and reset', () async {
    final service = SessionService();
    final baseTime = DateTime(2026, 9, 16, 12, 0, 0);
    const user = 'sec-student';

    expect(await service.isInSecurityCooldown(user, now: baseTime), isFalse);

    // 2 failures: not yet in cooldown
    await service.recordSecurityFailure(user, now: baseTime);
    await service.recordSecurityFailure(user,
        now: baseTime.add(const Duration(minutes: 1)));
    expect(
        await service.isInSecurityCooldown(user,
            now: baseTime.add(const Duration(minutes: 2))),
        isFalse);

    // 3rd failure: enters 30-min cooldown
    await service.recordSecurityFailure(user,
        now: baseTime.add(const Duration(minutes: 2)));
    expect(
        await service.isInSecurityCooldown(user,
            now: baseTime.add(const Duration(minutes: 2))),
        isTrue);
    expect(
        await service.isInSecurityCooldown(user,
            now: baseTime.add(const Duration(minutes: 25))),
        isTrue);

    // After 30 minutes: cooldown expired
    expect(
        await service.isInSecurityCooldown(user,
            now: baseTime.add(const Duration(minutes: 33))),
        isFalse);

    // reset clears state
    await service.recordSecurityFailure(user,
        now: baseTime.add(const Duration(minutes: 35)));
    await service.recordSecurityFailure(user,
        now: baseTime.add(const Duration(minutes: 36)));
    await service.recordSecurityFailure(user,
        now: baseTime.add(const Duration(minutes: 37)));
    expect(
        await service.isInSecurityCooldown(user,
            now: baseTime.add(const Duration(minutes: 37))),
        isTrue);
    await service.resetSecurityFailures(user);
    expect(
        await service.isInSecurityCooldown(user,
            now: baseTime.add(const Duration(minutes: 37))),
        isFalse);
  });

  test('sports login rate limiter enforces 5 attempts per hour', () async {
    final service = SessionService();
    final baseTime = DateTime(2026, 9, 16, 12, 0, 0);
    const user = 'sports-student';

    expect(await service.canAttemptSportsLogin(user, now: baseTime), isTrue);

    for (var i = 0; i < 5; i++) {
      await service.recordSportsLoginAttempt(
        user,
        now: baseTime.add(Duration(minutes: i * 2)),
      );
    }
    expect(
        await service.canAttemptSportsLogin(user,
            now: baseTime.add(const Duration(minutes: 15))),
        isFalse);

    await service.clearSportsLoginAttempts(user);
    expect(
        await service.canAttemptSportsLogin(user,
            now: baseTime.add(const Duration(minutes: 15))),
        isTrue);
  });

  test('auth circuit breaker marks, checks, and resets state per account',
      () async {
    final service = SessionService();
    const user = 'cb-student';

    expect(await service.isAuthCircuitBroken(user), isFalse);
    expect(await service.canAttemptAutoLogin(user), isTrue);

    await service.markAuthCircuitBroken(user);
    expect(await service.isAuthCircuitBroken(user), isTrue);
    expect(await service.canAttemptAutoLogin(user), isFalse);
    expect(await service.getRemainingAutoLoginAttempts(user), 0);

    // Another account is unaffected
    expect(await service.isAuthCircuitBroken('other-user'), isFalse);
    expect(await service.canAttemptAutoLogin('other-user'), isTrue);

    await service.resetAuthCircuitBreaker(user);
    expect(await service.isAuthCircuitBroken(user), isFalse);
    expect(await service.canAttemptAutoLogin(user), isTrue);

    // clearLoginArtifacts also clears circuit breaker
    await service.markAuthCircuitBroken(user);
    expect(await service.isAuthCircuitBroken(user), isTrue);
    await service.clearLoginArtifacts(user);
    expect(await service.isAuthCircuitBroken(user), isFalse);
  });

  test('CredentialService.save clears circuit breaker and auto-login attempts',
      () async {
    final sessionService = SessionService();
    final credService = CredentialService();
    const user = 'cred-user';

    await sessionService.markAuthCircuitBroken(user);
    await sessionService.recordAutoLoginAttempt(user);
    expect(await sessionService.isAuthCircuitBroken(user), isTrue);
    expect((await sessionService.loadAutoLoginAttempts(user)).length, 1);

    await credService.save(user, 'new-secret-password');

    expect(await sessionService.isAuthCircuitBroken(user), isFalse);
    expect(await sessionService.loadAutoLoginAttempts(user), isEmpty);
    expect(await sessionService.canAttemptAutoLogin(user), isTrue);
  });
}

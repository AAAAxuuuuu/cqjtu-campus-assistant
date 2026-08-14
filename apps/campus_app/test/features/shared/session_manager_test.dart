import 'dart:async';

import 'package:campus_app/providers/session.dart';
import 'package:core/models/course.dart';
import 'package:data/data.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeSessionApi implements CampusSessionApi {
  int createSessionCalls = 0;
  int loginWithTicketCalls = 0;
  final Map<String, int> injectCookieCalls = {};
  Object? createSessionError;
  Object? loginWithTicketError;
  Object? injectCookiesError;
  final List<String> sessionIds = [];
  String nextSessionId = 'session-0';
  String? scheduleResult;
  Object? scheduleError;

  @override
  Future<String> createSession(String username) async {
    createSessionCalls++;
    final error = createSessionError;
    if (error != null) throw error;
    final id = 'session-$createSessionCalls';
    sessionIds.add(id);
    return id;
  }

  @override
  Future<void> loginWithTicket(
    String username,
    String ticket, {
    required String sessionId,
  }) async {
    loginWithTicketCalls++;
    final error = loginWithTicketError;
    if (error != null) throw error;
  }

  @override
  Future<void> injectCookies(
    String username,
    String domain,
    String cookies, {
    required String sessionId,
  }) async {
    injectCookieCalls[domain] = (injectCookieCalls[domain] ?? 0) + 1;
    final error = injectCookiesError;
    if (error != null) throw error;
  }

  @override
  Future<({List<Course> courses, String remark})> getSchedule(
    String username,
    String password, {
    required String sessionId,
    String? semester,
    bool forceRefresh = false,
  }) async {
    final error = scheduleError;
    if (error != null) throw error;
    return (courses: const <Course>[], remark: scheduleResult ?? '');
  }
}

class _FakeSessionStore implements SelfHostedSessionStore {
  final Map<String, String> values = {};
  final Set<String> clearedTickets = {};

  @override
  Future<String?> loadSessionId(String username) async =>
      values['sid:$username'];

  @override
  Future<void> saveSessionId(String username, String sessionId) async {
    values['sid:$username'] = sessionId;
  }

  @override
  Future<String?> loadTicket(String username) async =>
      values['ticket:$username'];

  @override
  Future<void> saveTicket(String username, String ticket) async {
    values['ticket:$username'] = ticket;
  }

  @override
  Future<void> clearTicket(String username) async {
    values.remove('ticket:$username');
    clearedTickets.add(username);
  }

  @override
  Future<void> clearLoginArtifacts(String username) async {}

  @override
  Future<String?> loadCasCookies(String username) async =>
      values['cas:$username'];

  @override
  Future<void> saveCasCookies(String username, String cookies) async {
    values['cas:$username'] = cookies;
  }

  @override
  Future<String?> loadJwgCookies(String username) async =>
      values['jwg:$username'];

  @override
  Future<void> saveJwgCookies(String username, String cookies) async {
    values['jwg:$username'] = cookies;
  }

  @override
  Future<String?> loadEcardCookies(String username) async =>
      values['ecard:$username'];

  @override
  Future<void> saveEcardCookies(String username, String cookies) async {
    values['ecard:$username'] = cookies;
  }

  @override
  Future<String?> loadZoveToken(String username) async =>
      values['zove:$username'];

  @override
  Future<void> saveZoveToken(String username, String token) async {
    values['zove:$username'] = token;
  }
}

Future<void> _flushSnapshots() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

SessionManager _buildManager({
  required _FakeSessionApi api,
  required _FakeSessionStore store,
  required ProviderContainer container,
}) {
  return SessionManager(
    api,
    store,
    container.read(recoveryHealthProvider.notifier),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('RecoverySnapshot', () {
    test('round-trips through JSON', () {
      final original = RecoverySnapshot(
        domain: SystemDomain.schedule,
        state: RecoveryState.degraded,
        failureKind: RecoveryFailureKind.transientNetwork,
        message: 'boom',
        retryCount: 2,
        updatedAt: DateTime.fromMillisecondsSinceEpoch(1234567),
        latencyMs: 42,
      );
      final decoded = RecoverySnapshot.fromJson(
        original.toJson(),
        SystemDomain.schedule,
      );
      expect(decoded, isNotNull);
      expect(decoded!.state, RecoveryState.degraded);
      expect(decoded.failureKind, RecoveryFailureKind.transientNetwork);
      expect(decoded.message, 'boom');
      expect(decoded.retryCount, 2);
      expect(decoded.updatedAt.millisecondsSinceEpoch, 1234567);
      expect(decoded.latencyMs, 42);
    });

    test('returns null for corrupt json', () {
      expect(
        RecoverySnapshot.fromJson({'state': 'nope'}, SystemDomain.oneCard),
        isNull,
      );
    });
  });

  group('SessionManager failure classification', () {
    late ProviderContainer container;
    late _FakeSessionApi api;
    late _FakeSessionStore store;
    late SessionManager manager;

    setUp(() {
      container = ProviderContainer();
      api = _FakeSessionApi();
      store = _FakeSessionStore();
      manager = _buildManager(api: api, store: store, container: container);
    });

    tearDown(() {
      container.dispose();
    });

    test('classifies session-expired ApiException', () {
      expect(
        manager.isSessionExpiredError(ApiException(403, 'sessionId expired')),
        isTrue,
      );
      expect(
        manager.isSessionExpiredError(ApiException(500, 'sessionId expired')),
        isFalse,
      );
    });

    test('classifies captcha as security verification', () {
      expect(
        manager.isSecurityVerificationError(CaptchaRequiredException()),
        isTrue,
      );
    });

    test('classifies timeouts as transient network', () {
      expect(manager.isTransientNetworkError(TimeoutException('t')), isTrue);
      expect(
        manager.isTransientNetworkError(ApiException(-1, 'connection reset')),
        isTrue,
      );
    });

    test('classifies 401 as auth invalid, not transient network', () {
      expect(
        manager.isTransientNetworkError(ApiException(401, 'unauthorized')),
        isFalse,
      );
      expect(
        manager.isSessionExpiredError(ApiException(401, 'unauthorized')),
        isFalse,
      );
    });
  });

  group('SessionManager runWithRecovery', () {
    late ProviderContainer container;
    late _FakeSessionApi api;
    late _FakeSessionStore store;
    late SessionManager manager;

    setUp(() {
      container = ProviderContainer();
      api = _FakeSessionApi();
      store = _FakeSessionStore();
      manager = _buildManager(api: api, store: store, container: container);
    });

    tearDown(() {
      container.dispose();
    });

    test(
      'marks healthy on success without creating a second session',
      () async {
        final result = await manager.runWithRecovery<String>(
          domain: SystemDomain.schedule,
          username: 'u1',
          request: (sessionId) async => 'ok:$sessionId',
        );
        expect(result, 'ok:session-1');
        expect(api.createSessionCalls, 1);
        await _flushSnapshots();

        final health = container.read(
          systemHealthProvider(SystemDomain.schedule),
        );
        expect(health.state, RecoveryState.healthy);
        expect(health.retryCount, 0);
      },
    );

    test('recovers once on session-expired failure', () async {
      var calls = 0;
      final result = await manager.runWithRecovery<String>(
        domain: SystemDomain.schedule,
        username: 'u1',
        request: (sessionId) async {
          calls++;
          if (calls == 1) throw ApiException(403, 'sessionId expired');
          return 'recovered';
        },
      );
      expect(result, 'recovered');
      expect(calls, 2);
      expect(
        api.createSessionCalls,
        2,
        reason: 'recovery refreshes the session',
      );
      await _flushSnapshots();
      final health = container.read(
        systemHealthProvider(SystemDomain.schedule),
      );
      expect(health.state, RecoveryState.healthy);
      expect(health.retryCount, 1);
    });

    test('rethrows non-recoverable failures without recovery', () async {
      var calls = 0;
      await expectLater(
        manager.runWithRecovery<String>(
          domain: SystemDomain.schedule,
          username: 'u1',
          request: (sessionId) async {
            calls++;
            throw StateError('unexpected');
          },
        ),
        throwsStateError,
      );
      expect(calls, 1);
      expect(api.createSessionCalls, 1);
    });

    test(
      'throws ManualVerificationRequiredException on repeated manual failures',
      () async {
        api.loginWithTicketError = CaptchaRequiredException();
        store.values['ticket:u1'] = 'stale-ticket';

        await expectLater(
          manager.runWithRecovery<String>(
            domain: SystemDomain.oneCard,
            username: 'u1',
            request: (sessionId) async {
              throw CaptchaRequiredException();
            },
          ),
          throwsA(isA<ManualVerificationRequiredException>()),
        );
        await _flushSnapshots();

        final health = container.read(
          systemHealthProvider(SystemDomain.oneCard),
        );
        expect(health.state, RecoveryState.manualRequired);
      },
    );

    test('second recovery attempt within backoff is blocked', () async {
      api.loginWithTicketError = CaptchaRequiredException();
      store.values['ticket:u1'] = 'stale-ticket';

      Future<void> failingRun() => manager.runWithRecovery<String>(
        domain: SystemDomain.oneCard,
        username: 'u1',
        request: (sessionId) async {
          throw CaptchaRequiredException();
        },
      );

      await expectLater(
        failingRun(),
        throwsA(isA<ManualVerificationRequiredException>()),
      );
      await _flushSnapshots();
      // Backoff is now active; the next run must refuse immediately.
      await expectLater(
        failingRun(),
        throwsA(isA<ManualVerificationRequiredException>()),
      );
      await _flushSnapshots();
      expect(
        (container.read(recoveryHealthProvider)[SystemDomain.oneCard]!).state,
        RecoveryState.manualRequired,
      );
    });

    test('restoreLoginState falls back to cookies when ticket fails', () async {
      api.loginWithTicketError = ApiException(401, 'bad ticket');
      store.values['ticket:u1'] = 'stale-ticket';
      store.values['cas:u1'] = 'CASCOOKIE';
      store.values['jwg:u1'] = 'JWGCOOKIE';
      store.values['ecard:u1'] = 'ECARDCOOKIE';

      await manager.restoreLoginState('u1', 'session-9');

      expect(api.injectCookieCalls['ids.cqjtu.edu.cn'], 1);
      expect(api.injectCookieCalls['jwgln.cqjtu.edu.cn'], 1);
      expect(api.injectCookieCalls['ecard.cqjtu.edu.cn'], 1);
      expect(store.clearedTickets, contains('u1'));
    });

    test(
      'restoreLoginState throws the ticket failure when nothing else restores',
      () async {
        api.loginWithTicketError = ApiException(401, 'bad ticket');
        store.values['ticket:u1'] = 'stale-ticket';

        await expectLater(
          manager.restoreLoginState('u1', 'session-9'),
          throwsA(isA<ApiException>()),
        );
      },
    );
  });

  group('SessionManager ensureSessionId', () {
    test('reuses the persisted session id without recreating', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final api = _FakeSessionApi();
      final store = _FakeSessionStore()..values['sid:u1'] = 'persisted-session';
      final manager = _buildManager(
        api: api,
        store: store,
        container: container,
      );

      expect(await manager.ensureSessionId('u1'), 'persisted-session');
      expect(api.createSessionCalls, 0);
    });

    test('creates and persists a new session when none exists', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final api = _FakeSessionApi();
      final store = _FakeSessionStore();
      final manager = _buildManager(
        api: api,
        store: store,
        container: container,
      );

      expect(await manager.ensureSessionId('u1'), 'session-1');
      expect(store.values['sid:u1'], 'session-1');
      expect(api.createSessionCalls, 1);
    });
  });
}

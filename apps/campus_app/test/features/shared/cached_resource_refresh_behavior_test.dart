import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:campus_app/features/auth/auth_providers.dart';
import 'package:campus_app/features/shared/cached_resource.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

typedef _ProbeFetch = Future<String> Function(String username);

final _probeFetchProvider = Provider<_ProbeFetch>((ref) {
  throw UnimplementedError('Tests must override _probeFetchProvider.');
});

final _probeFreshnessProvider = Provider<Duration?>((ref) => null);

final _probeProvider = NotifierProvider<_ProbeNotifier, CachedResource<String>>(
  _ProbeNotifier.new,
);

class _ProbeNotifier extends SimpleCachedResourceNotifier<String> {
  @override
  String get emptyData => '';

  @override
  String get cacheNamespace => 'probe_refresh_behavior';

  @override
  Duration? get cacheFreshness => ref.read(_probeFreshnessProvider);

  @override
  Object? encode(String data) => data;

  @override
  String decode(Object? json) => json?.toString() ?? '';

  @override
  Future<String> fetch(
    ({String username, String password}) credentials, {
    required bool forceRefresh,
  }) => ref.read(_probeFetchProvider)(credentials.username);
}

Future<void> _settle() async {
  for (var i = 0; i < 8; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('CachedResource refresh serialization', () {
    test('plain refresh joins the in-flight chain (dedup preserved)', () async {
      var fetchCalls = 0;
      final gate = Completer<String>();
      final container = ProviderContainer(
        overrides: [
          _probeFetchProvider.overrideWithValue((username) {
            fetchCalls++;
            return gate.future;
          }),
        ],
      );
      addTearDown(container.dispose);
      container.read(credentialsProvider.notifier).set('u', 'p');
      container.read(_probeProvider);
      await Future<void>.delayed(Duration.zero);

      final t1 = container.read(_probeProvider.notifier).refresh();
      final t2 = container.read(_probeProvider.notifier).refresh();
      expect(fetchCalls, 1, reason: 'joined refresh must not start a fetch');

      gate.complete('data');
      await Future.wait([t1, t2]);
      await _settle();
      expect(container.read(_probeProvider).data, 'data');
    });

    test('concurrent force refreshes merge into a single request', () async {
      var inFlight = 0;
      var maxInFlight = 0;
      var fetchCalls = 0;
      final gates = <Completer<String>>[];
      final container = ProviderContainer(
        overrides: [
          _probeFetchProvider.overrideWithValue((username) {
            fetchCalls++;
            inFlight++;
            maxInFlight = math.max(maxInFlight, inFlight);
            final gate = Completer<String>();
            gates.add(gate);
            return gate.future.whenComplete(() => inFlight--);
          }),
        ],
      );
      addTearDown(container.dispose);
      container.read(credentialsProvider.notifier).set('u', 'p');
      container.read(_probeProvider);
      await Future<void>.delayed(Duration.zero);
      expect(gates.length, 1); // initial restore refresh

      gates[0].complete('initial');
      await _settle();
      expect(container.read(_probeProvider).data, 'initial');

      final f1 = container
          .read(_probeProvider.notifier)
          .refresh(forceRefresh: true);
      final f2 = container
          .read(_probeProvider.notifier)
          .refresh(forceRefresh: true);
      final f3 = container
          .read(_probeProvider.notifier)
          .refresh(forceRefresh: true);

      await Future<void>.delayed(Duration.zero);
      expect(gates.length, 2, reason: 'one merged force request is queued');
      expect(maxInFlight, 1);

      gates[1].complete('force-merged');
      await Future.wait([f1, f2, f3]);
      await _settle();

      expect(maxInFlight, 1, reason: 'never two concurrent requests');
      expect(fetchCalls, 2, reason: 'initial + exactly one merged force');
      expect(container.read(_probeProvider).data, 'force-merged');
    });

    test(
      'a force refresh while a force is already running merges, not queues',
      () async {
        var fetchCalls = 0;
        final gates = <Completer<String>>[];
        final container = ProviderContainer(
          overrides: [
            _probeFetchProvider.overrideWithValue((username) {
              fetchCalls++;
              final gate = Completer<String>();
              gates.add(gate);
              return gate.future;
            }),
          ],
        );
        addTearDown(container.dispose);
        container.read(credentialsProvider.notifier).set('u', 'p');
        container.read(_probeProvider);
        await Future<void>.delayed(Duration.zero);
        gates[0].complete('initial');
        await _settle();

        final f1 = container
            .read(_probeProvider.notifier)
            .refresh(forceRefresh: true);
        await Future<void>.delayed(Duration.zero);
        expect(gates.length, 2, reason: 'first force started');

        // Second force arrives while the first force is in flight.
        final f2 = container
            .read(_probeProvider.notifier)
            .refresh(forceRefresh: true);

        gates[1].complete('first-force');
        await Future.wait([f1, f2]);
        await _settle();

        expect(fetchCalls, 2, reason: 'no second force request is issued');
        expect(container.read(_probeProvider).data, 'first-force');
      },
    );

    test(
      'a failed in-flight refresh does not block queued force refresh',
      () async {
        final gates = <Completer<String>>[];
        final container = ProviderContainer(
          overrides: [
            _probeFetchProvider.overrideWithValue((username) {
              final gate = Completer<String>();
              gates.add(gate);
              return gate.future;
            }),
          ],
        );
        addTearDown(container.dispose);
        container.read(credentialsProvider.notifier).set('u', 'p');
        container.read(_probeProvider);
        await Future<void>.delayed(Duration.zero);

        final f1 = container
            .read(_probeProvider.notifier)
            .refresh(forceRefresh: true);
        final f2 = container
            .read(_probeProvider.notifier)
            .refresh(forceRefresh: true);

        await Future<void>.delayed(Duration.zero);
        expect(
          gates.length,
          1,
          reason: 'force refreshes queue behind the initial fetch',
        );

        gates[0].completeError(Exception('boom'));
        await _settle();
        expect(
          gates.length,
          2,
          reason: 'the single merged force refresh runs after the failure',
        );
        expect(container.read(_probeProvider).hasData, isFalse);

        gates[1].complete('recovered');
        await Future.wait([f1, f2]);
        await _settle();
        expect(
          gates.length,
          2,
          reason: 'f2 merged into f1; no third request is issued',
        );
        expect(container.read(_probeProvider).data, 'recovered');
      },
    );
  });

  group('refresh queue account safety', () {
    test('a queued force is dropped when the account switches, without using '
        'the new credentials', () async {
      final fetchUsernames = <String>[];
      final gates = <Completer<String>>[];
      final container = ProviderContainer(
        overrides: [
          _probeFetchProvider.overrideWithValue((username) {
            fetchUsernames.add(username);
            final gate = Completer<String>();
            gates.add(gate);
            return gate.future;
          }),
        ],
      );
      addTearDown(container.dispose);
      container.read(credentialsProvider.notifier).set('account_a', 'p');
      container.read(_probeProvider);
      await Future<void>.delayed(Duration.zero);

      // A is slow; queue a force for A behind it.
      final queuedForce = container
          .read(_probeProvider.notifier)
          .refresh(forceRefresh: true);
      await Future<void>.delayed(Duration.zero);
      expect(gates.length, 1);

      // Switch to B while A's force is still queued.
      container.read(credentialsProvider.notifier).set('account_b', 'p');
      await Future<void>.delayed(Duration.zero);

      // B's restore refresh starts immediately (different account).
      await _settle();
      final bGates = gates.length;
      expect(bGates, 2, reason: 'account B starts its own fetch');

      // Release A's in-flight fetch; its queued force must be dropped.
      gates[0].complete('a_data');
      await _settle();

      // No request may have been issued with B's credentials for A's
      // queued force. The only B fetch is the one B started itself.
      final bFetches = fetchUsernames.where((u) => u == 'account_b').length;
      expect(bFetches, 1, reason: 'queued force must not use new creds');

      // The queued force future resolves without throwing.
      await queuedForce;

      // B's own fetch completes normally.
      gates[1].complete('b_data');
      await _settle();
      expect(container.read(_probeProvider).data, 'b_data');
    });

    test(
      'a joined refresh does not propagate failures it did not request',
      () async {
        final gates = <Completer<String>>[];
        final container = ProviderContainer(
          overrides: [
            _probeFetchProvider.overrideWithValue((username) {
              final gate = Completer<String>();
              gates.add(gate);
              return gate.future;
            }),
          ],
        );
        addTearDown(container.dispose);
        container.read(credentialsProvider.notifier).set('u', 'p');
        container.read(_probeProvider);
        await Future<void>.delayed(Duration.zero);
        gates[0].complete('initial');
        await _settle();

        // A force that will fail, with error propagation requested.
        final failing = container
            .read(_probeProvider.notifier)
            .refresh(forceRefresh: true, throwOnError: true);
        final failingExpectation = expectLater(failing, throwsStateError);
        await Future<void>.delayed(Duration.zero);
        expect(gates.length, 2);

        // A plain refresh joins the chain without asking for errors.
        final joined = container.read(_probeProvider.notifier).refresh();

        gates[1].completeError(StateError('force failed'));
        await _settle();

        // The requesting caller sees the error...
        await failingExpectation;
        // ...the joined caller resolves with the current state instead of
        // producing an unhandled async error.
        expect(await joined, isA<CachedResource<String>>());
      },
    );

    test(
      'joined plain refresh with throwOnError: true observes in-flight failure',
      () async {
        final gates = <Completer<String>>[];
        final container = ProviderContainer(
          overrides: [
            _probeFetchProvider.overrideWithValue((username) {
              final gate = Completer<String>();
              gates.add(gate);
              return gate.future;
            }),
          ],
        );
        addTearDown(container.dispose);
        container.read(credentialsProvider.notifier).set('u', 'p');
        container.read(_probeProvider);
        await Future<void>.delayed(Duration.zero);
        gates[0].complete('initial');
        await _settle();

        // Original force started WITHOUT error propagation.
        final original = container
            .read(_probeProvider.notifier)
            .refresh(forceRefresh: true, throwOnError: false);
        await Future<void>.delayed(Duration.zero);
        expect(gates.length, 2);

        // Joined plain caller asks for errors.
        final joined = container
            .read(_probeProvider.notifier)
            .refresh(forceRefresh: false, throwOnError: true);
        final joinedExpectation = expectLater(joined, throwsStateError);

        gates[1].completeError(StateError('in-flight failed'));
        await _settle();

        await original;
        await joinedExpectation;
      },
    );

    test(
      'merged throwOnError caller ignores failure from another account after switch',
      () async {
        var aCount = 0;
        final aInitial = Completer<String>();
        final aFetch = Completer<String>();
        final bFetch = Completer<String>();
        final container = ProviderContainer(
          overrides: [
            _probeFetchProvider.overrideWithValue((username) {
              if (username == 'account_a') {
                aCount++;
                return aCount == 1 ? aInitial.future : aFetch.future;
              }
              return bFetch.future;
            }),
          ],
        );
        addTearDown(container.dispose);
        container.read(credentialsProvider.notifier).set('account_a', 'p');
        container.read(_probeProvider);
        await Future<void>.delayed(Duration.zero);
        aInitial.complete('initial_a');
        await _settle();

        // Account A: start force refresh without throwOnError.
        final original = container
            .read(_probeProvider.notifier)
            .refresh(forceRefresh: true, throwOnError: false);
        await Future<void>.delayed(Duration.zero);

        // Account A: merge force refresh with throwOnError.
        final merged = container
            .read(_probeProvider.notifier)
            .refresh(forceRefresh: true, throwOnError: true);

        // Switch to Account B while A's request is in flight.
        container.read(credentialsProvider.notifier).set('account_b', 'p');
        await _settle();

        // Account B fails, setting state.error.
        bFetch.completeError(StateError('B failed'));
        await _settle();
        expect(container.read(_probeProvider).error, isNotNull);

        // Account A completes successfully.
        aFetch.complete('a_success');
        await _settle();

        // Original finishes without throwing.
        await original;
        // Merged caller of A must not throw B's error!
        await merged;
      },
    );

    test(
      'merged throwOnError caller preserves original failure even if another account cleared state.error',
      () async {
        var aCount = 0;
        final aInitial = Completer<String>();
        final aFetch = Completer<String>();
        final bFetch = Completer<String>();
        final container = ProviderContainer(
          overrides: [
            _probeFetchProvider.overrideWithValue((username) {
              if (username == 'account_a') {
                aCount++;
                return aCount == 1 ? aInitial.future : aFetch.future;
              }
              return bFetch.future;
            }),
          ],
        );
        addTearDown(container.dispose);
        container.read(credentialsProvider.notifier).set('account_a', 'p');
        container.read(_probeProvider);
        await Future<void>.delayed(Duration.zero);
        aInitial.complete('initial_a');
        await _settle();

        // Account A: start force refresh without throwOnError.
        final original = container
            .read(_probeProvider.notifier)
            .refresh(forceRefresh: true, throwOnError: false);
        await Future<void>.delayed(Duration.zero);

        // Account A: merge force refresh with throwOnError.
        final merged = container
            .read(_probeProvider.notifier)
            .refresh(forceRefresh: true, throwOnError: true);
        final mergedExpectation = expectLater(
          merged,
          throwsA(
            isA<StateError>().having((e) => e.message, 'message', 'A failed'),
          ),
        );

        // Switch to Account B.
        container.read(credentialsProvider.notifier).set('account_b', 'p');
        await _settle();

        // Account B completes successfully (state.error is null).
        bFetch.complete('b_success');
        await _settle();
        expect(container.read(_probeProvider).error, isNull);

        // Account A fails.
        aFetch.completeError(StateError('A failed'));
        await _settle();

        await original;
        // Merged caller of A still observes A's failure despite state.error being null.
        await mergedExpectation;
      },
    );

    test(
      'merged throwOnError caller throws original failure when both accounts fail',
      () async {
        var aCount = 0;
        final aInitial = Completer<String>();
        final aFetch = Completer<String>();
        final bFetch = Completer<String>();
        final container = ProviderContainer(
          overrides: [
            _probeFetchProvider.overrideWithValue((username) {
              if (username == 'account_a') {
                aCount++;
                return aCount == 1 ? aInitial.future : aFetch.future;
              }
              return bFetch.future;
            }),
          ],
        );
        addTearDown(container.dispose);
        container.read(credentialsProvider.notifier).set('account_a', 'p');
        container.read(_probeProvider);
        await Future<void>.delayed(Duration.zero);
        aInitial.complete('initial_a');
        await _settle();

        // Account A: start force refresh without throwOnError.
        final original = container
            .read(_probeProvider.notifier)
            .refresh(forceRefresh: true, throwOnError: false);
        await Future<void>.delayed(Duration.zero);

        // Account A: merge force refresh with throwOnError.
        final merged = container
            .read(_probeProvider.notifier)
            .refresh(forceRefresh: true, throwOnError: true);
        final mergedExpectation = expectLater(
          merged,
          throwsA(
            isA<StateError>().having((e) => e.message, 'message', 'A failed'),
          ),
        );

        // Switch to Account B.
        container.read(credentialsProvider.notifier).set('account_b', 'p');
        await _settle();

        // Account B fails.
        bFetch.completeError(StateError('B failed'));
        await _settle();

        // Account A fails.
        aFetch.completeError(StateError('A failed'));
        await _settle();

        await original;
        // Merged caller throws A's error, not B's error.
        await mergedExpectation;
      },
    );

    test(
      'queued and in-flight tasks resolve cleanly when provider is disposed',
      () async {
        final gates = <Completer<String>>[];
        final container = ProviderContainer(
          overrides: [
            _probeFetchProvider.overrideWithValue((username) {
              final gate = Completer<String>();
              gates.add(gate);
              return gate.future;
            }),
          ],
        );
        container.read(credentialsProvider.notifier).set('u', 'p');
        container.read(_probeProvider);
        await Future<void>.delayed(Duration.zero);
        gates[0].complete('initial');
        await _settle();

        final inFlight = container
            .read(_probeProvider.notifier)
            .refresh(forceRefresh: true);
        await Future<void>.delayed(Duration.zero);
        expect(gates.length, 2);

        final queued = container
            .read(_probeProvider.notifier)
            .refresh(forceRefresh: true);

        // Dispose container while in-flight is running and another is queued
        container.dispose();
        await _settle();

        // Complete in-flight
        gates[1].complete('late_data');
        await _settle();

        // Both futures complete without throwing
        await expectLater(inFlight, completes);
        await expectLater(queued, completes);
      },
    );
  });

  test(
    'a merged throwOnError caller still observes the original failure',
    () async {
      final gates = <Completer<String>>[];
      final container = ProviderContainer(
        overrides: [
          _probeFetchProvider.overrideWithValue((username) {
            final gate = Completer<String>();
            gates.add(gate);
            return gate.future;
          }),
        ],
      );
      addTearDown(container.dispose);
      container.read(credentialsProvider.notifier).set('u', 'p');
      container.read(_probeProvider);
      await Future<void>.delayed(Duration.zero);
      gates[0].complete('initial');
      await _settle();

      // Original force started WITHOUT error propagation.
      final original = container
          .read(_probeProvider.notifier)
          .refresh(forceRefresh: true);
      await Future<void>.delayed(Duration.zero);
      expect(gates.length, 2);

      // Merged caller asks for errors.
      final merged = container
          .read(_probeProvider.notifier)
          .refresh(forceRefresh: true, throwOnError: true);

      // Attach the expectation before the failure fires so the merged
      // rejection never becomes an unhandled async error.
      final mergedExpectation = expectLater(merged, throwsStateError);
      gates[1].completeError(StateError('original force failed'));
      await _settle();

      // The original caller swallows the failure by contract...
      await original;
      // ...while the merged caller observes it.
      await mergedExpectation;
    },
  );

  test('a merged throwOnError caller resolves normally on success', () async {
    final gates = <Completer<String>>[];
    final container = ProviderContainer(
      overrides: [
        _probeFetchProvider.overrideWithValue((username) {
          final gate = Completer<String>();
          gates.add(gate);
          return gate.future;
        }),
      ],
    );
    addTearDown(container.dispose);
    container.read(credentialsProvider.notifier).set('u', 'p');
    container.read(_probeProvider);
    await Future<void>.delayed(Duration.zero);
    gates[0].complete('initial');
    await _settle();

    final original = container
        .read(_probeProvider.notifier)
        .refresh(forceRefresh: true);
    await Future<void>.delayed(Duration.zero);
    final merged = container
        .read(_probeProvider.notifier)
        .refresh(forceRefresh: true, throwOnError: true);

    gates[1].complete('ok');
    await Future.wait([original, merged]);
    await _settle();
    expect(container.read(_probeProvider).data, 'ok');
  });

  group('CachedResource cacheFreshness', () {
    test('skips the network while the cache is fresh', () async {
      var fetchCalls = 0;
      final container = ProviderContainer(
        overrides: [
          _probeFetchProvider.overrideWithValue((username) {
            fetchCalls++;
            return Future.value('fresh-$fetchCalls');
          }),
          _probeFreshnessProvider.overrideWithValue(const Duration(hours: 2)),
        ],
      );
      addTearDown(container.dispose);
      container.read(credentialsProvider.notifier).set('u', 'p');
      container.read(_probeProvider);
      await _settle();
      expect(fetchCalls, 1);

      await container.read(_probeProvider.notifier).refresh();
      expect(fetchCalls, 1, reason: 'fresh cache skips the network');

      await container.read(_probeProvider.notifier).refresh(forceRefresh: true);
      expect(fetchCalls, 2, reason: 'force refresh bypasses freshness');
      await _settle();
      expect(container.read(_probeProvider).data, 'fresh-2');
    });

    test('restored fresh cache skips the startup network request', () async {
      var fetchCalls = 0;
      final cacheKey = resourceCacheKey(
        'probe_refresh_behavior',
        username: 'u',
        scope: null,
      );
      SharedPreferences.setMockInitialValues({
        cacheKey: jsonEncode({
          'updatedAtMs': DateTime.now().millisecondsSinceEpoch,
          'data': 'cached_data',
        }),
      });
      final container = ProviderContainer(
        overrides: [
          _probeFetchProvider.overrideWithValue((username) {
            fetchCalls++;
            return Future.value('network_data');
          }),
          _probeFreshnessProvider.overrideWithValue(const Duration(hours: 2)),
        ],
      );
      addTearDown(container.dispose);
      container.read(credentialsProvider.notifier).set('u', 'p');
      container.read(_probeProvider);
      await _settle();

      expect(fetchCalls, 0, reason: 'fresh restored cache avoids the network');
      expect(container.read(_probeProvider).data, 'cached_data');
    });

    test('future-dated cache (clock rollback) is treated as stale', () async {
      var fetchCalls = 0;
      final cacheKey = resourceCacheKey(
        'probe_refresh_behavior',
        username: 'u',
        scope: null,
      );
      SharedPreferences.setMockInitialValues({
        cacheKey: jsonEncode({
          'updatedAtMs': DateTime.now()
              .add(const Duration(hours: 1))
              .millisecondsSinceEpoch,
          'data': 'future_dated_data',
        }),
      });
      final container = ProviderContainer(
        overrides: [
          _probeFetchProvider.overrideWithValue((username) {
            fetchCalls++;
            return Future.value('network_data');
          }),
          _probeFreshnessProvider.overrideWithValue(const Duration(hours: 2)),
        ],
      );
      addTearDown(container.dispose);
      container.read(credentialsProvider.notifier).set('u', 'p');
      container.read(_probeProvider);
      await _settle();

      expect(fetchCalls, 1, reason: 'negative age must not skip the network');
      expect(container.read(_probeProvider).data, 'network_data');
    });

    test('null freshness never skips the network', () async {
      var fetchCalls = 0;
      final container = ProviderContainer(
        overrides: [
          _probeFetchProvider.overrideWithValue((username) {
            fetchCalls++;
            return Future.value('data-$fetchCalls');
          }),
          _probeFreshnessProvider.overrideWithValue(null),
        ],
      );
      addTearDown(container.dispose);
      container.read(credentialsProvider.notifier).set('u', 'p');
      container.read(_probeProvider);
      await _settle();
      expect(fetchCalls, 1);

      await container.read(_probeProvider.notifier).refresh();
      expect(fetchCalls, 2);
    });
  });
}

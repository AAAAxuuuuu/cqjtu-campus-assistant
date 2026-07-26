import 'dart:async';
import 'dart:convert';

import 'package:campus_app/features/auth/auth_providers.dart';
import 'package:campus_app/features/shared/cached_resource.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

typedef _ProbeFetch = Future<String> Function(String username);

final _probeFetchProvider = Provider<_ProbeFetch>((ref) {
  throw UnimplementedError('Tests must override _probeFetchProvider.');
});

final _probeProvider = NotifierProvider<_ProbeNotifier, CachedResource<String>>(
  _ProbeNotifier.new,
);

class _ProbeNotifier extends SimpleCachedResourceNotifier<String> {
  @override
  String get emptyData => '';

  @override
  String get cacheNamespace => 'probe';

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

Future<void> _flushAsyncWork() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Cached resource account isolation', () {
    test('does not restore another account legacy global cache', () async {
      SharedPreferences.setMockInitialValues({
        resourceCacheKey('probe', username: null, scope: null): jsonEncode({
          'updatedAtMs': 1,
          'data': 'student_a_legacy_data',
        }),
      });
      final fetchStarted = Completer<void>();
      final pendingFetch = Completer<String>();
      final container = ProviderContainer(
        overrides: [
          _probeFetchProvider.overrideWithValue((username) {
            fetchStarted.complete();
            return pendingFetch.future;
          }),
        ],
      );
      addTearDown(container.dispose);

      container.read(credentialsProvider.notifier).set('student_b', 'password');
      container.read(_probeProvider);
      await fetchStarted.future;

      final state = container.read(_probeProvider);
      expect(state.hasData, isFalse);
      expect(state.data, isEmpty);

      pendingFetch.complete('student_b_fresh_data');
      await _flushAsyncWork();
      expect(container.read(_probeProvider).data, 'student_b_fresh_data');
    });

    test('drops a stale response after switching accounts', () async {
      final aStarted = Completer<void>();
      final bStarted = Completer<void>();
      final aFetch = Completer<String>();
      final bFetch = Completer<String>();
      final container = ProviderContainer(
        overrides: [
          _probeFetchProvider.overrideWithValue((username) {
            if (username == 'student_a') {
              aStarted.complete();
              return aFetch.future;
            }
            bStarted.complete();
            return bFetch.future;
          }),
        ],
      );
      addTearDown(container.dispose);

      container.read(credentialsProvider.notifier).set('student_a', 'password');
      container.read(_probeProvider);
      await aStarted.future;

      container.read(credentialsProvider.notifier).set('student_b', 'password');
      await bStarted.future;
      bFetch.complete('student_b_fresh_data');
      await _flushAsyncWork();

      aFetch.complete('student_a_stale_data');
      await _flushAsyncWork();

      final state = container.read(_probeProvider);
      expect(state.hasData, isTrue);
      expect(state.data, 'student_b_fresh_data');
    });
  });
}

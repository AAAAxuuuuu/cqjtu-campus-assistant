import 'package:campus_app/features/shared/cached_resource.dart';
import 'package:flutter_test/flutter_test.dart';

/// Regression guard for `CachedResource.when()` branch selection.
///
/// The original guard was `if (hasData || !shouldOfferManualRefresh ||
/// skipError) return data(...)`. Because `shouldOfferManualRefresh` is
/// `consecutiveFailures >= 3`, a cold start (0 failures) always took the
/// `data` branch with an *empty* payload — so `loading` was dead code and
/// pages rendered "暂无数据" while the first request was still in flight,
/// then jumped when it landed. The same guard also swallowed the first two
/// failures, hiding the retry affordance until the third one.
void main() {
  String branch(CachedResource<String> resource, {bool skipError = false}) =>
      resource.when(
        data: (value) => 'data:$value',
        loading: () => 'loading',
        error: (_, _) => 'error',
        skipError: skipError,
      );

  group('CachedResource.when branch selection', () {
    test('cold start with an in-flight fetch resolves to loading', () {
      const resource = CachedResource<String>(data: '', isRefreshing: true);

      expect(resource.isLoading, isTrue);
      expect(branch(resource), 'loading');
    });

    test('first failure without data resolves to error', () {
      final resource = CachedResource<String>(
        data: '',
        error: Exception('CAS unreachable'),
        consecutiveFailures: 1,
      );

      expect(resource.shouldOfferManualRefresh, isFalse);
      expect(branch(resource), 'error');
    });

    test('error branch does not wait for the third consecutive failure', () {
      for (final failures in [1, 2, 3]) {
        final resource = CachedResource<String>(
          data: '',
          error: Exception('boom'),
          consecutiveFailures: failures,
        );
        expect(
          branch(resource),
          'error',
          reason: 'failure #$failures should already surface the error',
        );
      }
    });

    test('cached data outranks a failed background refresh', () {
      final resource = CachedResource<String>(
        data: 'cached',
        hasData: true,
        error: Exception('refresh failed'),
        consecutiveFailures: 5,
      );

      expect(branch(resource), 'data:cached');
    });

    test('cached data outranks an in-flight background refresh', () {
      const resource = CachedResource<String>(
        data: 'cached',
        hasData: true,
        isRefreshing: true,
      );

      expect(branch(resource), 'data:cached');
    });

    test('skipError suppresses only the cold-failure error branch', () {
      final resource = CachedResource<String>(
        data: '',
        error: Exception('boom'),
        consecutiveFailures: 1,
      );

      expect(branch(resource, skipError: true), 'data:');
    });

    test('skipError does not suppress loading', () {
      const resource = CachedResource<String>(data: '', isRefreshing: true);

      expect(branch(resource, skipError: true), 'loading');
    });

    test('idle and empty resolves to the empty data payload', () {
      const resource = CachedResource<String>(data: '');

      expect(branch(resource), 'data:');
    });
  });
}

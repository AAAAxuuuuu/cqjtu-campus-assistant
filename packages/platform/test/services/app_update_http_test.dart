import 'dart:convert';
import 'dart:io';

import 'package:campus_platform/services/app_update_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _RealHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      super.createHttpClient(context);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppUpdateService.debugFeedUrlOverride = null;
  });

  tearDown(() {
    AppUpdateService.debugFeedUrlOverride = null;
  });

  const installed = InstalledAppVersion(version: '1.0.0', buildNumber: 1);

  // The flutter_test binding stubs HttpClient to return 400 for everything;
  // run real HTTP inside a zone that provides a genuine client.
  Future<T> withRealHttp<T>(Future<T> Function() body) {
    return HttpOverrides.runZoned(
      body,
      createHttpClient: _RealHttpOverrides().createHttpClient,
    );
  }

  Future<HttpServer> startServer(
    Future<void> Function(HttpRequest request) handler,
  ) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen(handler);
    return server;
  }

  Map<String, dynamic> releaseJson({
    String version = '2.0.0',
    int buildNumber = 2,
  }) =>
      {'version': version, 'buildNumber': buildNumber};

  group('AppUpdateService HTTP', () {
    test('fetches a newer release over HTTP', () async {
      final server = await startServer((request) async {
        request.response
          ..statusCode = 200
          ..write(jsonEncode(releaseJson()));
        await request.response.close();
      });
      addTearDown(() => server.close(force: true));
      AppUpdateService.debugFeedUrlOverride =
          'http://127.0.0.1:${server.port}/feed';

      final result = await withRealHttp(
        () => AppUpdateService.checkForUpdate(current: installed),
      );

      expect(result.status, AppUpdateCheckStatus.updateAvailable);
      expect(result.latest!.version, '2.0.0');
      expect(result.latest!.buildNumber, 2);
    });

    test('a fresh cache skips the network entirely', () async {
      var requests = 0;
      final server = await startServer((request) async {
        requests++;
        request.response.statusCode = 500;
        await request.response.close();
      });
      addTearDown(() => server.close(force: true));
      AppUpdateService.debugFeedUrlOverride =
          'http://127.0.0.1:${server.port}/feed';

      // Seed a fresh cache with the next version.
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'app_update_feed_cache_v1',
        jsonEncode({
          'data': releaseJson(),
          'etag': 'etag-fresh',
          'checkedAtMs': DateTime.now().millisecondsSinceEpoch,
        }),
      );

      final result = await AppUpdateService.checkForUpdate(current: installed);

      expect(requests, 0, reason: 'fresh cache must not hit the network');
      expect(result.status, AppUpdateCheckStatus.updateAvailable);
      expect(result.latest!.version, '2.0.0');
    });

    test('honors HTTP 304 by reusing the cached feed', () async {
      String? receivedIfNoneMatch;
      var requests = 0;
      final server = await startServer((request) async {
        requests++;
        receivedIfNoneMatch = request.headers.value('if-none-match');
        if (requests == 1) {
          request.response
            ..statusCode = 200
            ..headers.set('etag', 'etag-1')
            ..write(jsonEncode(releaseJson()));
        } else {
          // Unconditional 304 on revalidation.
          request.response.statusCode = 304;
        }
        await request.response.close();
      });
      addTearDown(() => server.close(force: true));
      AppUpdateService.debugFeedUrlOverride =
          'http://127.0.0.1:${server.port}/feed';

      // First request fills the cache.
      await withRealHttp(
        () => AppUpdateService.checkForUpdate(current: installed),
      );

      // Expire the cache so the second check hits the network again.
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('app_update_feed_cache_v1')!;
      final cached = jsonDecode(raw) as Map<String, dynamic>;
      cached['checkedAtMs'] = DateTime.now()
          .subtract(const Duration(hours: 7))
          .millisecondsSinceEpoch;
      await prefs.setString('app_update_feed_cache_v1', jsonEncode(cached));

      final result = await withRealHttp(
        () => AppUpdateService.checkForUpdate(current: installed),
      );

      expect(requests, 2);
      // If-None-Match is only sent to api.github.com in production; a custom
      // feed host must not leak the header contract.
      expect(receivedIfNoneMatch, isNull);
      expect(result.status, AppUpdateCheckStatus.updateAvailable);
      expect(result.latest!.version, '2.0.0');
    });

    test('falls back to the cached feed when the server errors', () async {
      var requests = 0;
      final server = await startServer((request) async {
        requests++;
        if (requests == 1) {
          request.response
            ..statusCode = 200
            ..headers.set('etag', 'etag-1')
            ..write(jsonEncode(releaseJson()));
        } else {
          request.response.statusCode = 500;
        }
        await request.response.close();
      });
      addTearDown(() => server.close(force: true));
      AppUpdateService.debugFeedUrlOverride =
          'http://127.0.0.1:${server.port}/feed';

      await withRealHttp(
        () => AppUpdateService.checkForUpdate(current: installed),
      );

      // Expire the cache; the next request errors.
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('app_update_feed_cache_v1')!;
      final cached = jsonDecode(raw) as Map<String, dynamic>;
      cached['checkedAtMs'] = DateTime.now()
          .subtract(const Duration(hours: 7))
          .millisecondsSinceEpoch;
      await prefs.setString('app_update_feed_cache_v1', jsonEncode(cached));

      final result = await withRealHttp(
        () => AppUpdateService.checkForUpdate(current: installed),
      );

      expect(requests, 2);
      expect(
        result.status,
        AppUpdateCheckStatus.updateAvailable,
        reason: 'stale-but-usable cache wins over the network error',
      );
      expect(result.latest!.version, '2.0.0');
    });
  });
}

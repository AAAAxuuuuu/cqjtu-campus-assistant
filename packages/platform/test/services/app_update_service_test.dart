import 'package:campus_platform/services/app_update_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  AppUpdateInfo infoFrom(
    Map<String, dynamic> json, {
    String defaultReleasePageUrl = 'https://example.com/releases',
  }) =>
      AppUpdateInfo.fromJson(json,
          defaultReleasePageUrl: defaultReleasePageUrl);

  InstalledAppVersion installed(String version, [int buildNumber = 0]) =>
      InstalledAppVersion(version: version, buildNumber: buildNumber);

  group('AppUpdateInfo.fromJson', () {
    test('parses version and build number from common fields', () {
      final info = infoFrom({'version': '1.2.3', 'buildNumber': 42});
      expect(info.version, '1.2.3');
      expect(info.buildNumber, 42);
      expect(info.label, '1.2.3+42');
    });

    test('falls back to latestVersion/tag_name/name', () {
      expect(infoFrom({'latestVersion': '2.0.0'}).version, '2.0.0');
      expect(infoFrom({'tag_name': 'v2.1.0'}).version, '2.1.0');
      expect(infoFrom({'name': '3.0.0'}).version, '3.0.0');
    });

    test('extracts build number from version string when absent', () {
      expect(infoFrom({'version': '1.0.0+17'}).buildNumber, 17);
    });

    test('extracts build number from apk asset name', () {
      final info = infoFrom({
        'assets': [
          {
            'name': 'campus-app-1.2.0+21.apk',
            'content_type': 'application/octet-stream',
          },
        ],
      });
      expect(info.buildNumber, 21);
    });

    test('picks the android apk asset for download', () {
      final info = infoFrom({
        'version': '1.2.0',
        'assets': [
          {'name': 'note.txt'},
          {
            'name': 'campus-app-1.2.0.apk',
            'content_type': 'application/vnd.android.package-archive',
            'browser_download_url': 'https://example.com/campus-app-1.2.0.apk',
          },
        ],
      });
      expect(info.androidDownloadUrl, isNotNull);
    });

    test('throws FormatException when version is missing', () {
      expect(() => infoFrom({'buildNumber': 1}), throwsFormatException);
    });

    test('reads force/mandatory flags', () {
      expect(infoFrom({'version': '1.0.0', 'force': true}).force, isTrue);
      expect(infoFrom({'version': '1.0.0', 'mandatory': true}).force, isTrue);
      expect(infoFrom({'version': '1.0.0'}).force, isFalse);
    });

    test('joins list-based release notes', () {
      final info = infoFrom({
        'version': '1.0.0',
        'notes': ['fix a', 'fix b'],
      });
      expect(info.notes, 'fix a\nfix b');
    });
  });

  group('AppUpdateService.isNewerThanCurrent', () {
    AppUpdateInfo latest(String version, [int buildNumber = 0]) =>
        AppUpdateInfo(
          version: version,
          buildNumber: buildNumber,
          force: false,
          title: 't',
          notes: '',
          releasePageUrl: 'https://example.com',
        );

    test('build number decides when both sides have it', () {
      expect(
        AppUpdateService.isNewerThanCurrent(
            latest('1.0.0', 18), installed('1.0.0', 17)),
        isTrue,
      );
      expect(
        AppUpdateService.isNewerThanCurrent(
            latest('1.0.0', 16), installed('1.0.0', 17)),
        isFalse,
      );
    });

    test('version decides when build numbers are equal or absent', () {
      expect(
        AppUpdateService.isNewerThanCurrent(
            latest('1.0.2', 17), installed('1.0.1', 17)),
        isTrue,
      );
      expect(
        AppUpdateService.isNewerThanCurrent(
            latest('1.0.1'), installed('1.0.2')),
        isFalse,
      );
    });

    test('same version and build is not newer', () {
      expect(
        AppUpdateService.isNewerThanCurrent(
            latest('1.0.0', 17), installed('1.0.0', 17)),
        isFalse,
      );
    });

    test('segment-wise version comparison handles different lengths', () {
      expect(
        AppUpdateService.isNewerThanCurrent(
            latest('1.0.0.1'), installed('1.0.0')),
        isTrue,
      );
      expect(
        AppUpdateService.isNewerThanCurrent(latest('1.0'), installed('1.0.0')),
        isFalse,
      );
    });

    test('normalizes v-prefixed versions', () {
      expect(
        AppUpdateService.isNewerThanCurrent(
            latest('v2.0.0'), installed('1.9.9')),
        isTrue,
      );
    });
  });

  group('InstalledAppVersion', () {
    test('label omits build when zero', () {
      expect(installed('1.0.0').label, '1.0.0');
      expect(installed('1.0.0', 17).label, '1.0.0+17');
    });
  });

  group('AppUpdateCheckResult', () {
    test('hasUpdate reflects status', () {
      const upToDate = AppUpdateCheckResult(
        status: AppUpdateCheckStatus.upToDate,
        current: InstalledAppVersion(version: '1.0.0', buildNumber: 1),
      );
      expect(upToDate.hasUpdate, isFalse);

      const available = AppUpdateCheckResult(
        status: AppUpdateCheckStatus.updateAvailable,
        current: InstalledAppVersion(version: '1.0.0', buildNumber: 1),
        latest: AppUpdateInfo(
          version: '2.0.0',
          buildNumber: 2,
          force: false,
          title: 't',
          notes: '',
          releasePageUrl: 'https://example.com',
        ),
      );
      expect(available.hasUpdate, isTrue);
    });
  });

  group('shouldNotify', () {
    test('notifies only once per version label', () async {
      const latest = AppUpdateInfo(
        version: '1.0.1',
        buildNumber: 18,
        force: false,
        title: 't',
        notes: '',
        releasePageUrl: 'https://example.com',
      );
      expect(await AppUpdateService.shouldNotify(latest), isTrue);
      await AppUpdateService.markNotified(latest);
      expect(await AppUpdateService.shouldNotify(latest), isFalse);
    });
  });
}

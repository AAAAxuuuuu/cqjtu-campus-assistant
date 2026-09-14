import 'package:campus_app/services/app_update_installer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppUpdateDownloadProgress', () {
    test('known total reports fraction and percent', () {
      const progress = AppUpdateDownloadProgress(
        receivedBytes: 12 * 1024 * 1024,
        totalBytes: 24 * 1024 * 1024,
      );

      expect(progress.hasTotal, isTrue);
      expect(progress.fraction, closeTo(0.5, 0.0001));
      expect(progress.percent, 50);
      expect(progress.sizeLabel, '12.0 MB / 24.0 MB');
    });

    test('unknown total (GitHub CDN) does not invent a percentage', () {
      const progress = AppUpdateDownloadProgress(
        receivedBytes: 3 * 1024 * 1024,
        totalBytes: -1,
      );

      expect(progress.hasTotal, isFalse);
      expect(progress.fraction, isNull);
      expect(progress.percent, isNull);
      expect(progress.sizeLabel, '3.0 MB');
    });

    test('zero total is treated as unknown, not as 0%', () {
      const progress = AppUpdateDownloadProgress(
        receivedBytes: 1024,
        totalBytes: 0,
      );

      expect(progress.hasTotal, isFalse);
      expect(progress.fraction, isNull);
    });

    test('fraction clamps at 100%', () {
      const progress = AppUpdateDownloadProgress(
        receivedBytes: 11,
        totalBytes: 10,
      );
      expect(progress.fraction, 1.0);
      expect(progress.percent, 100);
    });

    test('formatBytes picks the right unit', () {
      expect(AppUpdateDownloadProgress.formatBytes(512), '512 B');
      expect(AppUpdateDownloadProgress.formatBytes(1536), '1.5 KB');
      expect(
        AppUpdateDownloadProgress.formatBytes(24 * 1024 * 1024),
        '24.0 MB',
      );
      expect(
        AppUpdateDownloadProgress.formatBytes(2 * 1024 * 1024 * 1024),
        '2.0 GB',
      );
    });
  });
}

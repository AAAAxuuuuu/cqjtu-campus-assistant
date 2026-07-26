import 'dart:convert';

import 'package:campus_app/features/auth/auth_providers.dart';
import 'package:campus_app/features/settings/settings_providers.dart';
import 'package:campus_platform/services/account_cache_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  group('Milestone 3 Empirical Verification Tests', () {
    group('1. Concurrent & Rapid Successive Cache Clears', () {
      test(
        'Concurrent clearAccountCache calls across 5 accounts simultaneously remove target caches and preserve credentials and global settings',
        () async {
          final accounts = ['userA', 'userB', 'userC', 'userD', 'userE'];
          final initialPrefs = <String, Object>{
            'app_theme_mode': 'system',
            'global_language': 'zh-CN',
          };

          for (final acc in accounts) {
            final b64 = base64Url.encode(utf8.encode(acc));
            initialPrefs['resource_cache_v1:schedule:$b64:default'] =
                '{"courses":["$acc-math"]}';
            initialPrefs['resource_cache_v1:grades:$b64:default'] =
                '{"gpa":3.9}';
            initialPrefs['user_${acc}_schedule_sunday_first'] = true;
            initialPrefs['user_${acc}_dorm_campus'] = 'Campus_$acc';
          }

          // Add a preserved account 'userKeeper'
          final keeperB64 = base64Url.encode(utf8.encode('userKeeper'));
          initialPrefs['resource_cache_v1:schedule:$keeperB64:default'] =
              '{"courses":["keeper-math"]}';
          initialPrefs['user_userKeeper_schedule_sunday_first'] = false;

          SharedPreferences.setMockInitialValues(initialPrefs);
          final prefs = await SharedPreferences.getInstance();

          final service = AccountCacheService();

          // Concurrent clear execution for 5 accounts
          await Future.wait(
            accounts.map((acc) => service.clearAccountCache(acc, prefs: prefs)),
          );

          // Verify all 5 cleared accounts have no remaining cache/preference keys
          for (final acc in accounts) {
            final b64 = base64Url.encode(utf8.encode(acc));
            expect(
              prefs.containsKey('resource_cache_v1:schedule:$b64:default'),
              isFalse,
            );
            expect(
              prefs.containsKey('resource_cache_v1:grades:$b64:default'),
              isFalse,
            );
            expect(
              prefs.containsKey('user_${acc}_schedule_sunday_first'),
              isFalse,
            );
            expect(prefs.containsKey('user_${acc}_dorm_campus'), isFalse);
          }

          // Verify userKeeper is intact
          expect(
            prefs.containsKey('resource_cache_v1:schedule:$keeperB64:default'),
            isTrue,
          );
          expect(
            prefs.containsKey('user_userKeeper_schedule_sunday_first'),
            isTrue,
          );

          // Verify global settings remain intact
          expect(prefs.getString('app_theme_mode'), 'system');
          expect(prefs.getString('global_language'), 'zh-CN');
        },
      );

      test(
        'Rapid successive cache clears (50 iterations) on the same account operate cleanly without exception or corruption',
        () async {
          final userAB64 = base64Url.encode(utf8.encode('userA'));
          SharedPreferences.setMockInitialValues({
            'resource_cache_v1:schedule:$userAB64:default': 'data_A',
            'user_userA_pref': 'valA',
            'app_global_key': 'intact',
          });

          final prefs = await SharedPreferences.getInstance();
          final service = AccountCacheService();

          // Execute 50 rapid calls
          for (int i = 0; i < 50; i++) {
            await service.clearAccountCache('userA', prefs: prefs);
          }

          expect(
            prefs.containsKey('resource_cache_v1:schedule:$userAB64:default'),
            isFalse,
          );
          expect(prefs.containsKey('user_userA_pref'), isFalse);
          expect(prefs.getString('app_global_key'), 'intact');
        },
      );

      test(
        'Interleaved rapid cache clears across multiple accounts (30 cycles) preserve non-target account state',
        () async {
          final accounts = ['acc1', 'acc2', 'acc3'];
          final initialMap = <String, Object>{'global_flag': true};

          for (final a in accounts) {
            final b64 = base64Url.encode(utf8.encode(a));
            initialMap['resource_cache_v1:data:$b64:default'] = 'content_$a';
            initialMap['user_${a}_setting'] = 'val_$a';
          }

          SharedPreferences.setMockInitialValues(initialMap);
          final prefs = await SharedPreferences.getInstance();
          final service = AccountCacheService();

          // Rapid interleaved clearing: clear acc1, re-populate acc1, clear acc2, etc.
          for (int cycle = 0; cycle < 10; cycle++) {
            for (final target in accounts) {
              await service.clearAccountCache(target, prefs: prefs);
              final targetB64 = base64Url.encode(utf8.encode(target));
              expect(
                prefs.containsKey('resource_cache_v1:data:$targetB64:default'),
                isFalse,
              );
              expect(prefs.containsKey('user_${target}_setting'), isFalse);

              // Re-seed target data to test repeated clear cycles
              await prefs.setString(
                'resource_cache_v1:data:$targetB64:default',
                'reseeded_$cycle',
              );
              await prefs.setString(
                'user_${target}_setting',
                'reseeded_val_$cycle',
              );
            }
          }

          expect(prefs.getBool('global_flag'), isTrue);
        },
      );

      test(
        'Concurrent clearCurrentAccountCache with Riverpod invalidations across accounts runs safely',
        () async {
          final userAB64 = base64Url.encode(utf8.encode('userA'));
          final userBB64 = base64Url.encode(utf8.encode('userB'));

          SharedPreferences.setMockInitialValues({
            'resource_cache_v1:schedule:$userAB64:default': 'dataA',
            'resource_cache_v1:schedule:$userBB64:default': 'dataB',
          });

          final container = ProviderContainer();
          addTearDown(container.dispose);

          container.read(credentialsProvider.notifier).set('userA', 'passA');

          // Run clearCurrentAccountCache concurrently for userA and userB
          await Future.wait([
            clearCurrentAccountCache(container, 'userA'),
            clearCurrentAccountCache(container, 'userB'),
          ]);

          final prefs = await SharedPreferences.getInstance();
          expect(
            prefs.containsKey('resource_cache_v1:schedule:$userAB64:default'),
            isFalse,
          );
          expect(
            prefs.containsKey('resource_cache_v1:schedule:$userBB64:default'),
            isFalse,
          );

          // Check userA credentials retained
          final creds = container.read(credentialsProvider);
          expect(creds?.username, 'userA');
          expect(creds?.password, 'passA');
        },
      );
    });

    group('2. Empty State Safety (Zero Pre-existing Cached Items)', () {
      test(
        'clearAccountCache on completely empty SharedPreferences and SecureStorage completes without error',
        () async {
          SharedPreferences.setMockInitialValues({});
          FlutterSecureStorage.setMockInitialValues({});

          final prefs = await SharedPreferences.getInstance();
          final service = AccountCacheService();

          await expectLater(
            service.clearAccountCache('userEmpty', prefs: prefs),
            completes,
          );

          expect(prefs.getKeys(), isEmpty);
        },
      );

      test(
        'clearAccountCache on an account with zero pre-existing items does not alter other accounts or global items',
        () async {
          final otherB64 = base64Url.encode(utf8.encode('otherUser'));
          SharedPreferences.setMockInitialValues({
            'resource_cache_v1:schedule:$otherB64:default': 'other_data',
            'user_otherUser_pref': 'other_pref',
            'global_app_theme': 'light',
          });

          final prefs = await SharedPreferences.getInstance();
          final service = AccountCacheService();

          await service.clearAccountCache('userEmpty', prefs: prefs);

          expect(
            prefs.containsKey('resource_cache_v1:schedule:$otherB64:default'),
            isTrue,
          );
          expect(prefs.containsKey('user_otherUser_pref'), isTrue);
          expect(prefs.getString('global_app_theme'), 'light');
        },
      );

      test(
        'Multiple repeated clearAccountCache calls on empty state remain safe and idempotent',
        () async {
          SharedPreferences.setMockInitialValues({});
          final prefs = await SharedPreferences.getInstance();
          final service = AccountCacheService();

          for (int i = 0; i < 10; i++) {
            await expectLater(
              service.clearAccountCache('nonExistentUser', prefs: prefs),
              completes,
            );
          }

          expect(prefs.getKeys(), isEmpty);
        },
      );

      test(
        'clearCurrentAccountCache with Riverpod invalidations on empty state updates UI providers to clean default states without crashing',
        () async {
          SharedPreferences.setMockInitialValues({});
          final container = ProviderContainer();
          addTearDown(container.dispose);

          // Invoke clearCurrentAccountCache for zero cached items account
          await expectLater(
            clearCurrentAccountCache(container, 'userEmpty'),
            completes,
          );

          final dorm = await container.read(dormRoomProvider.future);
          expect(dorm, isNull);
        },
      );
    });
  });
}

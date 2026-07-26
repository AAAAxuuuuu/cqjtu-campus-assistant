import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'session_service.dart';

final accountCacheServiceProvider = Provider<AccountCacheService>((ref) {
  return AccountCacheService(
    sessionService: ref.watch(sessionServiceProvider),
  );
});

class AccountCacheService {
  final SessionService _sessionService;

  AccountCacheService({SessionService? sessionService})
      : _sessionService = sessionService ?? SessionService();

  /// Clears persistent SharedPreferences keys and session tokens/cookies for [username].
  ///
  /// Leaves secure login credentials in [CredentialService] untouched so the user stays logged in.
  Future<void> clearAccountCache(
    String username, {
    String? accountId,
    SharedPreferences? prefs,
  }) async {
    final trimmedUsername = username.trim();
    if (trimmedUsername.isEmpty) return;

    final sp = prefs ?? await SharedPreferences.getInstance();
    final effectiveAccountId = (accountId != null && accountId.trim().isNotEmpty)
        ? accountId.trim()
        : trimmedUsername;

    final usernameB64Url = base64Url.encode(utf8.encode(trimmedUsername));
    final usernameB64Std = base64.encode(utf8.encode(trimmedUsername));

    final knownAccounts = _extractKnownAccounts(
      sp: sp,
      username: trimmedUsername,
      accountId: effectiveAccountId,
    );

    final keysToRemove = <String>[];
    for (final key in sp.getKeys()) {
      if (_shouldDeleteKey(
        key,
        usernameB64Url: usernameB64Url,
        usernameB64Std: usernameB64Std,
        accountId: effectiveAccountId,
        username: trimmedUsername,
        knownAccounts: knownAccounts,
      )) {
        keysToRemove.add(key);
      }
    }

    for (final key in keysToRemove) {
      await sp.remove(key);
    }

    await _sessionService.clearForUsername(trimmedUsername);
  }

  /// Alias for [clearAccountCache] to support [clearCurrentAccountCache] interface.
  Future<void> clearCurrentAccountCache(
    String username, {
    String? accountId,
    SharedPreferences? prefs,
  }) => clearAccountCache(username, accountId: accountId, prefs: prefs);

  /// Clears account cache and invalidates specified Riverpod providers.
  Future<void> clearAndInvalidate({
    required void Function(dynamic provider) invalidator,
    required String username,
    String? accountId,
    List<dynamic>? providers,
    SharedPreferences? prefs,
  }) async {
    await clearAccountCache(username, accountId: accountId, prefs: prefs);
    if (providers != null) {
      for (final provider in providers) {
        invalidator(provider);
      }
    }
  }

  static const List<String> _knownSettingPrefixes = [
    '_schedule_',
    '_dorm_',
    '_semester_start_',
    '_pref',
    '_setting',
    '_test',
  ];

  Set<String> _extractKnownAccounts({
    required SharedPreferences sp,
    required String username,
    required String accountId,
  }) {
    final set = <String>{
      if (username.isNotEmpty) username,
      if (accountId.isNotEmpty) accountId,
    };

    for (final k in sp.getKeys()) {
      if (k.startsWith('resource_cache_v1:')) {
        final parts = k.split(':');
        if (parts.length >= 3) {
          final accountPart = parts[2];
          set.add(accountPart);
          try {
            final decoded = utf8.decode(base64Url.decode(accountPart));
            if (decoded.isNotEmpty) set.add(decoded);
          } catch (_) {}
          try {
            final decoded = utf8.decode(base64.decode(accountPart));
            if (decoded.isNotEmpty) set.add(decoded);
          } catch (_) {}
        }
      } else if (k.startsWith('user_')) {
        final rest = k.substring(5);
        if (rest.isNotEmpty) {
          bool matchedSettingPrefix = false;
          for (final settingPrefix in _knownSettingPrefixes) {
            final idx = rest.indexOf(settingPrefix);
            if (idx > 0) {
              final parsedAccount = rest.substring(0, idx);
              if (parsedAccount.isNotEmpty) {
                set.add(parsedAccount);
                matchedSettingPrefix = true;
                break;
              }
            }
          }

          if (!matchedSettingPrefix) {
            set.add(rest);
            if (rest.contains('_')) {
              final lastUnderscore = rest.lastIndexOf('_');
              if (lastUnderscore > 0) {
                final candidate1 = rest.substring(0, lastUnderscore);
                if (candidate1.isNotEmpty) set.add(candidate1);
              }
              final firstUnderscore = rest.indexOf('_');
              if (firstUnderscore > 0) {
                final candidate2 = rest.substring(0, firstUnderscore);
                if (candidate2.isNotEmpty) set.add(candidate2);
              }
            }
          }
        }
      }
    }
    return set;
  }

  bool _shouldDeleteKey(
    String key, {
    required String usernameB64Url,
    required String usernameB64Std,
    required String accountId,
    required String username,
    required Set<String> knownAccounts,
  }) {
    // 1. Resource cache keys
    if (key.startsWith('resource_cache_v1:')) {
      final parts = key.split(':');
      if (parts.length >= 3) {
        final accountPart = parts[2];
        if (accountPart == usernameB64Url ||
            accountPart == usernameB64Std ||
            accountPart == username ||
            accountPart == accountId ||
            accountPart == 'default') {
          return true;
        }
      }
    }

    // 2. Exact account key matches
    if (key == 'user_$accountId' || key == 'user_$username') {
      return true;
    }

    // 3. User-scoped preference keys (e.g. user_userA_... or user_userA)
    final targetAccs = {
      if (accountId.isNotEmpty) accountId,
      if (username.isNotEmpty) username,
    };

    for (final acc in targetAccs) {
      final prefix = 'user_${acc}_';
      if (key.startsWith(prefix)) {
        bool matchesLongerAccount = false;
        for (final otherAcc in knownAccounts) {
          if (otherAcc != acc && otherAcc.startsWith('${acc}_')) {
            if (key.startsWith('user_${otherAcc}_') || key == 'user_$otherAcc') {
              matchesLongerAccount = true;
              break;
            }
          }
        }
        if (!matchesLongerAccount) {
          return true;
        }
      }
    }

    // 4. Encoded or delimited substring matches
    if (key.contains(':$usernameB64Url:') ||
        key.contains(':$usernameB64Std:') ||
        (username.isNotEmpty && key.contains(':$username:')) ||
        (accountId.isNotEmpty && key.contains(':$accountId:'))) {
      return true;
    }

    // 5. Fallback / legacy account preference keys
    if (key.startsWith('schedule_custom_courses_') ||
        key.startsWith('schedule_total_weeks_') ||
        key.startsWith('dorm_') ||
        key.startsWith('semester_start_') ||
        key == 'selected_semester_str' ||
        key == 'schedule_sunday_first' ||
        key == 'schedule_show_inactive_courses') {
      return true;
    }

    return false;
  }
}

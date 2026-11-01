import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:data/data.dart';

final sessionServiceProvider = Provider<SessionService>(
  (ref) => SessionService(),
);

class SessionService implements SelfHostedSessionStore {
  static const int maxAutoLoginAttemptsPerHour = 6;
  static const Duration minAutoLoginInterval = Duration(minutes: 5);
  static const int maxManualLoginAttemptsPerHour = 5;
  static const int maxSportsLoginAttemptsPerHour = 5;
  static const int maxSecurityFailuresBeforeCooldown = 3;
  static const Duration securityCooldownDuration = Duration(minutes: 30);
  static const Duration securityFailureTtl = Duration(hours: 1);

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static const _sessionPrefix = 'session_id_';
  static const _ticketPrefix = 'login_ticket_';
  static const _ticketUpdatedAtPrefix = 'login_ticket_updated_at_';
  static const _casCookiesPrefix = 'cas_cookies_';
  static const _casCookiesUpdatedAtPrefix = 'cas_cookies_updated_at_';
  static const _jwgCookiesPrefix = 'jwg_cookies_';
  static const _jwgCookiesUpdatedAtPrefix = 'jwg_cookies_updated_at_';
  static const _ecardCookiesPrefix = 'ecard_cookies_';
  static const _ecardCookiesUpdatedAtPrefix = 'ecard_cookies_updated_at_';
  static const _zoveTokenPrefix = 'zove_token_';
  static const _zoveTokenUpdatedAtPrefix = 'zove_token_updated_at_';
  static const _autoLoginAttemptsPrefix = 'auto_login_attempts_';
  static const _authCircuitBrokenPrefix = 'auth_circuit_broken_';
  static const _manualLoginAttemptsPrefix = 'manual_login_attempts_';
  static const _securityFailureStatePrefix = 'security_failure_state_';
  static const _sportsLoginAttemptsPrefix = 'sports_login_attempts_';

  Future<String?> loadSessionId(String username) =>
      _storage.read(key: _sessionKey(username));

  Future<void> saveSessionId(String username, String sessionId) =>
      _storage.write(key: _sessionKey(username), value: sessionId);

  Future<String?> loadTicket(String username) =>
      _storage.read(key: _ticketKey(username));

  Future<void> saveTicket(String username, String ticket) =>
      _writeWithTimestamp(
        key: _ticketKey(username),
        updatedAtKey: _ticketUpdatedAtKey(username),
        value: ticket,
      );

  Future<void> clearTicket(String username) async {
    await _storage.delete(key: _ticketKey(username));
    await _storage.delete(key: _ticketUpdatedAtKey(username));
  }

  Future<int?> loadTicketUpdatedAt(String username) =>
      _readTimestamp(_ticketUpdatedAtKey(username));

  Future<String?> loadCasCookies(String username) =>
      _storage.read(key: _casCookiesKey(username));

  Future<void> saveCasCookies(String username, String cookies) =>
      _writeWithTimestamp(
        key: _casCookiesKey(username),
        updatedAtKey: _casCookiesUpdatedAtKey(username),
        value: cookies,
      );

  Future<int?> loadCasCookiesUpdatedAt(String username) =>
      _readTimestamp(_casCookiesUpdatedAtKey(username));

  Future<String?> loadJwgCookies(String username) =>
      _storage.read(key: _jwgCookiesKey(username));

  Future<void> saveJwgCookies(String username, String cookies) =>
      _writeWithTimestamp(
        key: _jwgCookiesKey(username),
        updatedAtKey: _jwgCookiesUpdatedAtKey(username),
        value: cookies,
      );

  Future<int?> loadJwgCookiesUpdatedAt(String username) =>
      _readTimestamp(_jwgCookiesUpdatedAtKey(username));

  Future<String?> loadEcardCookies(String username) =>
      _storage.read(key: _ecardCookiesKey(username));

  Future<void> saveEcardCookies(String username, String cookies) =>
      _writeWithTimestamp(
        key: _ecardCookiesKey(username),
        updatedAtKey: _ecardCookiesUpdatedAtKey(username),
        value: cookies,
      );

  Future<int?> loadEcardCookiesUpdatedAt(String username) =>
      _readTimestamp(_ecardCookiesUpdatedAtKey(username));

  Future<String?> loadZoveToken(String username) =>
      _storage.read(key: _zoveTokenKey(username));

  Future<void> saveZoveToken(String username, String token) async {
    await _writeWithTimestamp(
      key: _zoveTokenKey(username),
      updatedAtKey: _zoveTokenUpdatedAtKey(username),
      value: token,
    );
  }

  Future<int?> loadZoveTokenUpdatedAt(String username) =>
      _readTimestamp(_zoveTokenUpdatedAtKey(username));

  Future<void> saveWebLoginArtifacts(
    String username, {
    String? ticket,
    String? casCookies,
    String? jwgCookies,
    String? ecardCookies,
    String? zoveToken,
  }) async {
    if (ticket != null && ticket.isNotEmpty) {
      await saveTicket(username, ticket);
    }
    if (casCookies != null && casCookies.isNotEmpty) {
      await saveCasCookies(username, casCookies);
    }
    if (jwgCookies != null && jwgCookies.isNotEmpty) {
      await saveJwgCookies(username, jwgCookies);
    }
    if (ecardCookies != null && ecardCookies.isNotEmpty) {
      await saveEcardCookies(username, ecardCookies);
    }
    if (zoveToken != null && zoveToken.isNotEmpty) {
      await saveZoveToken(username, zoveToken);
    }
  }

  String _authCircuitBrokenKey(String username) =>
      '$_authCircuitBrokenPrefix$username';

  @override
  Future<bool> isAuthCircuitBroken(String username) async {
    final value = await _storage.read(key: _authCircuitBrokenKey(username));
    return value == 'true';
  }

  @override
  Future<void> markAuthCircuitBroken(String username) async {
    await _storage.write(key: _authCircuitBrokenKey(username), value: 'true');
  }

  @override
  Future<void> resetAuthCircuitBreaker(String username) async {
    await _storage.delete(key: _authCircuitBrokenKey(username));
  }

  @override
  Future<void> clearLoginArtifacts(String username) async {
    await _storage.delete(key: _sessionKey(username));
    await _storage.delete(key: _ticketKey(username));
    await _storage.delete(key: _ticketUpdatedAtKey(username));
    await _storage.delete(key: _casCookiesKey(username));
    await _storage.delete(key: _casCookiesUpdatedAtKey(username));
    await _storage.delete(key: _jwgCookiesKey(username));
    await _storage.delete(key: _jwgCookiesUpdatedAtKey(username));
    await _storage.delete(key: _ecardCookiesKey(username));
    await _storage.delete(key: _ecardCookiesUpdatedAtKey(username));
    await _storage.delete(key: _zoveTokenKey(username));
    await _storage.delete(key: _zoveTokenUpdatedAtKey(username));
    await _storage.delete(key: _autoLoginAttemptsKey(username));
    await _storage.delete(key: _authCircuitBrokenKey(username));
    await _storage.delete(key: _manualLoginAttemptsKey(username));
    await _storage.delete(key: _securityFailureStateKey(username));
    await _storage.delete(key: _sportsLoginAttemptsKey(username));
  }

  Future<List<int>> loadAutoLoginAttempts(String username) async {
    final raw = await _storage.read(key: _autoLoginAttemptsKey(username));
    if (raw == null || raw.isEmpty) return const [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list.map((e) => (e as num).toInt()).toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> saveAutoLoginAttempts(
    String username,
    List<int> timestamps,
  ) async {
    await _storage.write(
      key: _autoLoginAttemptsKey(username),
      value: jsonEncode(timestamps),
    );
  }

  /// Prunes attempts older than 1 hour, guards against race conditions with minInterval,
  /// records the current attempt, and persists.
  @override
  Future<void> recordAutoLoginAttempt(
    String username, {
    DateTime? now,
    Duration minInterval = minAutoLoginInterval,
  }) async {
    final current = now ?? DateTime.now();
    final cutoff =
        current.subtract(const Duration(hours: 1)).millisecondsSinceEpoch;
    final attempts = (await loadAutoLoginAttempts(username))
        .where((ts) => ts > cutoff)
        .toList();
    attempts.sort();
    if (attempts.isNotEmpty) {
      final lastAttempt = attempts.last;
      final diffMs = current.millisecondsSinceEpoch - lastAttempt;
      if (diffMs >= 0 && diffMs < minInterval.inMilliseconds) {
        return;
      }
    }
    attempts.add(current.millisecondsSinceEpoch);
    await saveAutoLoginAttempts(username, attempts);
  }

  /// Checks if the account can perform auto-login (< [maxAttemptsPerHour] in the last 1 hour
  /// and at least [minInterval] since the previous attempt).
  @override
  Future<bool> canAttemptAutoLogin(
    String username, {
    DateTime? now,
    int maxAttemptsPerHour = maxAutoLoginAttemptsPerHour,
    Duration minInterval = minAutoLoginInterval,
  }) async {
    if (await isAuthCircuitBroken(username)) {
      return false;
    }
    final current = now ?? DateTime.now();
    final cutoff =
        current.subtract(const Duration(hours: 1)).millisecondsSinceEpoch;
    final attempts = (await loadAutoLoginAttempts(username))
        .where((ts) => ts > cutoff)
        .toList();
    attempts.sort();
    if (attempts.isNotEmpty) {
      final lastAttempt = attempts.last;
      final diffMs = current.millisecondsSinceEpoch - lastAttempt;
      if (diffMs >= 0 && diffMs < minInterval.inMilliseconds) {
        return false;
      }
    }
    return attempts.length < maxAttemptsPerHour;
  }

  @override
  Future<bool> isAutoLoginHourlyLimitReached(
    String username, {
    DateTime? now,
    int maxAttemptsPerHour = maxAutoLoginAttemptsPerHour,
  }) async {
    final current = now ?? DateTime.now();
    final cutoff =
        current.subtract(const Duration(hours: 1)).millisecondsSinceEpoch;
    final attempts = (await loadAutoLoginAttempts(username))
        .where((ts) => ts > cutoff)
        .toList();
    return attempts.length >= maxAttemptsPerHour;
  }

  /// Returns remaining auto-login attempts for the sliding 1-hour window.
  Future<int> getRemainingAutoLoginAttempts(
    String username, {
    DateTime? now,
    int maxAttemptsPerHour = maxAutoLoginAttemptsPerHour,
  }) async {
    if (await isAuthCircuitBroken(username)) {
      return 0;
    }
    final current = now ?? DateTime.now();
    final cutoff =
        current.subtract(const Duration(hours: 1)).millisecondsSinceEpoch;
    final attempts = (await loadAutoLoginAttempts(username))
        .where((ts) => ts > cutoff)
        .toList();
    final remaining = maxAttemptsPerHour - attempts.length;
    return remaining < 0 ? 0 : remaining;
  }

  /// Clears recorded auto-login attempts (e.g. after successful manual login).
  Future<void> clearAutoLoginAttempts(String username) async {
    await _storage.delete(key: _autoLoginAttemptsKey(username));
  }

  // --- Manual Login Rate Limiting (F2) ---

  Future<List<int>> loadManualLoginAttempts(String username) async {
    final raw = await _storage.read(key: _manualLoginAttemptsKey(username));
    if (raw == null || raw.isEmpty) return const [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list.map((e) => (e as num).toInt()).toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> saveManualLoginAttempts(
    String username,
    List<int> timestamps,
  ) async {
    await _storage.write(
      key: _manualLoginAttemptsKey(username),
      value: jsonEncode(timestamps),
    );
  }

  @override
  Future<bool> canAttemptManualLogin(
    String username, {
    DateTime? now,
    int maxManualAttemptsPerHour = maxManualLoginAttemptsPerHour,
  }) async {
    final current = now ?? DateTime.now();
    final cutoff =
        current.subtract(const Duration(hours: 1)).millisecondsSinceEpoch;
    final attempts = (await loadManualLoginAttempts(username))
        .where((ts) => ts > cutoff)
        .toList();
    return attempts.length < maxManualAttemptsPerHour;
  }

  @override
  Future<void> recordManualLoginAttempt(String username,
      {DateTime? now}) async {
    final current = now ?? DateTime.now();
    final cutoff =
        current.subtract(const Duration(hours: 1)).millisecondsSinceEpoch;
    final attempts = (await loadManualLoginAttempts(username))
        .where((ts) => ts > cutoff)
        .toList();
    attempts.add(current.millisecondsSinceEpoch);
    await saveManualLoginAttempts(username, attempts);
  }

  @override
  Future<void> clearManualLoginAttempts(String username) async {
    await _storage.delete(key: _manualLoginAttemptsKey(username));
  }

  // --- Security Failures & Cooldown (F3) ---

  @override
  Future<bool> isInSecurityCooldown(String username, {DateTime? now}) async {
    final raw = await _storage.read(key: _securityFailureStateKey(username));
    if (raw == null || raw.isEmpty) return false;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final untilMs = (map['untilMs'] as num?)?.toInt() ?? 0;
      final currentMs = (now ?? DateTime.now()).millisecondsSinceEpoch;
      return untilMs > currentMs;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> recordSecurityFailure(String username, {DateTime? now}) async {
    final current = now ?? DateTime.now();
    final currentMs = current.millisecondsSinceEpoch;
    var count = 0;
    var untilMs = 0;
    final raw = await _storage.read(key: _securityFailureStateKey(username));
    if (raw != null && raw.isNotEmpty) {
      try {
        final map = jsonDecode(raw) as Map<String, dynamic>;
        final lastFailureMs = (map['lastFailureMs'] as num?)?.toInt() ?? 0;
        if (currentMs - lastFailureMs <= securityFailureTtl.inMilliseconds) {
          count = (map['count'] as num?)?.toInt() ?? 0;
        }
        untilMs = (map['untilMs'] as num?)?.toInt() ?? 0;
      } catch (_) {}
    }

    count += 1;
    if (count >= maxSecurityFailuresBeforeCooldown) {
      untilMs = currentMs + securityCooldownDuration.inMilliseconds;
      count = 0;
    }

    await _storage.write(
      key: _securityFailureStateKey(username),
      value: jsonEncode({
        'count': count,
        'untilMs': untilMs,
        'lastFailureMs': currentMs,
      }),
    );
  }

  @override
  Future<void> resetSecurityFailures(String username) async {
    await _storage.delete(key: _securityFailureStateKey(username));
  }

  // --- Sports Login Rate Limiting (F4) ---

  Future<List<int>> loadSportsLoginAttempts(String username) async {
    final raw = await _storage.read(key: _sportsLoginAttemptsKey(username));
    if (raw == null || raw.isEmpty) return const [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list.map((e) => (e as num).toInt()).toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> saveSportsLoginAttempts(
    String username,
    List<int> timestamps,
  ) async {
    await _storage.write(
      key: _sportsLoginAttemptsKey(username),
      value: jsonEncode(timestamps),
    );
  }

  Future<bool> canAttemptSportsLogin(
    String username, {
    DateTime? now,
    int maxSportsAttemptsPerHour = maxSportsLoginAttemptsPerHour,
  }) async {
    final current = now ?? DateTime.now();
    final cutoff =
        current.subtract(const Duration(hours: 1)).millisecondsSinceEpoch;
    final attempts = (await loadSportsLoginAttempts(username))
        .where((ts) => ts > cutoff)
        .toList();
    return attempts.length < maxSportsAttemptsPerHour;
  }

  Future<void> recordSportsLoginAttempt(String username,
      {DateTime? now}) async {
    final current = now ?? DateTime.now();
    final cutoff =
        current.subtract(const Duration(hours: 1)).millisecondsSinceEpoch;
    final attempts = (await loadSportsLoginAttempts(username))
        .where((ts) => ts > cutoff)
        .toList();
    attempts.add(current.millisecondsSinceEpoch);
    await saveSportsLoginAttempts(username, attempts);
  }

  Future<void> clearSportsLoginAttempts(String username) async {
    await _storage.delete(key: _sportsLoginAttemptsKey(username));
  }

  Future<void> clearForUsername(String username) =>
      clearLoginArtifacts(username);

  Future<void> _writeWithTimestamp({
    required String key,
    required String updatedAtKey,
    required String value,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch.toString();
    await _storage.write(key: key, value: value);
    await _storage.write(key: updatedAtKey, value: now);
  }

  Future<int?> _readTimestamp(String key) async {
    final raw = await _storage.read(key: key);
    if (raw == null || raw.isEmpty) return null;
    return int.tryParse(raw);
  }

  String sessionKeyFor(String username) => _sessionKey(username);

  String _sessionKey(String username) => '$_sessionPrefix$username';

  String _ticketKey(String username) => '$_ticketPrefix$username';

  String _ticketUpdatedAtKey(String username) =>
      '$_ticketUpdatedAtPrefix$username';

  String _casCookiesKey(String username) => '$_casCookiesPrefix$username';

  String _casCookiesUpdatedAtKey(String username) =>
      '$_casCookiesUpdatedAtPrefix$username';

  String _jwgCookiesKey(String username) => '$_jwgCookiesPrefix$username';

  String _jwgCookiesUpdatedAtKey(String username) =>
      '$_jwgCookiesUpdatedAtPrefix$username';

  String _ecardCookiesKey(String username) => '$_ecardCookiesPrefix$username';

  String _ecardCookiesUpdatedAtKey(String username) =>
      '$_ecardCookiesUpdatedAtPrefix$username';

  String _zoveTokenKey(String username) => '$_zoveTokenPrefix$username';

  String _zoveTokenUpdatedAtKey(String username) =>
      '$_zoveTokenUpdatedAtPrefix$username';

  String _autoLoginAttemptsKey(String username) =>
      '$_autoLoginAttemptsPrefix$username';

  String _manualLoginAttemptsKey(String username) =>
      '$_manualLoginAttemptsPrefix$username';

  String _securityFailureStateKey(String username) =>
      '$_securityFailureStatePrefix$username';

  String _sportsLoginAttemptsKey(String username) =>
      '$_sportsLoginAttemptsPrefix$username';
}

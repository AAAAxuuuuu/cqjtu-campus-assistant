import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

final semesterServiceProvider = Provider<SemesterService>(
  (ref) => SemesterService(),
);

class SemesterService {
  SemesterService({
    SemesterCacheSnapshot? initialCache,
    String? initialAccountId,
  }) {
    if (initialCache != null) {
      _caches[_scope(initialAccountId)] = initialCache;
    }
  }

  static const _key = 'semester_start_date';
  static const _semesterStartForKeyPrefix = 'semester_start_key_';
  static const _selectedSemesterKey = 'selected_semester_str';
  static const _defaultScope = 'default';

  final Map<String, SemesterCacheSnapshot> _caches = {};

  bool get cacheReady => cacheReadyFor(null);

  bool cacheReadyFor(String? accountId) =>
      _caches.containsKey(_scope(accountId));

  static String _scope(String? accountId) {
    final account = accountId?.trim();
    return account == null || account.isEmpty ? _defaultScope : account;
  }

  static String _scopedKey(String key, String? accountId) {
    final scope = _scope(accountId);
    return scope == _defaultScope ? key : 'user_${scope}_$key';
  }

  static String _startPrefix(String? accountId) =>
      _scopedKey(_semesterStartForKeyPrefix, accountId);

  static Future<SemesterCacheSnapshot> restoreSnapshot({
    String? accountId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final snapshot = _readSnapshot(prefs, accountId: accountId);
    final hasAccountId = _scope(accountId) != _defaultScope;
    if (!hasAccountId || snapshot.hasData) return snapshot;

    // Migrate legacy installation-wide semester data to the first signed-in
    // account that needs it, then prevent other accounts from inheriting it.
    final legacy = _readSnapshot(prefs, accountId: null);
    if (!legacy.hasData) return snapshot;
    await _writeSnapshot(prefs, legacy, accountId: accountId);
    await _removeSnapshot(prefs, accountId: null);
    return legacy;
  }

  static SemesterCacheSnapshot _readSnapshot(
    SharedPreferences prefs, {
    required String? accountId,
  }) {
    final startsBySemester = <String, DateTime>{};
    final prefix = _startPrefix(accountId);

    for (final key in prefs.getKeys()) {
      if (!key.startsWith(prefix)) continue;
      final semester = key.substring(prefix.length);
      final date = DateTime.tryParse(prefs.getString(key) ?? '');
      if (semester.isNotEmpty && date != null) {
        startsBySemester[semester] = date;
      }
    }

    return SemesterCacheSnapshot(
      defaultStart: DateTime.tryParse(
        prefs.getString(_scopedKey(_key, accountId)) ?? '',
      ),
      selectedSemester: prefs.getString(
        _scopedKey(_selectedSemesterKey, accountId),
      ),
      startsBySemester: startsBySemester,
    );
  }

  static Future<void> _writeSnapshot(
    SharedPreferences prefs,
    SemesterCacheSnapshot snapshot, {
    required String? accountId,
  }) async {
    if (snapshot.defaultStart != null) {
      await prefs.setString(
        _scopedKey(_key, accountId),
        snapshot.defaultStart!.toIso8601String(),
      );
    }
    if (snapshot.selectedSemester != null) {
      await prefs.setString(
        _scopedKey(_selectedSemesterKey, accountId),
        snapshot.selectedSemester!,
      );
    }
    for (final entry in snapshot.startsBySemester.entries) {
      await prefs.setString(
        '${_startPrefix(accountId)}${entry.key}',
        entry.value.toIso8601String(),
      );
    }
  }

  static Future<void> _removeSnapshot(
    SharedPreferences prefs, {
    required String? accountId,
  }) async {
    await prefs.remove(_scopedKey(_key, accountId));
    await prefs.remove(_scopedKey(_selectedSemesterKey, accountId));
    final prefix = _startPrefix(accountId);
    for (final key in prefs.getKeys().where((key) => key.startsWith(prefix))) {
      await prefs.remove(key);
    }
  }

  Future<SemesterCacheSnapshot> _ensureCache(String? accountId) async {
    final scope = _scope(accountId);
    final cached = _caches[scope];
    if (cached != null) return cached;
    final restored = await restoreSnapshot(accountId: accountId);
    _caches[scope] = restored;
    return restored;
  }

  /// 保存学期开始日期（当前/默认学期）
  Future<void> save(DateTime date, {String? accountId}) async {
    final scope = _scope(accountId);
    final current = await _ensureCache(accountId);
    _caches[scope] = current.copyWith(defaultStart: date);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_scopedKey(_key, accountId), date.toIso8601String());
  }

  /// 读取学期开始日期（当前/默认学期），未设置返回 null
  Future<DateTime?> load({String? accountId}) async {
    return (await _ensureCache(accountId)).defaultStart;
  }

  DateTime? loadSync({String? accountId}) =>
      _caches[_scope(accountId)]?.defaultStart;

  // ── 按学期 key 存取（用于非当前学期）────────────────────────
  // key 格式与成绩/考试的 semester 字符串一致，如 "2024-2025-1"
  // 存储的 SharedPreferences key 为 "semester_start_key_{semesterStr}"

  /// 保存指定学期的开学日期
  Future<void> saveForKey(
    String semesterKey,
    DateTime date, {
    String? accountId,
  }) async {
    final scope = _scope(accountId);
    final current = await _ensureCache(accountId);
    final nextStarts = {...current.startsBySemester, semesterKey: date};
    _caches[scope] = current.copyWith(startsBySemester: nextStarts);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      '${_startPrefix(accountId)}$semesterKey',
      date.toIso8601String(),
    );
  }

  /// 读取指定学期的开学日期，未设置返回 null
  Future<DateTime?> loadForKey(String semesterKey, {String? accountId}) async {
    if (semesterKey.isEmpty) return load(accountId: accountId);
    return (await _ensureCache(accountId)).startsBySemester[semesterKey];
  }

  DateTime? loadForKeySync(String semesterKey, {String? accountId}) {
    if (semesterKey.isEmpty) return loadSync(accountId: accountId);
    return _caches[_scope(accountId)]?.startsBySemester[semesterKey];
  }

  /// 持久化用户选中的学期字符串（如 "2024-2025-1"），null 表示恢复默认
  Future<void> saveSelectedSemester(String? value, {String? accountId}) async {
    final scope = _scope(accountId);
    final current = await _ensureCache(accountId);
    _caches[scope] = current.copyWith(selectedSemester: value);
    final prefs = await SharedPreferences.getInstance();
    if (value == null) {
      await prefs.remove(_scopedKey(_selectedSemesterKey, accountId));
    } else {
      await prefs.setString(_scopedKey(_selectedSemesterKey, accountId), value);
    }
  }

  /// 读取持久化的学期字符串，未设置返回 null
  Future<String?> loadSelectedSemester({String? accountId}) async {
    return (await _ensureCache(accountId)).selectedSemester;
  }

  String? loadSelectedSemesterSync({String? accountId}) =>
      _caches[_scope(accountId)]?.selectedSemester;
}

const Object _unset = Object();

class SemesterCacheSnapshot {
  const SemesterCacheSnapshot({
    this.defaultStart,
    this.selectedSemester,
    this.startsBySemester = const {},
  });

  final DateTime? defaultStart;
  final String? selectedSemester;
  final Map<String, DateTime> startsBySemester;

  bool get hasData =>
      defaultStart != null ||
      selectedSemester != null ||
      startsBySemester.isNotEmpty;

  SemesterCacheSnapshot copyWith({
    Object? defaultStart = _unset,
    Object? selectedSemester = _unset,
    Map<String, DateTime>? startsBySemester,
  }) {
    return SemesterCacheSnapshot(
      defaultStart: identical(defaultStart, _unset)
          ? this.defaultStart
          : defaultStart as DateTime?,
      selectedSemester: identical(selectedSemester, _unset)
          ? this.selectedSemester
          : selectedSemester as String?,
      startsBySemester: startsBySemester ?? this.startsBySemester,
    );
  }
}

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:core/models/dorm_room.dart';

final dormServiceProvider = Provider<DormService>((ref) => DormService());

class DormService {
  static const _keys = DormRoom.preferenceKeys;

  static String _key(String base, String? accountId) {
    final safeAccount = (accountId != null && accountId.trim().isNotEmpty)
        ? accountId.trim()
        : 'guest';
    return 'user_${safeAccount}_$base';
  }

  Future<void> save(DormRoom room, {String? accountId}) async {
    final prefs = await SharedPreferences.getInstance();
    // Remove values belonging to the other campus before persisting the new
    // selection, so stale South-Campus IDs cannot override a science-city room.
    for (final key in _keys) {
      await prefs.remove(_key(key, accountId));
    }
    for (final entry in room.toPrefsMap().entries) {
      await prefs.setString(_key(entry.key, accountId), entry.value);
    }
  }

  Future<DormRoom?> load({String? accountId}) async {
    final prefs = await SharedPreferences.getInstance();
    final hasAccountId = accountId != null && accountId.trim().isNotEmpty;

    final scopedMap = {
      for (final k in _keys) k: prefs.getString(_key(k, accountId))
    };
    final scopedRoom = DormRoom.fromPrefsMap(scopedMap);
    if (scopedRoom != null) {
      return scopedRoom;
    }

    // Migrate an installation-wide legacy selection only once, into the first
    // signed-in account that reads it. Other accounts must not inherit it.
    if (!hasAccountId) {
      final legacyMap = {for (final k in _keys) k: prefs.getString(k)};
      return DormRoom.fromPrefsMap(legacyMap);
    }

    final legacyMap = {for (final k in _keys) k: prefs.getString(k)};
    final legacyRoom = DormRoom.fromPrefsMap(legacyMap);
    if (legacyRoom == null) return null;

    await save(legacyRoom, accountId: accountId);
    for (final key in _keys) {
      await prefs.remove(key);
    }
    return legacyRoom;
  }

  Future<void> clear({String? accountId}) async {
    final prefs = await SharedPreferences.getInstance();
    final hasAccountId = accountId != null && accountId.trim().isNotEmpty;
    for (final k in _keys) {
      await prefs.remove(_key(k, accountId));
      if (!hasAccountId) {
        await prefs.remove(_key(k, 'default'));
        await prefs.remove(k);
      }
    }
    // 也清除旧版本的字段（兼容旧存档）
    for (final k in ['dorm_building', 'dorm_sysid']) {
      await prefs.remove(_key(k, accountId));
      if (!hasAccountId) {
        await prefs.remove(_key(k, 'default'));
        await prefs.remove(k);
      }
    }
  }
}

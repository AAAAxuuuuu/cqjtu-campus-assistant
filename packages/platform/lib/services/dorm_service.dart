import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:core/models/dorm_room.dart';

final dormServiceProvider = Provider<DormService>((ref) => DormService());

class DormService {
  static const _keys = [
    'dorm_campus',
    'dorm_garden',
    'dorm_number',
    'dorm_roomid',
  ];

  static String _key(String base, String? accountId) {
    final safeAccount = (accountId != null && accountId.trim().isNotEmpty)
        ? accountId.trim()
        : 'guest';
    return 'user_${safeAccount}_$base';
  }

  Future<void> save(DormRoom room, {String? accountId}) async {
    final prefs = await SharedPreferences.getInstance();
    for (final entry in room.toPrefsMap().entries) {
      await prefs.setString(_key(entry.key, accountId), entry.value);
    }
  }

  Future<DormRoom?> load({String? accountId}) async {
    final prefs = await SharedPreferences.getInstance();

    final scopedMap = {
      for (final k in _keys) k: prefs.getString(_key(k, accountId))
    };
    final scopedRoom = DormRoom.fromPrefsMap(scopedMap);
    if (scopedRoom != null) {
      return scopedRoom;
    }

    final legacyMap = {for (final k in _keys) k: prefs.getString(k)};
    return DormRoom.fromPrefsMap(legacyMap);
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
    for (final k in [
      'dorm_building',
      'dorm_buildid',
      'dorm_sysid',
      'dorm_areaid'
    ]) {
      await prefs.remove(_key(k, accountId));
      if (!hasAccountId) {
        await prefs.remove(_key(k, 'default'));
        await prefs.remove(k);
      }
    }
  }
}

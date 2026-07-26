import 'package:core/models/dorm_room.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:campus_platform/services/dorm_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('DormService tests', () {
    test('save and load with accountId scopes keys correctly', () async {
      final service = DormService();
      const roomA = DormRoom(
        campusName: '科学城校区',
        garden: DormGarden.deYuan,
        buildingNumber: 8,
        roomNumber: '0305',
      );

      await service.save(roomA, accountId: 'userA');

      final loadedA = await service.load(accountId: 'userA');
      expect(loadedA, isNotNull);
      expect(loadedA!.buildingFullName, '德园8舍');
      expect(loadedA.roomNumber, '0305');

      final loadedB = await service.load(accountId: 'userB');
      expect(loadedB, isNull);
    });

    test(
        'load falls back to legacy un-prefixed keys if scoped keys are missing',
        () async {
      SharedPreferences.setMockInitialValues({
        'dorm_campus': '科学城校区',
        'dorm_garden': 'deYuan',
        'dorm_number': '5',
        'dorm_roomid': '0101',
      });

      final service = DormService();
      final loaded = await service.load(accountId: 'userA');
      expect(loaded, isNotNull);
      expect(loaded!.buildingFullName, '德园5舍');
      expect(loaded.roomNumber, '0101');
    });

    test(
        'clear({String? accountId}) preserves legacy un-prefixed keys when accountId is provided',
        () async {
      SharedPreferences.setMockInitialValues({
        'dorm_campus': '科学城校区',
        'dorm_garden': 'deYuan',
        'dorm_number': '5',
        'dorm_roomid': '0101',
        'user_userA_dorm_campus': '南岸校区',
        'user_userA_dorm_garden': 'zhiYuan',
        'user_userA_dorm_number': '3',
        'user_userA_dorm_roomid': '0202',
      });

      final service = DormService();

      // Clear for userA
      await service.clear(accountId: 'userA');

      final prefs = await SharedPreferences.getInstance();

      // Scoped keys for userA should be removed
      expect(prefs.containsKey('user_userA_dorm_campus'), isFalse);
      expect(prefs.containsKey('user_userA_dorm_roomid'), isFalse);

      // Legacy un-prefixed keys MUST still be preserved for other accounts
      expect(prefs.getString('dorm_campus'), '科学城校区');
      expect(prefs.getString('dorm_garden'), 'deYuan');
      expect(prefs.getString('dorm_number'), '5');
      expect(prefs.getString('dorm_roomid'), '0101');
    });

    test(
        'clear() without accountId removes both default scoped keys and legacy un-prefixed keys',
        () async {
      SharedPreferences.setMockInitialValues({
        'dorm_campus': '科学城校区',
        'dorm_garden': 'deYuan',
        'dorm_number': '5',
        'dorm_roomid': '0101',
        'user_default_dorm_campus': '科学城校区',
        'user_default_dorm_garden': 'deYuan',
        'user_default_dorm_number': '5',
        'user_default_dorm_roomid': '0101',
      });

      final service = DormService();

      await service.clear();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('user_default_dorm_campus'), isFalse);
      expect(prefs.containsKey('dorm_campus'), isFalse);
    });
  });
}

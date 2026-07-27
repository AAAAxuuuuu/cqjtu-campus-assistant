import 'package:core/models/dorm_room.dart';
import 'package:test/test.dart';

void main() {
  test('South-Campus rooms use the verified electricity selector IDs', () {
    final room = DormRoom.southCampus(
      district: southDormDistricts.first,
      building: southDormDistricts.first.buildings[4],
      roomNumber: '0305',
    );

    expect(room.displayName, '菁园 菁园5栋1单元 305室');
    expect(room.toQueryParams(), {
      'sysid': '1',
      'areaid': '2',
      'districtid': '02',
      'buildid': '0501_02_C_菁园5栋1单元',
      'floorid': '0',
      'roomid': '0305',
    });

    final restored = DormRoom.fromPrefsMap(
      Map<String, String?>.from(room.toPrefsMap()),
    );
    expect(restored?.displayName, room.displayName);
    expect(restored?.toQueryParams(), room.toQueryParams());
  });

  test('staff accommodation IDs are not accepted as student dorms', () {
    final room = DormRoom.fromPrefsMap({
      'dorm_campus': '南岸校区',
      'dorm_roomid': '0305',
      'dorm_areaid': '2',
      'dorm_districtid': '80',
      'dorm_buildid': '0100_80_C_测试楼',
    });

    expect(room, isNull);
  });
}

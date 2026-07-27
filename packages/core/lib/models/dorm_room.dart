/// 园区类型（科学城校区）。
enum DormGarden {
  deYuan('德园', '01'),
  liYuan('礼园', '05');

  final String label;
  final String suffix;

  const DormGarden(this.label, this.suffix);
}

/// 南岸校区的楼栋。ID 来自一卡通电控接口，不能由显示名称推算。
class SouthDormBuilding {
  const SouthDormBuilding({required this.id, required this.label});

  final String id;
  final String label;
}

/// 南岸校区仅开放给学生的宿舍园区。
class SouthDormDistrict {
  const SouthDormDistrict({
    required this.id,
    required this.label,
    required this.buildings,
  });

  final String id;
  final String label;
  final List<SouthDormBuilding> buildings;
}

const southDormDistricts = [
  SouthDormDistrict(
    id: '02',
    label: '菁园',
    buildings: [
      SouthDormBuilding(id: '0100_02_C_菁园1栋', label: '菁园1栋'),
      SouthDormBuilding(id: '0200_02_C_菁园2栋', label: '菁园2栋'),
      SouthDormBuilding(id: '0300_02_C_菁园3栋', label: '菁园3栋'),
      SouthDormBuilding(id: '0400_02_C_菁园4栋', label: '菁园4栋'),
      SouthDormBuilding(id: '0501_02_C_菁园5栋1单元', label: '菁园5栋1单元'),
      SouthDormBuilding(id: '0502_02_C_菁园5栋2单元', label: '菁园5栋2单元'),
      SouthDormBuilding(id: '0601_02_C_菁园6栋1单元', label: '菁园6栋1单元'),
      SouthDormBuilding(id: '0602_02_C_菁园6栋2单元', label: '菁园6栋2单元'),
      SouthDormBuilding(id: '0603_02_C_菁园6栋3单元', label: '菁园6栋3单元'),
      SouthDormBuilding(id: '0701_02_C_菁园7栋1单元', label: '菁园7栋1单元'),
      SouthDormBuilding(id: '0702_02_C_菁园7栋2单元', label: '菁园7栋2单元'),
      SouthDormBuilding(id: '0703_02_C_菁园7栋3单元', label: '菁园7栋3单元'),
      SouthDormBuilding(id: '0900_02_C_菁园9栋', label: '菁园9栋'),
    ],
  ),
  SouthDormDistrict(
    id: '03',
    label: '雅园',
    buildings: [
      SouthDormBuilding(id: '0100_03_C_雅园A栋', label: '雅园A栋'),
      SouthDormBuilding(id: '0200_03_C_雅园B栋', label: '雅园B栋'),
      SouthDormBuilding(id: '0300_03_C_雅园C栋', label: '雅园C栋'),
      SouthDormBuilding(id: '0400_03_C_雅园D栋', label: '雅园D栋'),
      SouthDormBuilding(id: '0500_03_C_雅园E栋', label: '雅园E栋'),
    ],
  ),
  SouthDormDistrict(
    id: '04',
    label: '慧园',
    buildings: [
      SouthDormBuilding(id: '0100_04_C_慧园A栋', label: '慧园A栋'),
      SouthDormBuilding(id: '0200_04_C_慧园B栋', label: '慧园B栋'),
    ],
  ),
];

/// 根据园区 + 舍号生成科学城校区的 buildid。
String buildDormId(DormGarden garden, int number) {
  final numStr = number.toString().padLeft(2, '0');
  return '${numStr}00_${garden.suffix}_C_${garden.label}${number}舍';
}

String buildingName(DormGarden garden, int number) =>
    '${garden.label}${number}舍';

const int kDormNumberMin = 1;
const int kDormNumberMax = 15;

/// 用户当前选中的宿舍。
///
/// 默认构造函数保留科学城校区的旧数据结构；南岸校区使用
/// [DormRoom.southCampus]，由已验证的电控园区和楼栋 ID 组成。
class DormRoom {
  static const preferenceKeys = [
    'dorm_campus',
    'dorm_garden',
    'dorm_number',
    'dorm_roomid',
    'dorm_areaid',
    'dorm_districtid',
    'dorm_buildid',
  ];

  final String campusName;
  final DormGarden garden;
  final int buildingNumber;
  final String roomNumber;
  final SouthDormDistrict? southDistrict;
  final SouthDormBuilding? southBuilding;

  const DormRoom({
    required this.campusName,
    required this.garden,
    required this.buildingNumber,
    required this.roomNumber,
  }) : southDistrict = null,
       southBuilding = null;

  const DormRoom.southCampus({
    required SouthDormDistrict district,
    required SouthDormBuilding building,
    required this.roomNumber,
  }) : campusName = '南岸校区',
       garden = DormGarden.deYuan,
       buildingNumber = 0,
       southDistrict = district,
       southBuilding = building;

  bool get isSouthCampus => southDistrict != null && southBuilding != null;

  String get buildingFullName => isSouthCampus
      ? southBuilding!.label
      : buildingName(garden, buildingNumber);

  String get buildid =>
      isSouthCampus ? southBuilding!.id : buildDormId(garden, buildingNumber);

  String get displayName {
    final room = roomNumber.replaceFirst(RegExp(r'^0+'), '');
    final district = isSouthCampus ? '${southDistrict!.label} ' : '';
    return '$district$buildingFullName ${room.isEmpty ? roomNumber : room}室';
  }

  /// 电控余额查询参数。南岸网页明确要求园区和固定的“无”楼层。
  Map<String, String> toQueryParams() => {
    'sysid': '1',
    'areaid': isSouthCampus ? '2' : '1',
    if (isSouthCampus) 'districtid': southDistrict!.id,
    'buildid': buildid,
    if (isSouthCampus) 'floorid': '0',
    'roomid': roomNumber,
  };

  Map<String, String> toPrefsMap() => {
    'dorm_campus': campusName,
    'dorm_roomid': roomNumber,
    if (isSouthCampus) ...{
      'dorm_areaid': '2',
      'dorm_districtid': southDistrict!.id,
      'dorm_buildid': southBuilding!.id,
    } else ...{
      'dorm_garden': garden.name,
      'dorm_number': buildingNumber.toString(),
    },
  };

  static DormRoom? fromPrefsMap(Map<String, String?> map) {
    final roomid = map['dorm_roomid'];
    if (roomid == null || roomid.trim().isEmpty) return null;

    if (map['dorm_areaid'] == '2') {
      final districtId = map['dorm_districtid'];
      final buildingId = map['dorm_buildid'];
      SouthDormDistrict? district;
      for (final item in southDormDistricts) {
        if (item.id == districtId) {
          district = item;
          break;
        }
      }
      if (district == null || buildingId == null) return null;
      SouthDormBuilding? building;
      for (final item in district.buildings) {
        if (item.id == buildingId) {
          building = item;
          break;
        }
      }
      if (building == null) return null;
      return DormRoom.southCampus(
        district: district,
        building: building,
        roomNumber: roomid,
      );
    }

    final campus = map['dorm_campus'];
    final gardenName = map['dorm_garden'];
    final number = int.tryParse(map['dorm_number'] ?? '');
    if (campus == null || gardenName == null || number == null) return null;

    try {
      final garden = DormGarden.values.byName(gardenName);
      if (number < kDormNumberMin || number > kDormNumberMax) return null;
      return DormRoom(
        campusName: campus,
        garden: garden,
        buildingNumber: number,
        roomNumber: roomid,
      );
    } catch (_) {
      return null;
    }
  }
}

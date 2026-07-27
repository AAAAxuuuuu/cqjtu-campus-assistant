import 'package:campus_platform/services/account_cache_service.dart';
import 'package:campus_platform/services/dorm_service.dart';
import 'package:core/models/dorm_room.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_providers.dart';
import '../campus_card/campus_card_providers.dart';
import '../electricity/electricity_providers.dart';
import '../exams/exams_providers.dart';
import '../grades/grades_providers.dart';
import '../schedule/schedule_providers.dart';
import '../study_progress/study_progress_providers.dart';

class DormRoomNotifier extends AsyncNotifier<DormRoom?> {
  @override
  Future<DormRoom?> build() async {
    final accountId = getAccountId(ref, listen: true);
    return ref.read(dormServiceProvider).load(accountId: accountId);
  }

  Future<void> set(DormRoom room) async {
    final accountId = getAccountId(ref, listen: false);
    await ref.read(dormServiceProvider).save(room, accountId: accountId);
    state = AsyncData(room);
  }

  Future<void> clear() async {
    final accountId = getAccountId(ref, listen: false);
    await ref.read(dormServiceProvider).clear(accountId: accountId);
    state = const AsyncData(null);
  }
}

final dormRoomProvider = AsyncNotifierProvider<DormRoomNotifier, DormRoom?>(
  DormRoomNotifier.new,
);

final accountCacheProvider = Provider<AccountCacheService>((ref) {
  return ref.watch(accountCacheServiceProvider);
});

/// Reloads account-bound state after a sign-in switch without deleting the
/// previous account's local preferences or cached course data.
void resetAccountBoundProviders(dynamic ref) {
  ref.invalidate(scheduleProvider);
  ref.invalidate(gradesProvider);
  ref.invalidate(gradeDetailProvider);
  ref.invalidate(examsProvider);
  ref.invalidate(electricityProvider);
  ref.invalidate(campusCardBalanceProvider);
  ref.invalidate(studyProgressProvider);
  ref.invalidate(customCoursesProvider);
  ref.invalidate(semesterTotalWeeksProvider);
  ref.invalidate(scheduleSundayFirstProvider);
  ref.invalidate(scheduleShowInactiveCoursesProvider);
  ref.invalidate(scheduleDensityProvider);
  ref.invalidate(scheduleBackgroundImageProvider);
  ref.invalidate(scheduleCalendarRulesProvider);
  ref.invalidate(dormRoomProvider);
  ref.invalidate(selectedScheduleSemesterProvider);
  ref.invalidate(semesterStartProvider);
  ref.invalidate(semesterStartForKeyProvider);
  ref.invalidate(activeSemesterStartProvider);
}

/// Clears current account cache in persistent storage and session service,
/// and invalidates live Riverpod providers for immediate UI update.
Future<void> clearCurrentAccountCache(dynamic ref, String username) async {
  final cacheService = ref.read(accountCacheProvider) as AccountCacheService;
  await cacheService.clearAccountCache(username);

  resetAccountBoundProviders(ref);
}

import 'package:core/models/course.dart';

/// The subset of the campus backend API used by session managers.
///
/// Extracted so [ApiService] (self-hosted backend) can be faked in offline
/// tests of session recovery and login-state restoration.
abstract class CampusSessionApi {
  Future<String> createSession(String username);

  Future<void> loginWithTicket(
    String username,
    String ticket, {
    required String sessionId,
  });

  Future<void> injectCookies(
    String username,
    String domain,
    String cookies, {
    required String sessionId,
  });

  Future<({List<Course> courses, String remark})> getSchedule(
    String username,
    String password, {
    required String sessionId,
    String? semester,
    bool forceRefresh = false,
  });
}

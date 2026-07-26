import 'package:flutter_test/flutter_test.dart';
import 'package:campus_app/utils/campus_error_message.dart';

void main() {
  test('maps CAS DNS lookup failures to an actionable message', () {
    const error =
        'SocketFailed host lookup: ids.cqjtu.edu.cn (OS Error: No address associated with hostname, errno = 7)';

    expect(isCampusDnsError(error), isTrue);
    expect(formatCampusError(error), '无法解析统一认证服务器地址，请检查网络或 DNS 设置后重试');
  });

  test('maps timeout failures without exposing the low-level exception', () {
    expect(
      formatCampusError(Exception('connection timeout after 20 seconds')),
      '连接学校服务器超时，请检查网络后重试',
    );
  });

  test('keeps authentication failures user-readable', () {
    expect(formatCampusError(Exception('账号或密码错误')), '账号或密码错误');
  });
}

import 'package:data/data.dart';

bool isCampusNetworkError(Object error) {
  final message = error.toString().toLowerCase();
  return message.contains('socket') ||
      message.contains('host lookup') ||
      message.contains('no address associated with hostname') ||
      message.contains('network is unreachable') ||
      message.contains('timed out') ||
      message.contains('timeout') ||
      message.contains('connection') ||
      message.contains('handshake') ||
      message.contains('certificate_verify_failed');
}

bool isCampusDnsError(Object error) {
  final message = error.toString().toLowerCase();
  return message.contains('host lookup') ||
      message.contains('no address associated with hostname') ||
      message.contains('errno = 7');
}

String formatCampusError(Object error) {
  if (isCampusDnsError(error)) {
    return '无法解析统一认证服务器地址，请检查网络或 DNS 设置后重试';
  }

  final message = error.toString().toLowerCase();
  if (message.contains('timed out') || message.contains('timeout')) {
    return '连接学校服务器超时，请检查网络后重试';
  }
  if (message.contains('handshake') ||
      message.contains('certificate_verify_failed')) {
    return '与学校服务器的安全连接失败，请检查网络环境后重试';
  }
  if (message.contains('socket') ||
      message.contains('network is unreachable')) {
    return '网络连接不可用，请检查网络后重试';
  }
  if (error is CampusFailure) return error.message;

  return error
      .toString()
      .replaceFirst(RegExp(r'^(Exception|FormatException):\s*'), '')
      .trim();
}

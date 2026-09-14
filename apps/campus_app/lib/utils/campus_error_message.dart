import 'package:data/data.dart';

bool isCampusNetworkError(Object error) {
  // 人机验证不是网络故障：提示"检查网络"会把用户引向错误的排查方向。
  if (error is BotChallengeFailure) return false;

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
  // 先判类型再做字符串启发式匹配。下面的 contains 判断早于类型判断，
  // 一旦异常文案里出现 connection/timeout 之类的词就会被误归类为网络错误。
  if (error is BotChallengeFailure) return error.message;

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

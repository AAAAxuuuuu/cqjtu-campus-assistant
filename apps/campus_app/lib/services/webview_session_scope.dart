import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter/webview_flutter.dart';

const _webViewSessionAccountKey = 'webview_session_account_v1';

bool requiresWebViewSessionReset(String? previousUsername, String username) {
  final current = username.trim();
  if (current.isEmpty) return false;
  return previousUsername?.trim() != current;
}

class WebViewSessionScope {
  static Future<bool> resetForAccount(
    WebViewController controller,
    String username,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final current = username.trim();
    if (!requiresWebViewSessionReset(
      prefs.getString(_webViewSessionAccountKey),
      current,
    )) {
      return false;
    }

    await WebViewCookieManager().clearCookies();
    await controller.clearCache();
    await controller.clearLocalStorage();
    await prefs.setString(_webViewSessionAccountKey, current);
    return true;
  }

  static Future<void> markAuthenticated(String username) async {
    final current = username.trim();
    if (current.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_webViewSessionAccountKey, current);
  }

  static Future<void> clearOnLogout() async {
    await WebViewCookieManager().clearCookies();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_webViewSessionAccountKey);
  }
}

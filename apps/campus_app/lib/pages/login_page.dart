import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:campus_platform/services/credential_service.dart';
import 'package:data/data.dart';

import '../theme/app_theme.dart';
import '../utils/providers.dart';
import '../utils/campus_error_message.dart';
import '../widgets/app_button.dart';
import '../widgets/app_entrance.dart';
import 'webview_login_page.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _usernameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();

  bool _loading = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveCredentialsAndFinish(
    String username,
    String password,
  ) async {
    final previousUsername = ref.read(credentialsProvider)?.username.trim();
    await ref.read(credentialServiceProvider).save(username, password);
    ref.read(credentialsProvider.notifier).set(username, password);
    if (previousUsername != null &&
        previousUsername.isNotEmpty &&
        previousUsername != username) {
      resetAccountBoundProviders(ref);
    }
    ref.read(zoveTokenRefreshProvider.notifier).requestRefresh();
  }

  Future<void> _login() async {
    final username = _usernameCtrl.text.trim();
    final password = _passwordCtrl.text;

    if (!RegExp(r'^\d{12}$').hasMatch(username)) {
      setState(() => _error = '请输入12位学号');
      return;
    }
    if (password.isEmpty) {
      setState(() => _error = '请输入密码');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await _resetLocalLoginSession(username);
      await _verifyLoginForCurrentMode(username, password);
      await _saveCredentialsAndFinish(username, password);
    } catch (error) {
      if (_requiresSecurityVerification(error)) {
        setState(() {
          _error = '需要安全验证，正在打开网页登录...';
          _loading = false;
        });
        await _openWebViewLogin(username, password);
      } else {
        setState(() => _error = formatCampusError(error));
      }
    } finally {
      if (mounted && _loading) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _verifyLoginForCurrentMode(
    String username,
    String password,
  ) async {
    final mode = ref.read(campusRuntimeModeProvider);
    if (mode == CampusRuntimeMode.selfHosted) {
      final sessionManager = ref.read(sessionManagerProvider);
      await sessionManager.verifyScheduleReady(username, password);
      return;
    }

    final gateway = ref.read(campusGatewayProvider);
    if (gateway is DirectSchoolCampusGateway) {
      await gateway.loginWithPassword(username, password);
      return;
    }

    await gateway.getSchedule(username, password, forceRefresh: true);
  }

  Future<void> _resetLocalLoginSession(String username) async {
    if (ref.read(campusRuntimeModeProvider) != CampusRuntimeMode.localAndroid) {
      return;
    }

    final gateway = ref.read(campusGatewayProvider);
    if (gateway is DirectSchoolCampusGateway) {
      await gateway.resetLoginSession(username);
    }
  }

  Future<void> _verifyWebLoginForCurrentMode(
    String username,
    String password,
  ) async {
    if (ref.read(campusRuntimeModeProvider) != CampusRuntimeMode.localAndroid) {
      await _verifyLoginForCurrentMode(username, password);
      return;
    }

    final gateway = ref.read(campusGatewayProvider);
    if (gateway is DirectSchoolCampusGateway) {
      await gateway.verifyImportedSession(username);
      return;
    }

    await _verifyLoginForCurrentMode(username, password);
  }

  bool _requiresSecurityVerification(Object error) {
    if (error is AuthInvalidFailure) return false;
    if (error is CaptchaRequiredFailure) return true;

    final sessionManager = ref.read(sessionManagerProvider);
    final errorText = error.toString();
    final lowerError = errorText.toLowerCase();

    if (errorText.contains('账号或密码错误') ||
        errorText.contains('密码不正确') ||
        errorText.contains('密码错误') ||
        errorText.contains('密码不匹配') ||
        errorText.contains('账号不存在')) {
      return false;
    }

    return sessionManager.isSecurityVerificationError(error) ||
        sessionManager.isManualVerificationRequired(
          error,
          domain: SystemDomain.schedule,
        ) ||
        errorText.contains('449') ||
        lowerError.contains('captcha') ||
        lowerError.contains('needcaptcha') ||
        lowerError.contains('security');
  }

  Future<void> _openWebViewLogin(String username, [String? password]) async {
    final result = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(
        builder: (_) =>
            WebViewLoginPage(username: username, password: password ?? ''),
      ),
    );

    if (result == null) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await ref
          .read(webLoginBinderProvider)
          .bind(username: username, result: result);

      final webPassword = result['password']?.toString() ?? '';
      var passwordToSave = webPassword.trim().isNotEmpty
          ? webPassword
          : (password ?? '');

      if (passwordToSave.trim().isEmpty) {
        final existing = await ref.read(credentialServiceProvider).load();
        if (existing != null &&
            existing.username == username &&
            existing.password.trim().isNotEmpty) {
          passwordToSave = existing.password;
        }
      }

      if (passwordToSave.trim().isEmpty) {
        setState(() {
          _error = '网页登录成功，但未获取到密码，请手动输入后再试一次。';
        });
        return;
      }

      // Do not re-enter the password CAS flow after WebView established a
      // session. Validate only the imported Cookie/Ticket state.
      await _verifyWebLoginForCurrentMode(username, passwordToSave);
      await _saveCredentialsAndFinish(username, passwordToSave);
    } catch (error) {
      setState(() {
        _error = '网页登录处理失败: ${formatCampusError(error)}';
      });
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppColors.pageGradient),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              child: Container(
                constraints: const BoxConstraints(maxWidth: 420),
                padding: const EdgeInsets.symmetric(
                  horizontal: 28,
                  vertical: 36,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(AppRadius.hero),
                  border: Border.all(
                    color: AppColors.outline.withValues(alpha: 0.8),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.08),
                      blurRadius: 24,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AppEntrance(
                      index: 0,
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          gradient: AppColors.primaryGradient,
                          borderRadius: BorderRadius.circular(AppRadius.hero),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.primary.withValues(alpha: 0.25),
                              blurRadius: 16,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: Image.asset(
                          'assets/campus_app_mark.png',
                          width: 72,
                          height: 72,
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    AppEntrance(
                      index: 1,
                      child: ShaderMask(
                        shaderCallback: (bounds) => const LinearGradient(
                          colors: [
                            AppColors.textPrimary,
                            AppColors.textSecondary,
                          ],
                        ).createShader(bounds),
                        child: Text(
                          'CQJTU Hub',
                          style: AppType.metric.copyWith(
                            fontSize: 28,
                            letterSpacing: -0.5,
                            height: 1.1,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    AppEntrance(
                      index: 2,
                      child: Text(
                        '重庆交通大学 · 统一身份认证登录',
                        style: AppType.subtitle.copyWith(
                          color: AppColors.textMuted,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const SizedBox(height: 28),
                    AppEntrance(
                      index: 3,
                      child: TextField(
                        controller: _usernameCtrl,
                        keyboardType: TextInputType.number,
                        maxLength: 12,
                        // Without autofillHints Android password managers do
                        // not recognise this form and cannot fill it.
                        autofillHints: const [AutofillHints.username],
                        textInputAction: TextInputAction.next,
                        style: const TextStyle(fontWeight: FontWeight.w500),
                        decoration: InputDecoration(
                          labelText: '学号',
                          prefixIcon: const Icon(
                            Icons.person_outline,
                            color: AppColors.primary,
                          ),
                          counterText: '',
                          filled: true,
                          fillColor: AppColors.tintSoft,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    AppEntrance(
                      index: 4,
                      child: TextField(
                        controller: _passwordCtrl,
                        obscureText: _obscure,
                        onSubmitted: (_) => _login(),
                        autofillHints: const [AutofillHints.password],
                        textInputAction: TextInputAction.done,
                        style: const TextStyle(fontWeight: FontWeight.w500),
                        decoration: InputDecoration(
                          labelText: '密码',
                          prefixIcon: const Icon(
                            Icons.lock_outline,
                            color: AppColors.secondary,
                          ),
                          filled: true,
                          fillColor: AppColors.tintSoft,
                          suffixIcon: IconButton(
                            // The label has to track state: announcing
                            // "显示密码" while the password is already visible
                            // tells a screen-reader user the opposite of what
                            // the button will do.
                            tooltip: _obscure ? '显示密码' : '隐藏密码',
                            icon: Icon(
                              _obscure
                                  ? Icons.visibility_off
                                  : Icons.visibility,
                              color: AppColors.textMuted,
                            ),
                            onPressed: () =>
                                setState(() => _obscure = !_obscure),
                          ),
                        ),
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 16),
                      AppEntrance(
                        index: 5,
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.accent.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(
                              AppRadius.sm + 2,
                            ),
                            border: Border.all(
                              color: AppColors.accent.withValues(alpha: 0.4),
                            ),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.info_outline,
                                color: AppColors.accent,
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _error!,
                                  style: const TextStyle(
                                    color: AppColors.accent,
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                    AppEntrance(
                      index: 6,
                      child: AppButton(
                        label: '登 录',
                        isLoading: _loading,
                        onPressed: _login,
                        width: double.infinity,
                        height: 50,
                        style: AppButtonStyle.gradient,
                      ),
                    ),
                    const SizedBox(height: 14),
                    AppEntrance(
                      index: 7,
                      child: TextButton.icon(
                        icon: const Icon(Icons.open_in_browser, size: 16),
                        label: const Text('遇到验证问题？使用网页登录'),
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.secondary,
                          textStyle: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        onPressed: _loading
                            ? null
                            : () {
                                final username = _usernameCtrl.text.trim();
                                if (!RegExp(r'^\d{12}$').hasMatch(username)) {
                                  setState(() => _error = '请先输入正确学号再使用网页登录');
                                  return;
                                }
                                _openWebViewLogin(username, _passwordCtrl.text);
                              },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

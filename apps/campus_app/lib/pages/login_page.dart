import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// 移除报错的 import 'package:data/src/api_service.dart';
import 'package:campus_platform/services/credential_service.dart';
import 'package:campus_app/config/app_config.dart';
import '../utils/providers.dart';
import 'webview_login_page.dart'; // 确保你的同级目录下有这个文件

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

  // ── 补全漏掉的保存凭据方法 ─────────────────────────────────────
  Future<void> _saveCredentialsAndFinish(
    String username,
    String password,
  ) async {
    await ref.read(credentialServiceProvider).save(username, password);
    ref.read(credentialsProvider.notifier).set(username, password);
  }

  // ── 静默登录流程 ───────────────────────────────────────────
  Future<void> _login() async {
    final username = _usernameCtrl.text.trim();
    final password = _passwordCtrl.text;

    if (!RegExp(r'^\d{12}$').hasMatch(username)) {
      setState(() => _error = '学号格式不正确（12位数字）');
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
      // 尝试静默获取课表来验证
      await ref.read(apiServiceProvider).getSchedule(username, password);
      // 成功则保存凭证并进入 App
      await _saveCredentialsAndFinish(username, password);
    } catch (e) {
      // 捕获异常，如果错误信息包含特定的关键字（比如验证码拦截或449状态码）
      final errorStr = e.toString();
      if (errorStr.contains('449') ||
          errorStr.contains('验证码') ||
          errorStr.contains('HTML') ||
          errorStr.contains('CAS')) {
        setState(() {
          _error = '系统要求安全验证，正在打开网页登录...';
          _loading = false;
        });
        // 自动触发 WebView 登录
        await _openWebViewLogin(username, password);
      } else {
        setState(() => _error = errorStr);
      }
    } finally {
      if (mounted && _loading) setState(() => _loading = false);
    }
  }

  // ── WebView 介入流程 ───────────────────────────────────
  Future<void> _openWebViewLogin(String username, [String? password]) async {
    final result = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(
        // 【修改点】：把账号密码传给 WebView
        builder: (_) =>
            WebViewLoginPage(username: username, password: password ?? ""),
      ),
    );

    if (result == null) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final api = ref.read(apiServiceProvider);

      // 注入从 WebView 提取到的各域名的 Cookie
      if (result['casCookies'] != null &&
          result['casCookies'].toString().isNotEmpty) {
        await api.injectCookies(
          username,
          'ids.cqjtu.edu.cn',
          result['casCookies'],
        );
      }
      if (result['jwgCookies'] != null &&
          result['jwgCookies'].toString().isNotEmpty) {
        await api.injectCookies(
          username,
          'jwgln.cqjtu.edu.cn',
          result['jwgCookies'],
        );
      }

      await _saveCredentialsAndFinish(username, password ?? "");
    } catch (e) {
      setState(() => _error = 'WebView 会话注入失败: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── Mock 模式 ───────────────────────────────────────────
  Future<void> _enterMockMode() async {
    setState(() => _loading = true);
    try {
      const mockUser = 'mock_user';
      const mockPass = 'mock_pass';
      await _saveCredentialsAndFinish(mockUser, mockPass);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.school, size: 80, color: Colors.blue),
                const SizedBox(height: 12),
                Text(
                  'CQJTU Hub',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                const Text('使用教务网账号登录', style: TextStyle(color: Colors.grey)),
                const SizedBox(height: 40),
                TextField(
                  controller: _usernameCtrl,
                  keyboardType: TextInputType.number,
                  maxLength: 12,
                  decoration: const InputDecoration(
                    labelText: '学号',
                    prefixIcon: Icon(Icons.person_outline),
                    border: OutlineInputBorder(),
                    counterText: '',
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _passwordCtrl,
                  obscureText: _obscure,
                  onSubmitted: (_) => _login(),
                  decoration: InputDecoration(
                    labelText: '密码',
                    prefixIcon: const Icon(Icons.lock_outline),
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscure ? Icons.visibility_off : Icons.visibility,
                      ),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style: const TextStyle(color: Colors.red, fontSize: 13),
                  ),
                ],
                const SizedBox(height: 28),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: FilledButton(
                    onPressed: _loading ? null : _login,
                    child: _loading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('登录', style: TextStyle(fontSize: 16)),
                  ),
                ),

                // ── 手动触发网页登录的备用入口（修复了之前的参数报错） ─────────────
                const SizedBox(height: 12),
                TextButton(
                  onPressed: _loading
                      ? null
                      : () {
                          final username = _usernameCtrl.text.trim();
                          if (!RegExp(r'^\d{12}$').hasMatch(username)) {
                            setState(() => _error = '请先输入正确的学号，再使用网页登录');
                            return;
                          }
                          _openWebViewLogin(username, _passwordCtrl.text);
                        },
                  child: const Text('遇到验证码？点击此处使用网页登录'),
                ),

                if (AppConfig.env == 'mock') ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.science_outlined),
                      label: const Text('体验模式（Mock 数据）'),
                      onPressed: _loading ? null : _enterMockMode,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '体验模式使用模拟数据，无需真实账号',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

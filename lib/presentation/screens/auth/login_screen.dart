import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/local_config_storage.dart';
import '../../../providers/auth_provider.dart';
import '../../widgets/app_logo.dart';
import '../settings/api_config_screen.dart';
import 'forgot_password_dialog.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _user = TextEditingController();
  final _pass = TextEditingController();
  bool _obscure = true;
  bool _remember = true; // ghi nhớ tài khoản + mật khẩu

  @override
  void initState() {
    super.initState();
    _loadSaved();
  }

  /// Điền sẵn tên đăng nhập + mật khẩu đã ghi nhớ.
  Future<void> _loadSaved() async {
    try {
      final c = await LocalConfigStorage.loadCredentials();
      if (c == null || !mounted) return;
      setState(() {
        _user.text = c.username;
        _pass.text = c.password;
      });
    } catch (_) {}
  }

  @override
  void dispose() {
    _user.dispose();
    _pass.dispose();
    super.dispose();
  }

  /// Đăng nhập thành công -> AuthProvider đổi state -> main.dart tự chuyển sang MainShell.
  void _submit() {
    if (_user.text.trim().isEmpty || _pass.text.isEmpty) return;
    context.read<AuthProvider>().login(_user.text, _pass.text, remember: _remember);
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const AppLogo(height: 110),
                const SizedBox(height: 16),
                const Text('DC TECH',
                    style: TextStyle(fontSize: 34, fontWeight: FontWeight.w900, letterSpacing: 1)),
                const Text('QUẢN LÝ THUÊ LOA',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.orange)),
                const SizedBox(height: 36),
                TextField(
                  controller: _user,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                      labelText: 'Tên đăng nhập', prefixIcon: Icon(Icons.person_outline)),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _pass,
                  obscureText: _obscure,
                  onSubmitted: (_) => _submit(),
                  decoration: InputDecoration(
                    labelText: 'Mật khẩu',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(_obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  controlAffinity: ListTileControlAffinity.leading,
                  activeColor: AppColors.orange,
                  value: _remember,
                  onChanged: (v) => setState(() => _remember = v ?? true),
                  title: const Text('Ghi nhớ tài khoản và mật khẩu', style: TextStyle(fontSize: 14)),
                ),
                if (auth.error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(auth.error!, style: const TextStyle(color: AppColors.red)),
                  ),
                const SizedBox(height: 22),
                FilledButton(
                  onPressed: auth.loading ? null : _submit,
                  child: auth.loading
                      ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                      : const Text('ĐĂNG NHẬP'),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => showDialog<void>(context: context, builder: (_) => const ForgotPasswordDialog()),
                  child: const Text('Quên mật khẩu?',
                      style: TextStyle(color: AppColors.orange, fontSize: 15, fontWeight: FontWeight.w600)),
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const ApiConfigScreen()),
                  ),
                  icon: const Icon(Icons.cloud_sync_outlined, size: 18),
                  label: const Text('Cấu hình kết nối Google Sheets (API)'),
                ),
                const SizedBox(height: 20),
                const Text('Phiên bản 1.0.4', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

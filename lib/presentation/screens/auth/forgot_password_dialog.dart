import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/services/google_sheets_service.dart';
import '../../../providers/auth_provider.dart';

/// Quên mật khẩu: gửi yêu cầu tới quản trị viên (không tự đổi được mật khẩu
/// vì app không có email/SMS để xác thực).
class ForgotPasswordDialog extends StatefulWidget {
  const ForgotPasswordDialog({super.key});
  @override
  State<ForgotPasswordDialog> createState() => _ForgotPasswordDialogState();
}

class _ForgotPasswordDialogState extends State<ForgotPasswordDialog> {
  final _user = TextEditingController();
  final _phone = TextEditingController();
  bool _busy = false;
  bool _sent = false;
  String? _error;
  String _hotline = '';

  @override
  void initState() {
    super.initState();
    // Lấy hotline công ty (tab Settings, khóa company_phone) để hiển thị
    GoogleSheetsService.instance.fetchSettings().then((s) {
      if (mounted) setState(() => _hotline = s['company_phone'] ?? '');
    }).catchError((_) {});
  }

  @override
  void dispose() {
    _user.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_user.text.trim().isEmpty || _phone.text.trim().isEmpty) {
      setState(() => _error = 'Vui lòng nhập tên đăng nhập và số điện thoại.');
      return;
    }
    final auth = context.read<AuthProvider>();
    setState(() {
      _busy = true;
      _error = null;
    });
    final err = await auth.requestPasswordReset(_user.text, _phone.text);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = err;
      _sent = err == null;
    });
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Quên mật khẩu'),
        content: SizedBox(
          width: 380,
          child: SingleChildScrollView(
            child: _sent ? _sentView() : _formView(),
          ),
        ),
        actions: _sent
            ? [FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Đã hiểu'))]
            : [
                TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('Hủy')),
                FilledButton(
                  onPressed: _busy ? null : _send,
                  style: FilledButton.styleFrom(minimumSize: const Size(130, 44)),
                  child: _busy
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Gửi yêu cầu'),
                ),
              ],
      );

  Widget _formView() => Column(mainAxisSize: MainAxisSize.min, children: [
        const Text(
          'Nhập tên đăng nhập và số điện thoại đã đăng ký. Yêu cầu sẽ được gửi tới quản trị viên '
          'để cấp mật khẩu tạm thời cho bạn.',
          style: TextStyle(color: AppColors.textMuted, height: 1.4),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _user,
          autocorrect: false,
          decoration: const InputDecoration(labelText: 'Tên đăng nhập', prefixIcon: Icon(Icons.person_outline)),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _phone,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(labelText: 'Số điện thoại đã đăng ký', prefixIcon: Icon(Icons.phone_outlined)),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(_error!, style: const TextStyle(color: AppColors.red)),
          ),
      ]);

  Widget _sentView() => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Icon(Icons.mark_email_read_outlined, color: AppColors.green, size: 40),
        const SizedBox(height: 12),
        const Text(
          'Nếu thông tin trùng khớp với một tài khoản đang hoạt động, yêu cầu đã được gửi tới '
          'quản trị viên. Quản trị viên sẽ cấp mật khẩu tạm thời cho bạn; bạn sẽ được yêu cầu đổi '
          'mật khẩu khi đăng nhập.',
          style: TextStyle(height: 1.4),
        ),
        if (_hotline.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text('Cần gấp? Liên hệ: $_hotline', style: const TextStyle(color: AppColors.orange, fontWeight: FontWeight.w700)),
        ],
      ]);
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../providers/auth_provider.dart';

/// Hộp thoại đổi mật khẩu.
/// [forced] = true: dùng sau khi bị reset / tài khoản mới — không đóng được,
/// chỉ có thể đổi mật khẩu hoặc đăng xuất.
class ChangePasswordDialog extends StatefulWidget {
  final bool forced;
  const ChangePasswordDialog({super.key, this.forced = false});
  @override
  State<ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<ChangePasswordDialog> {
  final _old = TextEditingController();
  final _new = TextEditingController();
  final _confirm = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _old.dispose();
    _new.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_new.text != _confirm.text) {
      setState(() => _error = 'Mật khẩu xác nhận không khớp');
      return;
    }
    final auth = context.read<AuthProvider>();
    setState(() {
      _busy = true;
      _error = null;
    });
    final err = await auth.changePassword(_old.text, _new.text);
    if (!mounted) return;
    if (err == null) {
      Navigator.pop(context, true);
    } else {
      setState(() {
        _error = err;
        _busy = false;
      });
    }
  }

  void _logout() {
    final auth = context.read<AuthProvider>();
    Navigator.pop(context, false); // đóng hộp thoại trước
    auth.logout();
  }

  @override
  Widget build(BuildContext context) {
    Widget field(TextEditingController c, String label) => Padding(
          padding: const EdgeInsets.only(top: 12),
          child: TextField(controller: c, obscureText: true, decoration: InputDecoration(labelText: label)),
        );

    return PopScope(
      canPop: !widget.forced,
      child: AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(widget.forced ? 'Đặt mật khẩu mới' : 'Đổi mật khẩu'),
        content: SizedBox(
          width: 360,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              if (widget.forced)
                const Text(
                  'Mật khẩu của bạn vừa được tạo hoặc đặt lại bởi quản trị viên. '
                  'Hãy đổi sang mật khẩu của riêng bạn để tiếp tục.',
                  style: TextStyle(color: AppColors.textMuted, height: 1.4),
                ),
              field(_old, widget.forced ? 'Mật khẩu tạm thời / hiện tại' : 'Mật khẩu hiện tại'),
              field(_new, 'Mật khẩu mới (tối thiểu 6 ký tự)'),
              field(_confirm, 'Nhập lại mật khẩu mới'),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(_error!, style: const TextStyle(color: AppColors.red)),
                ),
            ]),
          ),
        ),
        actions: [
          if (widget.forced)
            TextButton(onPressed: _busy ? null : _logout, child: const Text('Đăng xuất'))
          else
            TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('Hủy')),
          FilledButton(
            onPressed: _busy ? null : _save,
            style: FilledButton.styleFrom(minimumSize: const Size(110, 44)),
            child: const Text('Lưu'),
          ),
        ],
      ),
    );
  }
}

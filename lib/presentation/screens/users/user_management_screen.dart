import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/password_hasher.dart';
import '../../../data/models/store_model.dart';
import '../../../data/models/user_model.dart';
import '../../../data/services/google_sheets_service.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/user_provider.dart';

/// Quản lý nhân viên (Admin, Super Admin).
///
/// Quy tắc phân quyền:
///  - Super Admin: tạo/sửa/khóa mọi tài khoản, đặt được mọi vai trò.
///  - Admin: chỉ tạo/sửa/khóa tài khoản vai trò User.
///  - Không ai sửa/khóa chính mình tại đây (dùng Cài đặt -> Đổi mật khẩu).
///  - Không thể khóa Super Admin đang hoạt động cuối cùng.
class UserManagementScreen extends StatefulWidget {
  const UserManagementScreen({super.key});
  @override
  State<UserManagementScreen> createState() => _UserManagementScreenState();
}

class _UserManagementScreenState extends State<UserManagementScreen> {
  final _search = TextEditingController();
  List<StoreInfo> _stores = StoreInfo.defaultStores;

  AppUser get _me => context.read<AuthProvider>().currentUser!;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _reload());
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _snack(String msg, {bool error = true}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: error ? AppColors.red : AppColors.green));
  }

  Future<void> _reload() async {
    try {
      await context.read<UserProvider>().load();
      final settings = await GoogleSheetsService.instance.fetchSettings();
      final list = StoreInfo.listFromSettings(settings);
      if (mounted) setState(() => _stores = list);
    } catch (e) {
      _snack('Không tải được danh sách nhân viên: $e');
    }
  }

  bool _canEdit(AppUser actor, AppUser target) {
    if (target.id == actor.id) return false;
    if (actor.role == UserRole.superAdmin) return true;
    return actor.role == UserRole.admin && target.role == UserRole.user;
  }

  Future<void> _openForm([AppUser? existing]) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => _UserDialog(actor: _me, existing: existing, stores: _stores),
    );
    if (ok == true) _snack(existing == null ? 'Đã tạo tài khoản' : 'Đã cập nhật tài khoản', error: false);
  }

  Future<void> _toggle(AppUser u, bool active) async {
    final provider = context.read<UserProvider>();
    if (!active && u.role == UserRole.superAdmin) {
      final activeSupers =
          provider.users.where((x) => x.role == UserRole.superAdmin && x.isActive).length;
      if (activeSupers <= 1) {
        _snack('Không thể khóa Super Admin hoạt động cuối cùng.');
        return;
      }
    }
    try {
      await provider.update(u.copyWith(isActive: active));
    } catch (e) {
      _snack('Cập nhật thất bại: $e');
    }
  }

  /// Mật khẩu tạm 8 ký tự, bỏ các ký tự dễ nhầm (0/O, 1/l/I).
  String _tempPassword() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnpqrstuvwxyz23456789';
    final r = Random.secure();
    return List.generate(8, (_) => chars[r.nextInt(chars.length)]).join();
  }

  /// Reset mật khẩu: tạo mật khẩu tạm, bắt nhân viên đổi khi đăng nhập lần tới,
  /// xóa cờ "yêu cầu reset", rồi hiện mật khẩu tạm MỘT LẦN cho quản trị viên.
  Future<void> _resetPassword(AppUser u) async {
    final provider = context.read<UserProvider>();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Reset mật khẩu?'),
        content: Text(
            'Hệ thống sẽ tạo mật khẩu tạm thời cho "${u.displayName}". '
            'Mật khẩu cũ không còn dùng được, và nhân viên phải đổi mật khẩu khi đăng nhập lần tới.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Hủy')),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(minimumSize: const Size(110, 44)),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    final temp = _tempPassword();
    try {
      await provider.update(u.copyWith(
        passwordHash: PasswordHasher.hash(temp),
        mustChangePassword: true,
        resetRequested: '',
      ));
    } catch (e) {
      _snack('Reset thất bại: $e');
      return;
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _TempPasswordDialog(name: u.displayName, username: u.username, password: temp),
    );
  }

  Color _roleColor(UserRole r) => switch (r) {
        UserRole.superAdmin => AppColors.red,
        UserRole.admin => AppColors.blue,
        UserRole.user => Colors.grey.shade600,
      };

  @override
  Widget build(BuildContext context) {
    final p = context.watch<UserProvider>();
    final me = context.watch<AuthProvider>().currentUser!;
    final q = _search.text.trim().toLowerCase();
    final list = p.users
        .where((u) =>
            q.isEmpty ||
            u.displayName.toLowerCase().contains(q) ||
            u.username.toLowerCase().contains(q) ||
            u.storeName.toLowerCase().contains(q) ||
            u.phone.contains(q))
        .toList();

    return Scaffold(
      appBar: AppBar(title: const Text('QUẢN LÝ NHÂN VIÊN')),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Center(
            heightFactor: 1,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: FilledButton.icon(
                onPressed: () => _openForm(),
                icon: const Icon(Icons.add),
                label: const Text('THÊM TÀI KHOẢN MỚI'),
              ),
            ),
          ),
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: TextField(
                controller: _search,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(hintText: 'Tìm kiếm nhân viên, cửa hàng...', prefixIcon: Icon(Icons.search)),
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _reload,
                child: p.loading && p.users.isEmpty
                    ? const Center(child: CircularProgressIndicator())
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                        itemCount: list.length,
                        itemBuilder: (_, i) => _card(list[i], me),
                      ),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _card(AppUser u, AppUser me) {
    final editable = _canEdit(me, u);
    final storeLabel = u.storeName.isNotEmpty ? u.storeName : 'Cửa hàng chính';
    return Card(
      color: AppColors.surface,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: editable ? () => _openForm(u) : null,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            CircleAvatar(
              radius: 28,
              backgroundColor: AppColors.field,
              child: Text(u.displayName[0].toUpperCase(),
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(u.displayName + (u.id == me.id ? ' (bạn)' : ''),
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                Text('@${u.username}${u.phone.isEmpty ? '' : ' · ${u.phone}'}',
                    style: const TextStyle(color: AppColors.textMuted, fontSize: 13)),
                const SizedBox(height: 4),
                Row(children: [
                  const Icon(Icons.storefront_outlined, size: 14, color: AppColors.orange),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(storeLabel, style: const TextStyle(fontSize: 12, color: AppColors.orange, fontWeight: FontWeight.w600)),
                  ),
                ]),
                const SizedBox(height: 6),
                Wrap(spacing: 6, runSpacing: 4, children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
                    decoration: BoxDecoration(color: _roleColor(u.role), borderRadius: BorderRadius.circular(14)),
                    child: Text(u.role.label,
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white)),
                  ),
                  if (u.resetRequested.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.orange.withValues(alpha: 0.2),
                        border: Border.all(color: AppColors.orange),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Text('Yêu cầu reset mật khẩu',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.orange)),
                    ),
                ]),
              ]),
            ),
            if (editable)
              IconButton(
                tooltip: 'Reset mật khẩu',
                icon: Icon(Icons.lock_reset,
                    color: u.resetRequested.isNotEmpty ? AppColors.orange : AppColors.textMuted),
                onPressed: () => _resetPassword(u),
              ),
            Column(children: [
              Switch(
                value: u.isActive,
                activeThumbColor: AppColors.green,
                onChanged: editable ? (v) => _toggle(u, v) : null,
              ),
              Text(u.isActive ? 'Hoạt động' : 'Đã khóa',
                  style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
            ]),
          ]),
        ),
      ),
    );
  }
}

/// Form tạo / sửa tài khoản.
class _UserDialog extends StatefulWidget {
  final AppUser actor;
  final AppUser? existing;
  final List<StoreInfo> stores;
  const _UserDialog({required this.actor, this.existing, required this.stores});
  @override
  State<_UserDialog> createState() => _UserDialogState();
}

class _UserDialogState extends State<_UserDialog> {
  final _form = GlobalKey<FormState>();
  late final _username = TextEditingController(text: widget.existing?.username ?? '');
  late final _fullName = TextEditingController(text: widget.existing?.fullName ?? '');
  late final _phone = TextEditingController(text: widget.existing?.phone ?? '');
  final _password = TextEditingController();
  late UserRole _role = widget.existing?.role ?? UserRole.user;
  late String _storeName = widget.existing?.storeName.isNotEmpty == true
      ? widget.existing!.storeName
      : (widget.stores.isNotEmpty ? widget.stores.first.name : 'DC TECH - Cửa hàng chính');
  late bool _active = widget.existing?.isActive ?? true;
  bool _obscure = true;
  bool _busy = false;
  String? _error;

  bool get _isEdit => widget.existing != null;

  /// Admin chỉ được đặt vai trò User; Super Admin đặt được tất cả.
  List<UserRole> get _roles =>
      widget.actor.role == UserRole.superAdmin ? UserRole.values : const [UserRole.user];

  @override
  void dispose() {
    _username.dispose();
    _fullName.dispose();
    _phone.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final provider = context.read<UserProvider>();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_isEdit) {
        var u = widget.existing!.copyWith(
          fullName: _fullName.text.trim(),
          phone: _phone.text.trim(),
          role: _role,
          storeName: _storeName,
          isActive: _active,
        );
        if (_password.text.isNotEmpty) {
          u = u.copyWith(
            passwordHash: PasswordHasher.hash(_password.text),
            mustChangePassword: true,
            resetRequested: '',
          );
        }
        await provider.update(u);
      } else {
        final id = await provider.nextId();
        await provider.create(AppUser(
          id: id,
          username: _username.text.trim().toLowerCase(),
          passwordHash: PasswordHasher.hash(_password.text),
          role: _role,
          fullName: _fullName.text.trim(),
          phone: _phone.text.trim(),
          storeName: _storeName,
          isActive: _active,
          mustChangePassword: true, // nhân viên tự đặt lại mật khẩu ở lần đăng nhập đầu
        ));
      }
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final storeItems = <String>{
      for (final s in widget.stores) s.name,
      _storeName,
    }.toList();

    return AlertDialog(
      backgroundColor: AppColors.surface,
      title: Text(_isEdit ? 'Sửa tài khoản' : 'Thêm tài khoản mới'),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Form(
            key: _form,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextFormField(
                controller: _username,
                enabled: !_isEdit, // không đổi tên đăng nhập sau khi tạo
                autocorrect: false,
                decoration: const InputDecoration(labelText: 'Tên đăng nhập', prefixIcon: Icon(Icons.alternate_email)),
                validator: (v) {
                  if (_isEdit) return null; // tên đăng nhập bị khóa khi sửa
                  final s = (v ?? '').trim();
                  if (!RegExp(r'^[a-zA-Z0-9._-]{3,}$').hasMatch(s)) {
                    return 'Tối thiểu 3 ký tự: chữ không dấu, số, . _ -';
                  }
                  final taken = context
                      .read<UserProvider>()
                      .users
                      .any((u) => u.username.toLowerCase() == s.toLowerCase());
                  return taken ? 'Tên đăng nhập đã tồn tại' : null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _fullName,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Họ và tên', prefixIcon: Icon(Icons.person_outline)),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Nhập họ và tên' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'Số điện thoại', prefixIcon: Icon(Icons.phone_outlined)),
                validator: (v) {
                  final s = (v ?? '').trim();
                  if (s.isEmpty) return null;
                  return RegExp(r'^(0|\+84)[0-9.\s]{8,13}$').hasMatch(s) ? null : 'Số điện thoại không hợp lệ';
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                // ignore: deprecated_member_use
                value: storeItems.contains(_storeName) ? _storeName : storeItems.first,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Cửa hàng đang thực hiện', prefixIcon: Icon(Icons.storefront)),
                items: [for (final s in storeItems) DropdownMenuItem(value: s, child: Text(s))],
                onChanged: (v) => setState(() => _storeName = v ?? _storeName),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<UserRole>(
                // ignore: deprecated_member_use
                value: _roles.contains(_role) ? _role : _roles.first,
                decoration: const InputDecoration(labelText: 'Vai trò', prefixIcon: Icon(Icons.badge_outlined)),
                items: [for (final r in _roles) DropdownMenuItem(value: r, child: Text(r.label))],
                onChanged: (v) => setState(() => _role = v ?? _role),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _password,
                obscureText: _obscure,
                decoration: InputDecoration(
                  labelText: _isEdit ? 'Mật khẩu mới (bỏ trống nếu không đổi)' : 'Mật khẩu (tối thiểu 6 ký tự)',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    icon: Icon(_obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
                validator: (v) {
                  final s = v ?? '';
                  if (_isEdit && s.isEmpty) return null;
                  return s.length < 6 ? 'Mật khẩu tối thiểu 6 ký tự' : null;
                },
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Đang hoạt động'),
                value: _active,
                activeThumbColor: AppColors.green,
                onChanged: (v) => setState(() => _active = v),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(_error!, style: const TextStyle(color: AppColors.red)),
                ),
            ]),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context, false), child: const Text('Hủy')),
        FilledButton(
          onPressed: _busy ? null : _save,
          style: FilledButton.styleFrom(minimumSize: const Size(100, 44)),
          child: _busy
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Lưu'),
        ),
      ],
    );
  }
}

/// Hiện mật khẩu tạm một lần sau khi reset.
class _TempPasswordDialog extends StatelessWidget {
  final String name;
  final String username;
  final String password;
  const _TempPasswordDialog({required this.name, required this.username, required this.password});

  @override
  Widget build(BuildContext context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Đã reset mật khẩu'),
        content: SizedBox(
          width: 380,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Tài khoản: $name (@$username)'),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.background.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.orange),
              ),
              child: SelectableText(
                password,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: 3, fontFamily: 'monospace'),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Mật khẩu này chỉ hiển thị MỘT LẦN. Hãy gửi cho nhân viên qua kênh riêng tư; '
              'họ sẽ phải đổi mật khẩu ngay khi đăng nhập.',
              style: TextStyle(color: AppColors.textMuted, height: 1.4),
            ),
          ]),
        ),
        actions: [
          TextButton.icon(
            onPressed: () => Clipboard.setData(ClipboardData(text: password)),
            icon: const Icon(Icons.copy, size: 18),
            label: const Text('Sao chép'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context),
            style: FilledButton.styleFrom(minimumSize: const Size(100, 44)),
            child: const Text('Đã ghi lại'),
          ),
        ],
      );
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/services/reminder_service.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/booking_provider.dart';
import '../../../providers/user_provider.dart';
import '../../widgets/change_password_dialog.dart';
import '../maintenance/photo_cleanup_screen.dart';
import '../service/service_catalog_screen.dart';
import '../users/user_management_screen.dart';
import 'api_config_screen.dart';
import 'store_catalog_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final user = auth.currentUser!;
    // Số nhân viên đang chờ được reset mật khẩu (hiện badge cho Admin)
    final pending = context.watch<UserProvider>().users.where((u) => u.resetRequested.isNotEmpty).length;

    Widget tile(IconData icon, String title, VoidCallback onTap, {Color? color, String? subtitle}) => Card(
          color: AppColors.surface,
          margin: const EdgeInsets.only(bottom: 10),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: ListTile(
            leading: Icon(icon, color: color ?? AppColors.orange),
            title: Text(title, style: TextStyle(color: color)),
            subtitle: subtitle == null ? null : Text(subtitle, style: const TextStyle(color: AppColors.orange)),
            trailing: const Icon(Icons.chevron_right),
            onTap: onTap,
          ),
        );

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('CÀI ĐẶT', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          const SizedBox(height: 14),
          Card(
            color: AppColors.surface,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: AppColors.orange,
                child: Text(user.displayName[0].toUpperCase()),
              ),
              title: Text(user.displayName, style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text('@${user.username}${user.storeName.isNotEmpty ? ' · ${user.storeName}' : ''}'),
              trailing: Chip(label: Text(user.role.label), side: BorderSide.none),
            ),
          ),
          const SizedBox(height: 14),
          const _ReminderCard(),
          const SizedBox(height: 4),
          if (user.role.canConfigureApi)
            tile(Icons.cloud_sync_outlined, 'Kết nối Google Sheets', () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const ApiConfigScreen()));
            }),
          if (user.role.canManageServices)
            tile(Icons.storefront_outlined, 'Danh mục cửa hàng', () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const StoreCatalogScreen()));
            }),
          if (user.role.canManageServices)
            tile(Icons.speaker_group_outlined, 'Danh mục dịch vụ', () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const ServiceCatalogScreen()));
            }),
          if (user.role.canManageUsers)
            tile(
              Icons.group_outlined,
              'Quản lý nhân viên',
              () => Navigator.push(context, MaterialPageRoute(builder: (_) => const UserManagementScreen())),
              subtitle: pending > 0 ? '$pending yêu cầu reset mật khẩu' : null,
            ),
          if (user.role.canManageUsers)
            tile(Icons.cleaning_services_outlined, 'Dọn ảnh cũ', () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const PhotoCleanupScreen()));
            }),
          tile(Icons.password_outlined, 'Đổi mật khẩu', () async {
            final ok = await showDialog<bool>(context: context, builder: (_) => const ChangePasswordDialog());
            if (ok == true && context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Đã đổi mật khẩu'), backgroundColor: AppColors.green));
            }
          }),
          tile(Icons.logout, 'Đăng xuất', () => context.read<AuthProvider>().logout(), color: AppColors.red),
        ],
      ),
    );
  }
}

/// Bật/tắt nhắc lịch giao / thu và chọn nhắc trước bao lâu (lưu riêng trên từng máy).
class _ReminderCard extends StatefulWidget {
  const _ReminderCard();
  @override
  State<_ReminderCard> createState() => _ReminderCardState();
}

class _ReminderCardState extends State<_ReminderCard> {
  final _svc = ReminderService.instance;

  Future<void> _apply({bool? enabled, int? lead}) async {
    final bookings = context.read<BookingProvider>().bookings;
    await _svc.configure(enabled: enabled, leadMinutes: lead, bookings: bookings);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    const leads = [15, 30, 60, 120];
    return Card(
      color: AppColors.surface,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 12, 12),
        child: Column(children: [
          SwitchListTile(
            secondary: const Icon(Icons.notifications_active_outlined, color: AppColors.orange),
            title: const Text('Nhắc lịch giao / thu loa'),
            subtitle: Text(
              ReminderService.supportsSystemNotifications
                  ? 'Thông báo chuẩn giờ giao / thu hồi, hiện cả khi đã tắt app.'
                  : 'Trên Windows, app nhắc ngay trong ứng dụng khi đang mở.',
              style: const TextStyle(fontSize: 12),
            ),
            value: _svc.enabled,
            activeThumbColor: AppColors.orange,
            onChanged: (v) => _apply(enabled: v),
          ),
          if (_svc.enabled) ...[
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: DropdownButtonFormField<int>(
                // ignore: deprecated_member_use
                value: leads.contains(_svc.leadMinutes) ? _svc.leadMinutes : 60,
                decoration: const InputDecoration(labelText: 'Nhắc trước'),
                items: [for (final m in leads) DropdownMenuItem(value: m, child: Text(m >= 60 ? '${m ~/ 60} giờ' : '$m phút'))],
                onChanged: (v) => _apply(lead: v),
              ),
            ),
            if (ReminderService.supportsSystemNotifications) ...[
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton.icon(
                    onPressed: () async {
                      await _svc.requestExactAlarmsPermission();
                    },
                    icon: const Icon(Icons.alarm_add, size: 18),
                    label: const Text('Cấp quyền Báo thức'),
                  ),
                  const SizedBox(width: 8),
                  TextButton.icon(
                    onPressed: () async {
                      await _svc.showTestNotification();
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Đã gửi thông báo thử nghiệm.'),
                            backgroundColor: AppColors.green,
                          ),
                        );
                      }
                    },
                    icon: const Icon(Icons.notifications_active, size: 18),
                    label: const Text('Thử ngay'),
                  ),
                ],
              ),
            ],
          ],
        ]),
      ),
    );
  }
}

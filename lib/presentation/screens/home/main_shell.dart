import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/services/reminder_service.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/booking_provider.dart';
import '../../widgets/change_password_dialog.dart';
import '../booking/add_booking_screen.dart';
import '../booking/booking_list_screen.dart';
import '../report/report_screen.dart';
import '../settings/settings_screen.dart';
import 'home_screen.dart';

class _TabDef {
  final String label;
  final IconData icon;
  final Widget page;
  const _TabDef(this.label, this.icon, this.page);
}

/// Khung chính: thanh menu dưới + nút "+" ở giữa.
/// Menu hiển thị theo quyền: User không thấy tab "Báo cáo".
class MainShell extends StatefulWidget {
  const MainShell({super.key});
  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;

  Timer? _timer;
  final Set<String> _notified = {}; // lời nhắc đã hiện (mỗi sự kiện chỉ nhắc 1 lần)

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _forceChangePasswordIfNeeded());
    // Android đã có thông báo hệ thống; các nền tảng khác nhắc ngay trong app mỗi phút
    if (!ReminderService.supportsSystemNotifications) {
      _timer = Timer.periodic(const Duration(minutes: 1), (_) => _checkReminders());
      Future.delayed(const Duration(seconds: 8), _checkReminders);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _checkReminders() {
    if (!mounted) return;
    final bookings = context.read<BookingProvider>().bookings;
    for (final r in ReminderService.instance.upcoming(bookings, DateTime.now())) {
      if (!_notified.add(r.key)) continue;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        duration: const Duration(seconds: 15),
        backgroundColor: AppColors.orange,
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(r.title, style: const TextStyle(fontWeight: FontWeight.w800, color: Colors.white)),
          Text(r.body, style: const TextStyle(color: Colors.white)),
        ]),
      ));
    }
  }

  /// Tài khoản mới / vừa được reset / mật khẩu mặc định -> bắt đổi mật khẩu ngay.
  Future<void> _forceChangePasswordIfNeeded() async {
    if (!mounted || context.read<AuthProvider>().currentUser?.mustChangePassword != true) return;
    await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const ChangePasswordDialog(forced: true),
    );
  }

  Future<void> _addBooking() => Navigator.push<bool>(
      context, MaterialPageRoute(builder: (_) => const AddBookingScreen()));

  @override
  Widget build(BuildContext context) {
    final role = context.watch<AuthProvider>().role;

    final tabs = <_TabDef>[
      const _TabDef('Trang chủ', Icons.home_rounded, HomeScreen()),
      const _TabDef('Đơn hàng', Icons.receipt_long_rounded, BookingListScreen()),
      if (role.canViewReports)
        const _TabDef('Báo cáo', Icons.insights_rounded, ReportScreen()),
      const _TabDef('Cài đặt', Icons.settings_rounded, SettingsScreen()),
    ];
    if (_index >= tabs.length) _index = 0;

    Widget item(int i) {
      final selected = i == _index;
      final color = selected ? AppColors.orange : AppColors.textMuted;
      return Expanded(
        child: InkWell(
          onTap: () => setState(() => _index = i),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(tabs[i].icon, color: color),
              Text(tabs[i].label, style: TextStyle(fontSize: 11, color: color)),
            ]),
          ),
        ),
      );
    }

    return Scaffold(
      // IndexedStack giữ state từng tab (không tải lại khi chuyển tab)
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: IndexedStack(index: _index, children: [for (final t in tabs) t.page]),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addBooking,
        backgroundColor: AppColors.orange,
        foregroundColor: Colors.white,
        shape: const CircleBorder(),
        tooltip: 'Thêm đơn hàng',
        child: const Icon(Icons.add, size: 30),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: BottomAppBar(
        color: AppColors.surface,
        shape: const CircularNotchedRectangle(),
        notchMargin: 6,
        padding: EdgeInsets.zero,
        child: Row(children: [
          item(0),
          item(1),
          const SizedBox(width: 72), // chừa chỗ cho nút +
          for (var i = 2; i < tabs.length; i++) item(i),
        ]),
      ),
    );
  }
}

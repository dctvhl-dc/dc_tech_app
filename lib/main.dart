import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/services/reminder_service.dart';
import 'core/theme/app_theme.dart';
import 'core/utils/local_config_storage.dart';
import 'data/services/google_sheets_service.dart';
import 'presentation/screens/auth/login_screen.dart';
import 'presentation/screens/home/main_shell.dart';
import 'presentation/screens/settings/api_config_screen.dart';
import 'presentation/widgets/app_logo.dart';
import 'providers/auth_provider.dart';
import 'providers/booking_provider.dart';
import 'providers/service_provider.dart';
import 'providers/user_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await ReminderService.instance.init(); // quyền thông báo + cấu hình nhắc lịch
  } catch (_) {}
  runApp(MultiProvider(
    providers: [
      ChangeNotifierProvider(create: (_) => AuthProvider()),
      ChangeNotifierProvider(create: (_) => BookingProvider()),
      ChangeNotifierProvider(create: (_) => ServiceProvider()),
      ChangeNotifierProvider(create: (_) => UserProvider()),
    ],
    child: MaterialApp(
      title: 'DC TECH',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      home: const _SessionKeeper(child: _Bootstrap()),
    ),
  ));
}

enum _Boot { loading, needConfig, error, ready }

/// Luồng khởi động:
///  chưa có cấu hình  -> ApiConfigScreen (thiết lập lần đầu)
///  có cấu hình       -> kết nối Sheets -> LoginScreen -> MainShell
class _Bootstrap extends StatefulWidget {
  const _Bootstrap();
  @override
  State<_Bootstrap> createState() => _BootstrapState();
}

class _BootstrapState extends State<_Bootstrap> {
  _Boot _status = _Boot.loading;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _connect();
  }

  Future<void> _connect() async {
    setState(() => _status = _Boot.loading);
    final cfg = await LocalConfigStorage.load();
    if (cfg.sheetId == null || cfg.credentials == null) {
      if (mounted) setState(() => _status = _Boot.needConfig);
      return;
    }
    try {
      await GoogleSheetsService.instance
          .init(credentialsJson: cfg.credentials!, spreadsheetId: cfg.sheetId!);
      if (!mounted) return;
      // Còn phiên trong 7 ngày -> vào thẳng app, không hiện màn hình đăng nhập
      await context.read<AuthProvider>().restoreSession();
      if (mounted) setState(() => _status = _Boot.ready);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _status = _Boot.error;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    switch (_status) {
      case _Boot.loading:
        return const Scaffold(
          body: Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              AppLogo(height: 90),
              SizedBox(height: 28),
              CircularProgressIndicator(),
            ]),
          ),
        );
      case _Boot.needConfig:
        return ApiConfigScreen(
          isInitialSetup: true,
          onConnected: () => setState(() => _status = _Boot.ready),
        );
      case _Boot.error:
        return Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.cloud_off, size: 56, color: AppColors.red),
                const SizedBox(height: 12),
                Text(_error, textAlign: TextAlign.center),
                const SizedBox(height: 20),
                FilledButton(onPressed: _connect, child: const Text('THỬ LẠI')),
                TextButton(
                  onPressed: () => setState(() => _status = _Boot.needConfig),
                  child: const Text('Cấu hình lại kết nối'),
                ),
              ]),
            ),
          ),
        );
      case _Boot.ready:
        return Consumer<AuthProvider>(
          builder: (context, auth, child) => auth.isLoggedIn ? const MainShell() : const LoginScreen(),
        );
    }
  }
}

/// Giữ phiên đăng nhập "sống": ghi lại thời điểm sử dụng cuối mỗi 5 phút và mỗi khi
/// app mở lại / ra nền. Nhờ vậy phiên 7 ngày tính từ lần dùng cuối, không phải từ lúc đăng nhập.
class _SessionKeeper extends StatefulWidget {
  final Widget child;
  const _SessionKeeper({required this.child});
  @override
  State<_SessionKeeper> createState() => _SessionKeeperState();
}

class _SessionKeeperState extends State<_SessionKeeper> with WidgetsBindingObserver {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer.periodic(const Duration(minutes: 5), (_) => _touch());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  void _touch() {
    if (mounted) context.read<AuthProvider>().touchSession();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) => _touch();

  @override
  Widget build(BuildContext context) => widget.child;
}

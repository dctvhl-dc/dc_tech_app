import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/map_link.dart';
import '../../../core/utils/report_calculator.dart';
import '../../../core/utils/schedule_utils.dart';
import '../../../data/models/booking_model.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/booking_provider.dart';
import '../../widgets/app_logo.dart';
import '../booking/add_booking_screen.dart';
import '../debt/debt_list_screen.dart';

/// Trang chủ: tổng quan hôm nay + danh sách việc cần làm (giao / thu hồi) kèm gọi điện, mở bản đồ.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _showDelivery = true;

  bool get _isMobile => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _reload());
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: AppColors.red));
  }

  Future<void> _reload() async {
    final user = context.read<AuthProvider>().currentUser;
    if (user == null) return;
    try {
      await context.read<BookingProvider>().load(user);
    } catch (e) {
      _snack('Không tải được dữ liệu: $e');
    }
  }

  /// Bấm vào việc cần làm -> mở form đơn với trạng thái mới + phần chụp ảnh.
  void _open(TaskItem t) => Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => AddBookingScreen(
            booking: t.booking,
            presetStatus: t.isDelivery ? BookingStatus.delivered : BookingStatus.returned,
          ),
        ),
      );

  Color _labelColor(String label) => switch (label) {
        'Quá giờ' => AppColors.red,
        'Chuẩn bị' => AppColors.orange,
        _ => AppColors.blue,
      };

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().currentUser!;
    final all = context.watch<BookingProvider>().bookings;
    final now = DateTime.now();

    // Tổng quan HÔM NAY: các đơn có ngày giao (ghi nhận doanh thu) là hôm nay
    final today = all.where((b) => ScheduleUtils.sameDay(ReportCalculator.recordDate(b), now)).toList();
    final s = ReportCalculator.summarize(today);
    // Công nợ còn tồn của TẤT CẢ đơn trong phạm vi của bạn (không chỉ hôm nay) — để biết còn phải đòi
    final debtAll = all.fold<int>(0, (sum, b) => sum + (b.debtAmount > 0 ? b.debtAmount : 0));
    final isStaff = !user.role.canSeeAllBookings;

    final deliveries = ScheduleUtils.deliveries(all, now);
    final collections = ScheduleUtils.collections(all, now);
    final list = _showDelivery ? deliveries : collections;

    return SafeArea(
      child: RefreshIndicator(
        onRefresh: _reload,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
          children: [
            // ── Đầu trang ──
            Row(children: [
              const AppLogo(height: 40),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('DC TECH', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
                  Text('Quản lý thuê loa', style: TextStyle(color: AppColors.textMuted)),
                ]),
              ),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(user.displayName, style: const TextStyle(fontWeight: FontWeight.w700)),
                Chip(
                  label: Text(user.role.label, style: const TextStyle(fontSize: 11, color: Colors.white)),
                  backgroundColor: AppColors.orange,
                  visualDensity: VisualDensity.compact,
                  side: BorderSide.none,
                ),
              ]),
            ]),
            const SizedBox(height: 16),

            // ── Tổng quan hôm nay ──
            _panel(
              title: isStaff ? 'HÔM NAY CỦA BẠN' : 'TỔNG QUAN HÔM NAY',
              trailing: '${today.length} đơn',
              child: Row(children: [
                _Stat('Doanh thu', s.revenue, AppColors.blue, Icons.trending_up, caption: 'hôm nay'),
                const SizedBox(width: 10),
                _Stat(
                  'Công nợ',
                  debtAll,
                  AppColors.red,
                  Icons.warning_amber_rounded,
                  caption: 'còn thu · bấm xem',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => DebtListScreen(
                        title: 'Đơn còn công nợ',
                        select: (all) => all.where((b) => b.debtAmount > 0).toList(),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                _Stat('Đã thu nộp', s.submitted, AppColors.green, Icons.payments_outlined, caption: 'hôm nay'),
              ]),
            ),
            const SizedBox(height: 14),

            // ── Danh sách cần làm ──
            _panel(
              title: 'Danh sách cần làm hôm nay',
              trailing: '(${deliveries.length + collections.length})',
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                _tabs(deliveries.length, collections.length),
                const SizedBox(height: 12),
                if (list.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 28),
                    child: Center(
                      child: Text(
                        _showDelivery ? 'Không có đơn nào cần giao hôm nay' : 'Không có đơn nào cần thu hồi hôm nay',
                        style: const TextStyle(color: AppColors.textMuted),
                      ),
                    ),
                  )
                else
                  for (final t in list) _taskCard(t, now),
              ]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _panel({required String title, required String trailing, required Widget child}) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(child: Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800))),
            Text(trailing, style: const TextStyle(color: AppColors.textMuted)),
          ]),
          const SizedBox(height: 12),
          child,
        ]),
      );

  Widget _tabs(int nDelivery, int nCollect) {
    Widget tab(String label, int n, bool selected, VoidCallback onTap) => Expanded(
          child: GestureDetector(
            onTap: onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(vertical: 11),
              decoration: BoxDecoration(
                color: selected ? AppColors.orange : Colors.transparent,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text('$label ($n)',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontWeight: FontWeight.w700, color: selected ? Colors.white : AppColors.textMuted)),
            ),
          ),
        );
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(18)),
      child: Row(children: [
        tab('Cần giao', nDelivery, _showDelivery, () => setState(() => _showDelivery = true)),
        tab('Cần thu', nCollect, !_showDelivery, () => setState(() => _showDelivery = false)),
      ]),
    );
  }

  Widget _taskCard(TaskItem t, DateTime now) {
    final b = t.booking;
    final label = t.statusLabel(now);
    final color = _labelColor(label);
    final isToday = ScheduleUtils.sameDay(t.time, now);
    final hm = '${t.time.hour.toString().padLeft(2, '0')}:${t.time.minute.toString().padLeft(2, '0')}';
    final when = isToday ? hm : '$hm · ${t.time.day.toString().padLeft(2, '0')}/${t.time.month.toString().padLeft(2, '0')}';
    final services = b.services.map((x) => x.qty > 1 ? '${x.name} ×${x.qty}' : x.name).join(' + ');
    final hasMap = b.mapLink.isNotEmpty || b.gpsLocation.isNotEmpty;

    return Container(
      key: ValueKey('${b.id}-${t.isDelivery ? 'giao' : 'thu'}'),
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppColors.field.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(16),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _open(t),
        child: IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(width: 5, color: color),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('KH: ${b.customerName}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                  Text(b.customerPhone, style: const TextStyle(color: AppColors.textMuted)),
                  const SizedBox(height: 2),
                  Text(services),
                  const SizedBox(height: 6),
                  Row(children: [
                    const Icon(Icons.schedule, size: 18, color: AppColors.textMuted),
                    const SizedBox(width: 6),
                    Text(when),
                    Container(width: 1, height: 14, margin: const EdgeInsets.symmetric(horizontal: 8), color: AppColors.textMuted),
                    Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w700)),
                  ]),
                ]),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                if (_isMobile)
                  _circleButton(Icons.phone, AppColors.green, 'Gọi khách', () async {
                    if (!await MapLink.call(b.customerPhone)) _snack('Không mở được ứng dụng gọi điện.');
                  }),
                if (hasMap)
                  _circleButton(Icons.location_on, AppColors.orange, 'Mở bản đồ', () async {
                    if (!await MapLink.open(link: b.mapLink, gps: b.gpsLocation)) _snack('Không mở được bản đồ.');
                  }),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _circleButton(IconData icon, Color color, String tooltip, VoidCallback onTap) => Padding(
        padding: const EdgeInsets.only(left: 6),
        child: Material(
          color: AppColors.field.withValues(alpha: 0.8),
          shape: const CircleBorder(),
          child: IconButton(tooltip: tooltip, icon: Icon(icon, color: color), onPressed: onTap),
        ),
      );
}

class _Stat extends StatelessWidget {
  final String label;
  final int value;
  final Color color;
  final IconData icon;
  final String? caption;
  final VoidCallback? onTap;
  const _Stat(this.label, this.value, this.color, this.icon, {this.caption, this.onTap});

  @override
  Widget build(BuildContext context) => Expanded(
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: color, width: onTap != null ? 2 : 1.2),
            ),
            child: Column(children: [
              Icon(icon, color: color, size: 28),
              const SizedBox(height: 6),
              Text(label, style: const TextStyle(fontSize: 12)),
              const SizedBox(height: 2),
              FittedBox(
                child: Text(Fmt.money(value), style: const TextStyle(fontWeight: FontWeight.w800)),
              ),
              if (caption != null)
                Text(caption!, style: const TextStyle(fontSize: 10, color: AppColors.textMuted)),
            ]),
          ),
        ),
      );
}

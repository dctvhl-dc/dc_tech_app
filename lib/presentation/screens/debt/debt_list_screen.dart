import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/map_link.dart';
import '../../../core/utils/report_calculator.dart';
import '../../../data/models/booking_model.dart';
import '../../../providers/booking_provider.dart';
import '../../../providers/user_provider.dart';
import '../booking/add_booking_screen.dart';

/// Danh sách các đơn còn công nợ (bấm vào ô "Công nợ" ở Trang chủ / Báo cáo).
class DebtListScreen extends StatefulWidget {
  final String title;
  final List<Booking> Function(List<Booking> all) select;
  const DebtListScreen({super.key, required this.title, required this.select});

  @override
  State<DebtListScreen> createState() => _DebtListScreenState();
}

class _DebtListScreenState extends State<DebtListScreen> {
  final _search = TextEditingController();

  bool get _isMobile => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  static int _debt(Booking b) => b.debtAmount > 0 ? b.debtAmount : 0;

  @override
  Widget build(BuildContext context) {
    final all = context.watch<BookingProvider>().bookings;
    final names = {for (final u in context.watch<UserProvider>().users) u.username: u.displayName};

    // Chỉ giữ đơn thực sự còn nợ, đơn cũ nhất lên đầu (cần đòi trước)
    final base = widget.select(all).where((b) => _debt(b) > 0).toList()
      ..sort((a, b) => ReportCalculator.recordDate(a).compareTo(ReportCalculator.recordDate(b)));
    final q = _search.text.trim().toLowerCase();
    final list = q.isEmpty
        ? base
        : base
            .where((b) =>
                b.customerName.toLowerCase().contains(q) ||
                b.customerPhone.contains(q) ||
                b.id.toLowerCase().contains(q))
            .toList();
    final total = list.fold<int>(0, (s, b) => s + _debt(b));

    return Scaffold(
      appBar: AppBar(title: Text(widget.title.toUpperCase(), style: const TextStyle(fontSize: 18))),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Column(children: [
            Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.orange.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.orange),
              ),
              child: Row(children: [
                const Icon(Icons.warning_amber_rounded, color: AppColors.orange, size: 30),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${list.length} đơn còn công nợ', style: const TextStyle(fontWeight: FontWeight.w700)),
                    Text('Tổng còn phải thu: ${Fmt.money(total)}',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.orange)),
                  ]),
                ),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: TextField(
                controller: _search,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(hintText: 'Tìm khách hàng, SĐT, mã đơn...', prefixIcon: Icon(Icons.search)),
              ),
            ),
            Expanded(
              child: list.isEmpty
                  ? const Center(child: Text('Không có đơn nào còn công nợ', style: TextStyle(color: AppColors.textMuted)))
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                      itemCount: list.length,
                      findChildIndexCallback: (key) {
                        final id = (key as ValueKey<String>).value;
                        final i = list.indexWhere((b) => b.id == id);
                        return i < 0 ? null : i;
                      },
                      itemBuilder: (_, i) => KeyedSubtree(key: ValueKey(list[i].id), child: _card(list[i], names)),
                    ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _card(Booking b, Map<String, String> names) {
    final d = ReportCalculator.recordDate(b);
    return Card(
      color: AppColors.surface,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => Navigator.push<bool>(
            context, MaterialPageRoute(builder: (_) => AddBookingScreen(booking: b))),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                child: Text('#${b.id} · ${b.customerName}',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              ),
              if (_isMobile)
                IconButton(
                  tooltip: 'Gọi khách',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.phone, color: AppColors.green),
                  onPressed: () => MapLink.call(b.customerPhone),
                ),
            ]),
            Text('${b.customerPhone} · Giao ${Fmt.dateTime(d)}', style: const TextStyle(color: AppColors.textMuted)),
            Text('NV: ${names[b.assignedUser] ?? b.assignedUser}',
                style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
            const SizedBox(height: 8),
            Row(children: [
              _amount('Tổng', b.totalCost, Colors.white),
              _amount('Đã thu', b.paidAmount, AppColors.green),
              _amount('Còn nợ', _debt(b), AppColors.orange, bold: true),
            ]),
          ]),
        ),
      ),
    );
  }

  Widget _amount(String label, int value, Color color, {bool bold = false}) => Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(Fmt.money(value),
                style: TextStyle(color: color, fontWeight: bold ? FontWeight.w800 : FontWeight.w600)),
          ),
        ]),
      );
}

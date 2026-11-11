import 'dart:io';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/report_calculator.dart';
import '../../../core/utils/report_exporter.dart';
import '../../../data/models/booking_model.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/booking_provider.dart';
import '../../../providers/user_provider.dart';
import '../debt/debt_list_screen.dart';

/// Báo cáo doanh thu theo Tháng / Quý / Năm và theo nhân viên.
class ReportScreen extends StatefulWidget {
  const ReportScreen({super.key});
  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  static final _now = DateTime.now();
  PeriodType _type = PeriodType.month;
  int _year = _now.year;
  int _month = _now.month;
  int _quarter = ((_now.month - 1) ~/ 3) + 1;
  String? _username; // null = tất cả nhân viên
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final users = context.read<UserProvider>();
      if (users.users.isEmpty) users.load().catchError((_) {});
    });
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: error ? AppColors.red : AppColors.green));
  }

  /// Xuất báo cáo kỳ đang xem ra file Excel (.xlsx) gồm 3 sheet.
  Future<void> _export(ReportPeriod period, ReportSummary s, List<UserStat> ranking,
      List<Booking> bookings, Map<String, String> names) async {
    final userLabel = _username == null ? 'Tất cả nhân viên' : (names[_username] ?? _username!);
    final bytes = ReportExporter.build(
      period: period,
      userLabel: userLabel,
      summary: s,
      ranking: ranking,
      bookings: bookings,
      names: names,
    );
    final tag = period.label.replaceAll('/', '-').replaceAll(' ', '');
    final fileName = 'BaoCao_$tag${_username == null ? '' : '_$_username'}.xlsx';
    try {
      String? path;
      if (kIsWeb || Platform.isAndroid || Platform.isIOS) {
        // Mobile / Web: file_picker tự ghi bytes hoặc tải xuống qua browser
        path = await FilePicker.platform
            .saveFile(dialogTitle: 'Lưu báo cáo', fileName: fileName, bytes: bytes);
      } else {
        // Windows/macOS/Linux: chỉ trả về đường dẫn, ta tự ghi file
        path = await FilePicker.platform.saveFile(
          dialogTitle: 'Lưu báo cáo',
          fileName: fileName,
          type: FileType.custom,
          allowedExtensions: ['xlsx'],
        );
        if (path != null) {
          if (!path.toLowerCase().endsWith('.xlsx')) path = '$path.xlsx';
          await File(path).writeAsBytes(bytes);
        }
      }
      if (path != null) _snack('Đã lưu báo cáo: $path');
    } catch (e) {
      _snack('Xuất báo cáo thất bại: $e', error: true);
    }
  }

  Future<void> _reload() async {
    final user = context.read<AuthProvider>().currentUser;
    if (user == null) return;
    setState(() => _refreshing = true);
    try {
      await context.read<BookingProvider>().load(user);
      if (!mounted) return;
      await context.read<UserProvider>().load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Không tải được dữ liệu: $e'), backgroundColor: AppColors.red));
      }
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bookings = context.watch<BookingProvider>().bookings;
    final users = context.watch<UserProvider>().users;
    final names = {for (final u in users) u.username: u.displayName};

    // Danh sách năm & nhân viên để chọn
    final years = <int>{_now.year, _year, ...bookings.map((b) => ReportCalculator.recordDate(b).year)}.toList()
      ..sort((a, b) => b.compareTo(a));
    final userOptions = <String>{
      ...names.keys,
      ...bookings.map((b) => b.assignedUser).where((u) => u.isNotEmpty),
      ?_username,
    }.toList();

    final period = ReportPeriod(_type, _year, _type == PeriodType.month ? _month : _quarter);
    final selected = ReportCalculator.filter(bookings, period, username: _username);
    final s = ReportCalculator.summarize(selected);
    final ranking = ReportCalculator.rankByUser(selected);

    return SafeArea(
      child: RefreshIndicator(
        onRefresh: _reload,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
          children: [
            Row(children: [
              const Expanded(
                child: Text('BÁO CÁO DOANH THU', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
              ),
              IconButton(
                tooltip: 'Xuất Excel',
                onPressed: s.count == 0 ? null : () => _export(period, s, ranking, selected, names),
                icon: const Icon(Icons.download_outlined),
              ),
              IconButton(
                tooltip: 'Tải lại dữ liệu',
                onPressed: _refreshing ? null : _reload,
                icon: _refreshing
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.refresh),
              ),
            ]),
            const SizedBox(height: 8),
            SegmentedButton<PeriodType>(
              segments: const [
                ButtonSegment(value: PeriodType.month, label: Text('Tháng')),
                ButtonSegment(value: PeriodType.quarter, label: Text('Quý')),
                ButtonSegment(value: PeriodType.year, label: Text('Năm')),
              ],
              selected: {_type},
              onSelectionChanged: (v) => setState(() => _type = v.first),
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: _dropdown<int>(
                  label: 'Năm',
                  value: _year,
                  items: [for (final y in years) DropdownMenuItem(value: y, child: Text('$y'))],
                  onChanged: (v) => setState(() => _year = v ?? _year),
                ),
              ),
              if (_type == PeriodType.month) ...[
                const SizedBox(width: 10),
                Expanded(
                  child: _dropdown<int>(
                    label: 'Tháng',
                    value: _month,
                    items: [for (var m = 1; m <= 12; m++) DropdownMenuItem(value: m, child: Text('Tháng $m'))],
                    onChanged: (v) => setState(() => _month = v ?? _month),
                  ),
                ),
              ],
              if (_type == PeriodType.quarter) ...[
                const SizedBox(width: 10),
                Expanded(
                  child: _dropdown<int>(
                    label: 'Quý',
                    value: _quarter,
                    items: [for (var q = 1; q <= 4; q++) DropdownMenuItem(value: q, child: Text('Quý $q'))],
                    onChanged: (v) => setState(() => _quarter = v ?? _quarter),
                  ),
                ),
              ],
            ]),
            const SizedBox(height: 10),
            _dropdown<String?>(
              label: 'Nhân viên',
              value: _username,
              items: [
                const DropdownMenuItem<String?>(value: null, child: Text('Tất cả nhân viên')),
                for (final u in userOptions) DropdownMenuItem<String?>(value: u, child: Text(names[u] ?? u)),
              ],
              onChanged: (v) => setState(() => _username = v),
            ),
            const SizedBox(height: 6),
            Text(
              '${period.label} · ${s.count} đơn · tính theo ngày giao (hoặc ngày tạo nếu chưa có)',
              style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
            ),
            const SizedBox(height: 14),
            Row(children: [
              _Stat('Doanh thu', s.revenue, AppColors.blue, Icons.trending_up),
              const SizedBox(width: 10),
              _Stat('Đã thu', s.paid, AppColors.green, Icons.payments_outlined),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              _Stat(
                'Công nợ',
                s.debt,
                AppColors.orange,
                Icons.warning_amber_rounded,
                caption: 'xem công nợ',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => DebtListScreen(
                      title: 'Công nợ · ${period.label}',
                      select: (all) => ReportCalculator.filter(all, period, username: _username)
                          .where((b) => b.debtAmount > 0)
                          .toList(),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              _Stat('Đã nộp cty', s.submitted, AppColors.green, Icons.account_balance_outlined),
            ]),
            const SizedBox(height: 18),
            _card('CƠ CẤU DOANH THU', [
              Center(
                child: SizedBox(
                  width: 220,
                  height: 220,
                  child: CustomPaint(
                    painter: _DonutPainter(
                      [s.submitted.toDouble(), s.holding.toDouble(), s.debt.toDouble()],
                      const [AppColors.green, AppColors.blue, AppColors.orange],
                    ),
                    child: Center(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        const Text('Tổng cộng', style: TextStyle(color: AppColors.textMuted)),
                        const SizedBox(height: 2),
                        Text(Fmt.money(s.revenue), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                      ]),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Wrap(spacing: 16, runSpacing: 8, alignment: WrapAlignment.center, children: [
                _Legend(AppColors.green, 'Đã nộp cty', s.submitted),
                _Legend(AppColors.blue, 'NV đang giữ (chưa nộp)', s.holding),
                _Legend(AppColors.orange, 'Công nợ (chưa thu)', s.debt),
              ]),
            ]),
            const SizedBox(height: 18),
            _card('THỐNG KÊ NHÂN VIÊN & GIAO/THU LOA', [
              if (ranking.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Center(child: Text('Chưa có đơn trong kỳ này', style: TextStyle(color: AppColors.textMuted))),
                ),
              for (var i = 0; i < ranking.length; i++) _rankRow(i, ranking[i], names),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _dropdown<T>({
    required String label,
    required T value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
  }) =>
      DropdownButtonFormField<T>(
        // ignore: deprecated_member_use
        value: value,
        isExpanded: true,
        decoration: InputDecoration(labelText: label),
        items: items,
        onChanged: onChanged,
      );

  Widget _card(String title, List<Widget> children) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          const SizedBox(height: 14),
          ...children,
        ]),
      );

  Widget _rankRow(int i, UserStat u, Map<String, String> names) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.background.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(children: [
          SizedBox(
            width: 32,
            child: i == 0
                ? const Icon(Icons.emoji_events, color: Color(0xFFFFC107))
                : Text('${i + 1}.', style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(names[u.username] ?? u.username, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              const SizedBox(height: 2),
              Text('${u.count} đơn · Nợ: ${Fmt.money(u.debt)}',
                  style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
              const SizedBox(height: 4),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.blue.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      'Giao: ${u.deliveryCount} lần',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.blue),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.green.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      'Thu: ${u.collectionCount} lần',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.green),
                    ),
                  ),
                ],
              ),
            ]),
          ),
          Text(Fmt.money(u.revenue), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
        ]),
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
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: color, width: onTap != null ? 2 : 1.2),
            ),
            child: Row(children: [
              Icon(icon, color: color, size: 28),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(label, style: const TextStyle(fontSize: 12)),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(Fmt.money(value), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                  ),
                  if (caption != null)
                    Text(caption!, style: TextStyle(fontSize: 10, color: color))
                  else if (onTap != null)
                    Text('Bấm xem đơn', style: TextStyle(fontSize: 10, color: color)),
                ]),
              ),
            ]),
          ),
        ),
      );
}

class _Legend extends StatelessWidget {
  final Color color;
  final String label;
  final int value;
  const _Legend(this.color, this.label, this.value);

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text('$label: ', style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
        Text(Fmt.money(value), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
      ]);
}

/// Biểu đồ vành khuyên tự vẽ.
class _DonutPainter extends CustomPainter {
  final List<double> values;
  final List<Color> colors;
  _DonutPainter(this.values, this.colors);

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width * 0.13;
    final rect = (Offset.zero & size).deflate(stroke / 2);
    final total = values.fold<double>(0, (a, b) => a + b);

    if (total <= 0) {
      canvas.drawArc(
        rect, 0, math.pi * 2, false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..color = Colors.white.withValues(alpha: 0.1),
      );
      return;
    }

    final visible = values.where((v) => v > 0).length;
    final gap = visible > 1 ? 0.04 : 0.0;
    var start = -math.pi / 2;
    for (var i = 0; i < values.length; i++) {
      if (values[i] <= 0) continue;
      final sweep = values[i] / total * math.pi * 2;
      canvas.drawArc(
        rect, start + gap / 2, math.max(sweep - gap, 0.01), false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..color = colors[i],
      );
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter old) => true;
}

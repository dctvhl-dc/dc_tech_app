import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/map_link.dart';
import '../../../core/utils/report_calculator.dart';
import '../../../core/utils/slip_renderer.dart';
import '../../../data/models/booking_model.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/booking_provider.dart';
import '../../../providers/user_provider.dart';
import '../slip/slip_screen.dart';
import 'add_booking_screen.dart';

/// Danh sách đơn: tìm kiếm, lọc trạng thái, bấm để sửa, nút nhanh Giao/Thu/Hủy đơn.
class BookingListScreen extends StatefulWidget {
  const BookingListScreen({super.key});
  @override
  State<BookingListScreen> createState() => _BookingListScreenState();
}

class _BookingListScreenState extends State<BookingListScreen> {
  final _search = TextEditingController();
  BookingStatus? _filter; // null = tất cả

  static const int _defaultDays = 30;
  DateTimeRange? _range; // null = mặc định 30 ngày gần đây
  bool _debtOnly = false; // chỉ đơn còn công nợ
  String? _staff; // lọc theo nhân viên (Admin)

  DateTime get _defaultStart {
    final n = DateTime.now();
    return DateTime(
      n.year,
      n.month,
      n.day,
    ).subtract(const Duration(days: _defaultDays));
  }

  bool get _advancedActive => _range != null || _debtOnly || _staff != null;

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
      SnackBar(content: Text(msg), backgroundColor: error ? AppColors.red : AppColors.green),
    );
  }

  Future<void> _reload() async {
    final user = context.read<AuthProvider>().currentUser;
    if (user == null) return;
    try {
      await context.read<BookingProvider>().load(user);
    } catch (e) {
      _snack('Không tải được danh sách đơn: $e');
    }
  }

  bool get _isMobile => Platform.isAndroid || Platform.isIOS;

  Future<void> _openMap(Booking b) async {
    if (!await MapLink.open(link: b.mapLink, gps: b.gpsLocation)) {
      _snack('Không mở được bản đồ.');
    }
  }

  Future<void> _call(Booking b) async {
    if (!await MapLink.call(b.customerPhone)) {
      _snack('Không mở được ứng dụng gọi điện.');
    }
  }

  void _openSlip(Booking b, SlipKind k) => Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => SlipScreen(booking: b, kind: k),
    ),
  );

  void _openForStatus(Booking b) => Navigator.push<bool>(
    context,
    MaterialPageRoute(
      builder: (_) => AddBookingScreen(
        booking: b,
        presetStatus: b.status == BookingStatus.pending
            ? BookingStatus.delivered
            : BookingStatus.returned,
      ),
    ),
  );

  /// Thao tác Hủy đơn trực tiếp từ thẻ đơn hàng.
  Future<void> _cancelBookingDialog(Booking b) async {
    if (b.status != BookingStatus.pending) {
      _snack('Chỉ có thể hủy đơn hàng chưa giao.');
      return;
    }

    final reasonCtrl = TextEditingController();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Row(
          children: [
            Icon(Icons.cancel_outlined, color: AppColors.red),
            SizedBox(width: 8),
            Text('Hủy đơn hàng'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Bạn có chắc chắn muốn hủy đơn hàng #${b.id}?'),
            const SizedBox(height: 12),
            TextField(
              controller: reasonCtrl,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Lý do hủy đơn',
                hintText: 'Nhập lý do khách hủy / trùng lịch...',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Quay lại')),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.red),
            child: const Text('Xác nhận Hủy'),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;
    final reason = reasonCtrl.text.trim();
    if (reason.isEmpty) {
      _snack('Vui lòng nhập lý do hủy đơn');
      return;
    }

    final auth = context.read<AuthProvider>();
    final provider = context.read<BookingProvider>();
    try {
      await provider.cancelBooking(b, reason, auth.currentUser!.username);
      _snack('Đã hủy đơn hàng #${b.id}', error: false);
    } catch (e) {
      _snack('Hủy đơn thất bại: $e');
    }
  }

  Color _statusColor(BookingStatus s) => switch (s) {
    BookingStatus.pending => AppColors.orange,
    BookingStatus.delivered => AppColors.blue,
    BookingStatus.returned => AppColors.green,
    BookingStatus.cancelled => AppColors.red,
  };

  @override
  Widget build(BuildContext context) {
    final p = context.watch<BookingProvider>();
    final q = _search.text.trim().toLowerCase();
    final start = _range?.start ?? _defaultStart;
    final end = _range == null
        ? null
        : DateTime(
            _range!.end.year,
            _range!.end.month,
            _range!.end.day,
            23,
            59,
            59,
          );
    final list = p.bookings.where((b) {
      final d = ReportCalculator.recordDate(b);
      if (d.isBefore(start) || (end != null && d.isAfter(end))) return false;
      if (_filter != null && b.status != _filter) return false;
      if (_debtOnly && b.debtAmount <= 0) return false;
      if (_staff != null && b.assignedUser != _staff) return false;
      if (q.isEmpty) return true;
      return b.customerName.toLowerCase().contains(q) ||
          b.customerPhone.contains(q) ||
          b.id.toLowerCase().contains(q);
    }).toList();

    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'DANH SÁCH ĐƠN HÀNG',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _search,
                        onChanged: (_) => setState(() {}),
                        decoration: const InputDecoration(
                          hintText: 'Tìm khách hàng, SĐT, mã đơn...',
                          prefixIcon: Icon(Icons.search),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      tooltip: 'Tìm nâng cao (khoảng thời gian...)',
                      onPressed: _openAdvanced,
                      style: IconButton.styleFrom(
                        backgroundColor: _advancedActive
                            ? AppColors.orange
                            : AppColors.field,
                        fixedSize: const Size(54, 54),
                      ),
                      icon: Icon(
                        _advancedActive ? Icons.filter_alt : Icons.tune,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _chip('Tất cả', null),
                      for (final s in BookingStatus.values) _chip(s.label, s),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                _rangeInfo(list.length),
              ],
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _reload,
              child: p.loading && p.bookings.isEmpty
                  ? const Center(child: CircularProgressIndicator())
                  : list.isEmpty
                  ? ListView(
                      children: [
                        const SizedBox(height: 120),
                        Center(
                          child: Text(
                            _advancedActive ||
                                    _filter != null ||
                                    _search.text.isNotEmpty
                                ? 'Không có đơn nào khớp bộ lọc'
                                : 'Không có đơn nào trong 30 ngày gần đây',
                            style: const TextStyle(color: AppColors.textMuted),
                          ),
                        ),
                      ],
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 90),
                      itemCount: list.length,
                      findChildIndexCallback: (key) {
                        final id = (key as ValueKey<String>).value;
                        final index = list.indexWhere((b) => b.id == id);
                        return index < 0 ? null : index;
                      },
                      itemBuilder: (_, i) => KeyedSubtree(
                        key: ValueKey(list[i].id),
                        child: _card(list[i]),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  static String _d(DateTime x) =>
      '${x.day.toString().padLeft(2, '0')}/${x.month.toString().padLeft(2, '0')}/${x.year}';

  Widget _rangeInfo(int count) {
    final text = _range == null
        ? '30 ngày gần đây (từ ${_d(_defaultStart)}) · $count đơn'
        : (_range!.start.year <= 2000
              ? 'Tất cả thời gian · $count đơn'
              : '${_d(_range!.start)} – ${_d(_range!.end)} · $count đơn');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                text,
                style: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 12,
                ),
              ),
            ),
            if (_advancedActive)
              TextButton(
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: () => setState(() {
                  _range = null;
                  _debtOnly = false;
                  _staff = null;
                }),
                child: const Text('Đặt lại'),
              ),
          ],
        ),
        if (_range == null)
          const Text(
            'Muốn xem đơn cũ hơn: bấm nút lọc bên cạnh ô tìm kiếm để chọn khoảng thời gian.',
            style: TextStyle(color: AppColors.textMuted, fontSize: 11),
          ),
      ],
    );
  }

  Future<void> _openAdvanced() async {
    final canPickStaff = context.read<AuthProvider>().role.canSeeAllBookings;
    final res = await showModalBottomSheet<_AdvancedFilter>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      builder: (_) => _AdvancedFilterSheet(
        initial: _AdvancedFilter(_range, _debtOnly, _staff),
        showStaff: canPickStaff,
      ),
    );
    if (res != null) {
      setState(() {
        _range = res.range;
        _debtOnly = res.debtOnly;
        _staff = res.staff;
      });
    }
  }

  Widget _chip(String label, BookingStatus? value) => Padding(
    padding: const EdgeInsets.only(right: 8),
    child: ChoiceChip(
      label: Text(label),
      selected: _filter == value,
      selectedColor: AppColors.orange,
      onSelected: (_) => setState(() => _filter = value),
    ),
  );

  Widget _card(Booking b) {
    final color = _statusColor(b.status);
    final services = b.services
        .map((s) => s.qty > 1 ? '${s.name} ×${s.qty}' : s.name)
        .join(', ');
    final isCancelled = b.status == BookingStatus.cancelled;

    return Card(
      color: AppColors.surface,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => Navigator.push<bool>(
          context,
          MaterialPageRoute(builder: (_) => AddBookingScreen(booking: b)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Mã: #${b.id}',
                      style: TextStyle(
                        color: isCancelled ? AppColors.red : AppColors.blue,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      b.status.label,
                      style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const Divider(height: 18),
              _row(
                Icons.person_outline,
                'Khách: ${b.customerName} - ${b.customerPhone}',
              ),
              _row(Icons.speaker_outlined, 'Dịch vụ: $services'),
              _row(
                Icons.event_outlined,
                'Hạn thu: ${Fmt.dateTime(b.collectTime)}',
              ),
              if (isCancelled && b.cancelReason.isNotEmpty) ...[
                const SizedBox(height: 2),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.cancel_outlined, size: 20, color: AppColors.red),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Lý do hủy: ${b.cancelReason}',
                        style: const TextStyle(color: AppColors.red, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ] else if (!isCancelled) ...[
                Row(
                  children: [
                    const Icon(
                      Icons.account_balance_wallet_outlined,
                      size: 20,
                      color: AppColors.textMuted,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text:
                                  'Công nợ: ${Fmt.money(b.debtAmount < 0 ? 0 : b.debtAmount)} / ',
                            ),
                            TextSpan(
                              text: b.pendingToCompany > 0
                                  ? 'Chưa nộp cty ${Fmt.money(b.pendingToCompany)}'
                                  : 'Đã nộp cty',
                              style: TextStyle(
                                color: b.pendingToCompany > 0
                                    ? AppColors.orange
                                    : AppColors.green,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 6),
              Row(
                children: [
                  if (b.mapLink.isNotEmpty || b.gpsLocation.isNotEmpty)
                    IconButton(
                      tooltip: 'Mở bản đồ',
                      icon: const Icon(
                        Icons.location_on,
                        color: AppColors.orange,
                      ),
                      onPressed: () => _openMap(b),
                    ),
                  if (_isMobile)
                    IconButton(
                      tooltip: 'Gọi khách',
                      icon: const Icon(Icons.phone, color: AppColors.green),
                      onPressed: () => _call(b),
                    ),
                  IconButton(
                    tooltip: 'Sao chép đơn này',
                    icon: const Icon(
                      Icons.copy_outlined,
                      color: AppColors.blue,
                    ),
                    onPressed: () => Navigator.push<bool>(
                      context,
                      MaterialPageRoute(
                        builder: (_) => AddBookingScreen(copyFrom: b),
                      ),
                    ),
                  ),
                  PopupMenuButton<SlipKind>(
                    tooltip: 'In phiếu',
                    icon: const Icon(
                      Icons.print_outlined,
                      color: AppColors.textMuted,
                    ),
                    onSelected: (k) => _openSlip(b, k),
                    itemBuilder: (_) => [
                      for (final k in SlipKind.values)
                        PopupMenuItem(value: k, child: Text(k.label)),
                    ],
                  ),
                  const Spacer(),
                  if (b.status == BookingStatus.pending) ...[
                    IconButton(
                      tooltip: 'Hủy đơn hàng',
                      icon: const Icon(Icons.cancel_outlined, color: AppColors.red),
                      onPressed: () => _cancelBookingDialog(b),
                    ),
                    const SizedBox(width: 4),
                    FilledButton.tonalIcon(
                      onPressed: () => _openForStatus(b),
                      icon: const Icon(Icons.photo_camera_outlined, size: 18),
                      label: const Text('Giao loa'),
                    ),
                  ] else if (b.status == BookingStatus.delivered)
                    FilledButton.tonalIcon(
                      onPressed: () => _openForStatus(b),
                      icon: const Icon(Icons.photo_camera_outlined, size: 18),
                      label: const Text('Thu loa'),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(IconData icon, String text) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(
      children: [
        Icon(icon, size: 20, color: AppColors.textMuted),
        const SizedBox(width: 8),
        Expanded(child: Text(text)),
      ],
    ),
  );
}

class _AdvancedFilter {
  final DateTimeRange? range;
  final bool debtOnly;
  final String? staff;
  const _AdvancedFilter(this.range, this.debtOnly, this.staff);
}

/// Tìm nâng cao: chọn khoảng thời gian, chỉ đơn còn nợ, nhân viên.
class _AdvancedFilterSheet extends StatefulWidget {
  final _AdvancedFilter initial;
  final bool showStaff;
  const _AdvancedFilterSheet({required this.initial, required this.showStaff});
  @override
  State<_AdvancedFilterSheet> createState() => _AdvancedFilterSheetState();
}

class _AdvancedFilterSheetState extends State<_AdvancedFilterSheet> {
  late DateTimeRange? _range = widget.initial.range;
  late bool _debtOnly = widget.initial.debtOnly;
  late String? _staff = widget.initial.staff;

  static DateTime get _today {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  static String _d(DateTime x) =>
      '${x.day.toString().padLeft(2, '0')}/${x.month.toString().padLeft(2, '0')}/${x.year}';

  void _lastMonths(int months) {
    final t = _today;
    setState(
      () => _range = DateTimeRange(
        start: DateTime(t.year, t.month - months, t.day),
        end: t,
      ),
    );
  }

  Future<void> _pick() async {
    final now = DateTime.now();
    final r = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(now.year + 3),
      initialDateRange: (_range != null && _range!.start.year > 2000)
          ? _range
          : null,
    );
    if (r != null) setState(() => _range = r);
  }

  @override
  Widget build(BuildContext context) {
    final users = context.read<UserProvider>().users;
    final label = _range == null
        ? 'Chọn khoảng thời gian'
        : (_range!.start.year <= 2000
              ? 'Tất cả thời gian'
              : '${_d(_range!.start)} – ${_d(_range!.end)}');

    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        16,
        16,
        16 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Tìm kiếm nâng cao',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            const Text(
              'Mặc định danh sách chỉ hiện đơn 30 ngày gần đây. Chọn khoảng thời gian (theo ngày giao) để xem đơn cũ hơn.',
              style: TextStyle(color: AppColors.textMuted, height: 1.4),
            ),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: _pick,
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
                shape: const StadiumBorder(),
              ),
              icon: const Icon(Icons.date_range),
              label: Text(label),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                ActionChip(
                  label: const Text('3 tháng'),
                  onPressed: () => _lastMonths(3),
                ),
                ActionChip(
                  label: const Text('6 tháng'),
                  onPressed: () => _lastMonths(6),
                ),
                ActionChip(
                  label: const Text('1 năm'),
                  onPressed: () => _lastMonths(12),
                ),
                ActionChip(
                  label: const Text('Tất cả'),
                  onPressed: () => setState(
                    () => _range = DateTimeRange(
                      start: DateTime(2000),
                      end: _today,
                    ),
                  ),
                ),
              ],
            ),
            if (widget.showStaff) ...[
              const SizedBox(height: 14),
              DropdownButtonFormField<String?>(
                // ignore: deprecated_member_use
                value: _staff,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Nhân viên phụ trách',
                  prefixIcon: Icon(Icons.badge_outlined),
                ),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('Tất cả nhân viên'),
                  ),
                  for (final u in users)
                    DropdownMenuItem<String?>(
                      value: u.username,
                      child: Text(u.displayName),
                    ),
                ],
                onChanged: (v) => setState(() => _staff = v),
              ),
            ],
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Chỉ đơn còn công nợ'),
              value: _debtOnly,
              activeThumbColor: AppColors.orange,
              onChanged: (v) => setState(() => _debtOnly = v),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.pop(
                      context,
                      const _AdvancedFilter(null, false, null),
                    ),
                    child: const Text('Đặt lại (30 ngày)'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.pop(
                      context,
                      _AdvancedFilter(_range, _debtOnly, _staff),
                    ),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 48),
                    ),
                    child: const Text('Áp dụng'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

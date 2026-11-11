import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/availability_checker.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/map_link.dart';
import '../../../core/utils/slip_renderer.dart';
import '../../../data/models/booking_model.dart';
import '../../../data/models/photo_model.dart';
import '../../../data/models/service_model.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/booking_provider.dart';
import '../../../providers/service_provider.dart';
import '../../../providers/user_provider.dart';
import '../slip/slip_screen.dart';

/// Màn hình Tạo / Sửa đơn hàng.
class AddBookingScreen extends StatefulWidget {
  final Booking? booking;
  final Booking? copyFrom;
  final BookingStatus? presetStatus;
  const AddBookingScreen({super.key, this.booking, this.copyFrom, this.presetStatus})
      : assert(booking == null || copyFrom == null);

  @override
  State<AddBookingScreen> createState() => _AddBookingScreenState();
}

/// Controller cho 1 dòng dịch vụ (tên + số lượng + đơn giá).
class _ServiceLine {
  final TextEditingController name;
  final TextEditingController price; // đơn giá 1 đơn vị
  final TextEditingController qty;
  String? serviceId; // mã trong danh mục (null = nhập tay)
  _ServiceLine({String n = '', int p = 0, int q = 1, this.serviceId})
      : name = TextEditingController(text: n),
        price = TextEditingController(text: p == 0 ? '' : Fmt.thousands(p)),
        qty = TextEditingController(text: '$q');

  int get qtyValue {
    final v = int.tryParse(qty.text.trim()) ?? 1;
    return v < 1 ? 1 : v;
  }

  void dispose() {
    name.dispose();
    price.dispose();
    qty.dispose();
  }
}

class _AddBookingScreenState extends State<AddBookingScreen> {
  final _formKey = GlobalKey<FormState>();
  final _photoKey = GlobalKey();

  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _address = TextEditingController();
  final _mapLink = TextEditingController();
  final _gps = TextEditingController();
  final _note = TextEditingController();
  final _invoiceInfo = TextEditingController();
  final _cancelReason = TextEditingController();
  final _total = TextEditingController();
  final _paid = TextEditingController();
  final _submitted = TextEditingController();
  final List<_ServiceLine> _lines = [];

  DateTime? _serviceTime, _installTime, _collectTime;
  bool _requireInvoice = false;
  bool _totalManual = false; // true khi người dùng tự sửa tổng -> ngừng auto cộng
  bool _resolving = false;
  bool _saving = false;
  BookingStatus _status = BookingStatus.pending;
  String? _assignedUser;

  Booking? _saved; // đơn mới vừa lưu (để lần Lưu sau là cập nhật, không tạo trùng)
  final List<BookingPhoto> _photos = []; // ảnh đã lưu trên Sheet
  final List<BookingPhoto> _pending = []; // ảnh vừa chụp, chưa tải lên
  bool _photosLoading = false;

  bool get _isEdit => widget.booking != null;
  bool get _isCopy => widget.copyFrom != null;
  bool get _canCapture => Platform.isAndroid || Platform.isIOS;

  /// Công nợ = Tổng - Đã thanh toán (tính realtime, chỉ hiển thị, không nhập).
  int get _debt => _status == BookingStatus.cancelled ? 0 : Fmt.parseMoney(_total.text) - Fmt.parseMoney(_paid.text);

  @override
  void initState() {
    super.initState();
    final b = widget.booking ?? widget.copyFrom;
    final auth = context.read<AuthProvider>();

    if (b != null) {
      _name.text = b.customerName;
      _phone.text = b.customerPhone;
      _address.text = b.locationText;
      _mapLink.text = b.mapLink;
      _gps.text = b.gpsLocation;
      _note.text = b.note;
      _invoiceInfo.text = b.invoiceInfo;
      _cancelReason.text = b.cancelReason;
      _total.text = b.totalCost == 0 ? '' : Fmt.thousands(b.totalCost);
      _paid.text = b.paidAmount == 0 ? '' : Fmt.thousands(b.paidAmount);
      _submitted.text = b.submittedToCompany == 0 ? '' : Fmt.thousands(b.submittedToCompany);
      _serviceTime = b.serviceTime;
      _installTime = b.installTime;
      _collectTime = b.collectTime;
      _requireInvoice = b.requireInvoice;
      _status = widget.presetStatus ?? b.status;
      _totalManual = true; // đơn cũ: giữ nguyên tổng đã lưu
      _lines.addAll(b.services.map((s) => _ServiceLine(n: s.name, p: s.price, q: s.qty, serviceId: s.serviceId)));
    }
    if (_lines.isEmpty) _lines.add(_ServiceLine());

    // User thường: đơn luôn gán cho chính mình
    _assignedUser = b?.assignedUser ?? auth.currentUser?.username;

    // Công nợ cập nhật realtime khi gõ
    _total.addListener(_refresh);
    _paid.addListener(_refresh);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ServiceProvider>().load();
      if (auth.role.canSeeAllBookings) context.read<UserProvider>().load();
      _loadPhotos();
      // Bấm "Giao loa" / "Thu loa" từ danh sách -> cuộn tới phần chụp ảnh
      if (widget.presetStatus != null && _photoKey.currentContext != null) {
        Scrollable.ensureVisible(_photoKey.currentContext!, duration: const Duration(milliseconds: 400));
      }
    });
  }

  @override
  void dispose() {
    for (final c in [_name, _phone, _address, _mapLink, _gps, _note, _invoiceInfo, _cancelReason, _total, _paid, _submitted]) {
      c.dispose();
    }
    for (final l in _lines) {
      l.dispose();
    }
    super.dispose();
  }

  void _refresh() => setState(() {});

  /// Tự cộng giá các dịch vụ vào "Tổng chi phí" (trừ khi user đã tự sửa tổng).
  void _recalcTotal() {
    if (_totalManual) return;
    final sum = _lines.fold<int>(0, (s, l) => s + Fmt.parseMoney(l.price.text) * l.qtyValue);
    _total.text = sum == 0 ? '' : Fmt.thousands(sum);
  }

  // ───────────────────────── Actions ─────────────────────────

  void _snack(String msg, {bool error = true}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? AppColors.red : AppColors.green,
    ));
  }

  Future<DateTime?> _pickDateTime(DateTime? current) async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: current ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 3),
    );
    if (d == null || !mounted) return null;
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(current ?? now),
    );
    if (t == null) return null;
    return DateTime(d.year, d.month, d.day, t.hour, t.minute);
  }

  // ───── Link Google Maps của khách ─────

  Future<void> _pasteLink() async {
    final data = await Clipboard.getData('text/plain');
    final text = data?.text?.trim();
    if (text == null || text.isEmpty) return;
    _mapLink.text = MapLink.extractUrl(text) ?? text;
    setState(() {});
    await _extractCoords();
  }

  /// Từ link khách gửi -> toạ độ.
  Future<void> _extractCoords() async {
    final raw = _mapLink.text.trim();
    if (raw.isEmpty) {
      _snack('Hãy dán link Google Maps của khách trước.');
      return;
    }
    setState(() => _resolving = true);
    try {
      final c = await MapLink.toCoords(raw);
      if (c == null) {
        _snack('Không đọc được toạ độ từ link này. Bấm "Mở bản đồ" để kiểm tra.');
      } else {
        _gps.text = c.text;
        _snack('Đã lấy toạ độ khách: ${c.text}', error: false);
      }
    } catch (e) {
      _snack('Không truy cập được link: $e');
    } finally {
      if (mounted) setState(() => _resolving = false);
    }
  }

  Future<void> _openMap() async {
    final ok = await MapLink.open(link: _mapLink.text, gps: _gps.text);
    if (!ok) _snack('Chưa có link hoặc toạ độ để mở bản đồ.');
  }

  // ───── Ảnh giao / thu hồi ─────

  Future<void> _loadPhotos() async {
    final b = widget.booking;
    if (b == null) return;
    setState(() => _photosLoading = true);
    try {
      final list = await context.read<BookingProvider>().loadPhotos(b.id);
      if (!mounted) return;
      setState(() {
        _photos
          ..clear()
          ..addAll(list);
      });
    } catch (e) {
      _snack('Không tải được ảnh: $e');
    } finally {
      if (mounted) setState(() => _photosLoading = false);
    }
  }

  Future<void> _addPhoto(PhotoType type, ImageSource source) async {
    final user = context.read<AuthProvider>().currentUser!;
    try {
      final x = await ImagePicker().pickImage(
        source: source,
        maxWidth: 640,
        maxHeight: 640,
        imageQuality: 50,
      );
      if (x == null) return;
      final bytes = await x.readAsBytes();
      if (bytes.length > 200 * 1024) {
        _snack('Ảnh quá lớn (${bytes.length ~/ 1024} KB). Hãy chụp lại.');
        return;
      }
      if (!mounted) return;
      setState(() => _pending.add(BookingPhoto(
            id: 'P${DateTime.now().microsecondsSinceEpoch}',
            bookingId: '',
            type: type,
            takenAt: DateTime.now(),
            takenBy: user.username,
            bytes: bytes,
          )));
    } catch (e) {
      _snack('Không mở được camera / thư viện ảnh: $e');
    }
  }

  Future<void> _deleteSaved(BookingPhoto p) async {
    final provider = context.read<BookingProvider>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Xóa ảnh?'),
        content: const Text('Ảnh sẽ bị xóa khỏi đơn hàng.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Hủy')),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.red, minimumSize: const Size(90, 44)),
            child: const Text('Xóa'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await provider.deletePhoto(p.id);
      if (!mounted) return;
      setState(() => _photos.remove(p));
    } catch (e) {
      _snack('Xóa ảnh thất bại: $e');
    }
  }

  void _viewPhoto(BookingPhoto p) => showDialog<void>(
        context: context,
        builder: (_) => Dialog(
          backgroundColor: Colors.black,
          insetPadding: const EdgeInsets.all(12),
          child: Stack(children: [
            InteractiveViewer(child: Center(child: Image.memory(p.bytes))),
            Positioned(
              top: 4,
              right: 4,
              child: IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
            ),
          ]),
        ),
      );

  // ───── Kiểm tra trùng lịch / tồn kho ─────

  List<BookingServiceItem> _currentServices() => _lines
      .where((l) => l.name.text.trim().isNotEmpty)
      .map((l) => BookingServiceItem(
            name: l.name.text.trim(),
            price: Fmt.parseMoney(l.price.text),
            qty: l.qtyValue,
            serviceId: l.serviceId,
          ))
      .toList();

  Future<List<StockConflict>> _findConflicts(List<BookingServiceItem> lines, BookingProvider provider) async {
    final start = _installTime, end = _collectTime;
    if (start == null || end == null) return [];
    final catalog = context.read<ServiceProvider>();
    await catalog.load();
    final all = await provider.fetchAll();
    return AvailabilityChecker.check(
      start: start,
      end: end,
      lines: lines,
      all: all,
      catalog: catalog.services,
      excludeBookingId: (widget.booking ?? _saved)?.id,
    );
  }

  Future<bool> _confirmStock(List<BookingServiceItem> lines, BookingProvider provider) async {
    if (_status == BookingStatus.cancelled) return true; // Đơn hủy không cần check kho
    List<StockConflict> conflicts;
    try {
      conflicts = await _findConflicts(lines, provider);
    } catch (e) {
      _snack('Không kiểm tra được trùng lịch thiết bị (bỏ qua): $e');
      return true;
    }
    if (conflicts.isEmpty || !mounted) return true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Row(children: [
          Icon(Icons.warning_amber_rounded, color: AppColors.orange),
          SizedBox(width: 8),
          Expanded(child: Text('Trùng lịch / thiếu thiết bị')),
        ]),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Trong khoảng thời gian giao → thu hồi của đơn này:'),
              const SizedBox(height: 10),
              for (final c in conflicts)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(
                    '• ${c.service.name}: có ${c.capacity}, đang được giữ ${c.alreadyUsed}'
                    '${c.bookingIds.isEmpty ? '' : ' (${c.bookingIds.map((i) => '#$i').join(', ')})'}. '
                    'Đơn này cần ${c.needed}, còn trống ${c.available}.',
                    style: const TextStyle(height: 1.4),
                  ),
                ),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Quay lại sửa')),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.red, minimumSize: const Size(110, 44)),
            child: const Text('Vẫn lưu'),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _checkStockNow() async {
    final services = _currentServices();
    if (services.isEmpty) return _snack('Hãy nhập dịch vụ trước.');
    if (_installTime == null || _collectTime == null) return _snack('Hãy chọn thời gian giao và thu hồi trước.');
    try {
      final c = await _findConflicts(services, context.read<BookingProvider>());
      _snack(
        c.isEmpty
            ? 'Thiết bị còn đủ trong khoảng thời gian này.'
            : 'Có ${c.length} thiết bị bị trùng lịch: ${c.map((x) => x.service.name).join(', ')}.',
        error: c.isNotEmpty,
      );
    } catch (e) {
      _snack('Không kiểm tra được: $e');
    }
  }

  void _openSlip(SlipKind kind) {
    final b = widget.booking ?? _saved;
    if (b == null) return;
    Navigator.push(context, MaterialPageRoute(builder: (_) => SlipScreen(booking: b, kind: kind)));
  }

  // ───── Thao tác Hủy đơn hàng ─────

  Future<void> _cancelBookingAction() async {
    final b = widget.booking ?? _saved;
    if (b == null) return;
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
    setState(() => _saving = true);
    try {
      await provider.cancelBooking(b, reason, auth.currentUser!.username);
      if (!mounted) return;
      _snack('Đã hủy đơn hàng #${b.id}', error: false);
      Navigator.pop(context, true);
    } catch (e) {
      _snack('Hủy đơn thất bại: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ───── Lưu ─────

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final services = _currentServices();
    if (services.isEmpty) return _snack('Vui lòng nhập ít nhất 1 dịch vụ');
    if (_installTime == null) return _snack('Vui lòng chọn thời gian giao');
    if (_collectTime == null) return _snack('Vui lòng chọn thời gian thu hồi');
    if (_collectTime!.isBefore(_installTime!)) {
      return _snack('Thời gian thu hồi phải sau thời gian giao');
    }

    if (_status == BookingStatus.cancelled && _cancelReason.text.trim().isEmpty) {
      return _snack('Vui lòng nhập lý do hủy đơn');
    }

    final total = Fmt.parseMoney(_total.text);
    final paid = Fmt.parseMoney(_paid.text);
    final submitted = Fmt.parseMoney(_submitted.text);

    final auth = context.read<AuthProvider>();
    final provider = context.read<BookingProvider>();
    setState(() => _saving = true);

    Booking? booking;
    try {
      if (!await _confirmStock(services, provider)) {
        if (mounted) setState(() => _saving = false);
        return;
      }

      if (_mapLink.text.trim().isNotEmpty && _gps.text.trim().isEmpty) {
        try {
          final c = await MapLink.toCoords(_mapLink.text).timeout(const Duration(seconds: 12));
          if (c != null) _gps.text = c.text;
        } catch (_) {}
      }

      final old = widget.booking ?? _saved;
      booking = Booking(
        id: old?.id ?? await provider.nextId(),
        createdAt: old?.createdAt ?? DateTime.now(),
        customerName: _name.text.trim(),
        customerPhone: _phone.text.trim(),
        services: services,
        serviceTime: _serviceTime,
        installTime: _installTime,
        collectTime: _collectTime,
        locationText: _address.text.trim(),
        gpsLocation: _gps.text.trim(),
        mapLink: _mapLink.text.trim(),
        note: _note.text.trim(),
        totalCost: total,
        paidAmount: paid,
        submittedToCompany: submitted,
        requireInvoice: _requireInvoice,
        invoiceInfo: _requireInvoice ? _invoiceInfo.text.trim() : '',
        status: _status,
        assignedUser: _assignedUser ?? auth.currentUser!.username,
        createdBy: old == null ? auth.currentUser!.username : old.createdBy,
        updatedBy: auth.currentUser!.username,
        updatedAt: DateTime.now(),
        cancelReason: _cancelReason.text.trim(),
      );
      await provider.save(booking, isNew: old == null);
      _saved = booking;
    } catch (e) {
      _snack('Lưu thất bại: $e');
      if (mounted) setState(() => _saving = false);
      return;
    }

    try {
      for (final p in List<BookingPhoto>.from(_pending)) {
        final uploaded = p.withBooking(booking.id);
        await provider.addPhoto(uploaded);
        if (!mounted) return;
        setState(() {
          _pending.remove(p);
          _photos.add(uploaded);
        });
      }
    } catch (e) {
      _snack('Đã lưu đơn ${booking.id} nhưng tải ảnh thất bại: $e');
      if (mounted) setState(() => _saving = false);
      return;
    }

    if (!mounted) return;
    _snack('Đã lưu đơn ${booking.id}', error: false);
    Navigator.pop(context, true);
  }

  // ───────────────────────── UI ─────────────────────────

  @override
  Widget build(BuildContext context) {
    final catalog = context.watch<ServiceProvider>().activeServices;
    final canAssign = context.watch<AuthProvider>().role.canSeeAllBookings;

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'SỬA ĐƠN HÀNG' : _isCopy ? 'SAO CHÉP ĐƠN HÀNG' : 'THÊM ĐƠN HÀNG MỚI'),
        actions: [
          if (widget.booking != null || _saved != null)
            PopupMenuButton<SlipKind>(
              icon: const Icon(Icons.print_outlined),
              tooltip: 'In phiếu (theo dữ liệu đã lưu)',
              onSelected: _openSlip,
              itemBuilder: (_) => [for (final k in SlipKind.values) PopupMenuItem(value: k, child: Text(k.label))],
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            if (_status == BookingStatus.cancelled)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.red.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.red),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.cancel_outlined, color: AppColors.red, size: 20),
                        SizedBox(width: 8),
                        Text('ĐƠN HÀNG ĐÃ HỦY', style: TextStyle(color: AppColors.red, fontWeight: FontWeight.w800)),
                      ],
                    ),
                    if (_cancelReason.text.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text('Lý do hủy: ${_cancelReason.text}', style: const TextStyle(color: Colors.white, height: 1.3)),
                    ],
                  ],
                ),
              ),
            if (_isCopy)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.orange.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'Đang sao chép đơn #${widget.copyFrom!.id}. Thông tin đơn có thể chỉnh sửa.',
                  style: const TextStyle(height: 1.4),
                ),
              ),
            _section('THÔNG TIN KHÁCH HÀNG', [
              TextFormField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Họ và tên', prefixIcon: Icon(Icons.person_outline)),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Nhập tên khách hàng' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9+]'))],
                decoration: const InputDecoration(labelText: 'Số điện thoại', prefixIcon: Icon(Icons.phone_outlined)),
                validator: (v) => RegExp(r'^(0|\+84)\d{9,10}$').hasMatch(v?.trim() ?? '')
                    ? null
                    : 'Số điện thoại không hợp lệ',
              ),
            ]),

            _section('DỊCH VỤ', [
              for (var i = 0; i < _lines.length; i++) _serviceRow(i, catalog),
              Row(children: [
                TextButton.icon(
                  onPressed: () => setState(() => _lines.add(_ServiceLine())),
                  icon: const Icon(Icons.add),
                  label: const Text('Thêm dịch vụ'),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: _checkStockNow,
                  icon: const Icon(Icons.fact_check_outlined),
                  label: const Text('Kiểm tra lịch'),
                ),
              ]),
            ]),

            _section('THỜI GIAN & ĐỊA ĐIỂM', [
              _timeTile('Thời gian sử dụng (tuỳ chọn)', _serviceTime, (d) => _serviceTime = d),
              _timeTile('Thời gian giao', _installTime, (d) => _installTime = d),
              _timeTile('Thời gian thu hồi', _collectTime, (d) => _collectTime = d),
              const SizedBox(height: 12),
              TextFormField(
                controller: _address,
                maxLines: 2,
                decoration: const InputDecoration(labelText: 'Địa chỉ', prefixIcon: Icon(Icons.location_on_outlined)),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Nhập địa chỉ giao loa' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _mapLink,
                keyboardType: TextInputType.url,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: 'Link Google Maps khách gửi',
                  prefixIcon: const Icon(Icons.link),
                  suffixIcon: IconButton(
                    tooltip: 'Dán từ clipboard và lấy toạ độ',
                    icon: const Icon(Icons.content_paste),
                    onPressed: _pasteLink,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _resolving ? null : _extractCoords,
                    style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
                    icon: _resolving
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.my_location),
                    label: const Text('Lấy toạ độ', style: TextStyle(fontSize: 14)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: (_mapLink.text.trim().isEmpty && _gps.text.trim().isEmpty) ? null : _openMap,
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 48),
                      foregroundColor: AppColors.orange,
                      side: const BorderSide(color: AppColors.orange),
                      shape: const StadiumBorder(),
                    ),
                    icon: const Icon(Icons.map_outlined),
                    label: const Text('Mở bản đồ', style: TextStyle(fontSize: 14)),
                  ),
                ),
              ]),
              if (_gps.text.trim().isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Row(children: [
                    const Icon(Icons.pin_drop_outlined, size: 20, color: AppColors.green),
                    const SizedBox(width: 8),
                    Expanded(child: SelectableText('Toạ độ khách: ${_gps.text}')),
                  ]),
                ),
            ]),

            _section('TÀI CHÍNH', [
              _moneyField(_total, 'Tổng chi phí', onUserEdit: () => _totalManual = true, required: true),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: _moneyField(_paid, 'Đã thanh toán')),
                const SizedBox(width: 12),
                Expanded(child: _moneyField(_submitted, 'Đã nộp cty')),
              ]),
              const SizedBox(height: 12),
              _debtTile(),
            ]),

            _section('GHI CHÚ ĐƠN HÀNG', [
              TextFormField(
                controller: _note,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Ghi chú',
                  hintText: 'Nội dung cần lưu ý cho đơn hàng',
                  prefixIcon: Icon(Icons.notes_outlined),
                  alignLabelWithHint: true,
                ),
              ),
            ]),

            _section('HOÁ ĐƠN', [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Yêu cầu xuất hoá đơn'),
                value: _requireInvoice,
                activeThumbColor: AppColors.orange,
                onChanged: (v) => setState(() => _requireInvoice = v),
              ),
              if (_requireInvoice)
                TextFormField(
                  controller: _invoiceInfo,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: 'Thông tin xuất hoá đơn (MST, tên cty, địa chỉ, email)'),
                  validator: (v) => (_requireInvoice && (v == null || v.trim().isEmpty))
                      ? 'Nhập thông tin xuất hoá đơn'
                      : null,
                ),
            ]),

            KeyedSubtree(
              key: _photoKey,
              child: _section('ẢNH GIAO & THU HỒI LOA', [
                if (widget.presetStatus != null)
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.orange.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      widget.presetStatus == BookingStatus.delivered
                          ? 'Chụp ảnh loa đã giao tại nhà khách, rồi bấm LƯU ĐƠN HÀNG để chuyển sang "Đã giao loa".'
                          : 'Chụp ảnh loa khi thu hồi, rồi bấm LƯU ĐƠN HÀNG để chuyển sang "Đã trả loa".',
                      style: const TextStyle(height: 1.4),
                    ),
                  ),
                if (_photosLoading) const LinearProgressIndicator(),
                _photoGroup(PhotoType.delivery),
                const SizedBox(height: 16),
                _photoGroup(PhotoType.returned),
              ]),
            ),

            _section('QUẢN LÝ ĐƠN', [
              if (_isEdit || _isCopy)
                DropdownButtonFormField<BookingStatus>(
                  // ignore: deprecated_member_use
                  value: _status,
                  decoration: const InputDecoration(labelText: 'Trạng thái'),
                  items: [for (final s in BookingStatus.values) DropdownMenuItem(value: s, child: Text(s.label))],
                  onChanged: (v) => setState(() => _status = v ?? _status),
                ),
              if (_status == BookingStatus.cancelled) ...[
                const SizedBox(height: 12),
                TextFormField(
                  controller: _cancelReason,
                  decoration: const InputDecoration(
                    labelText: 'Lý do hủy đơn',
                    prefixIcon: Icon(Icons.cancel_outlined, color: AppColors.red),
                  ),
                ),
              ],
              if ((_isEdit || _isCopy) && canAssign) const SizedBox(height: 12),
              if (canAssign) _assigneeDropdown(),
              if ((_isEdit || _saved != null) && _status == BookingStatus.pending) ...[
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: _saving ? null : _cancelBookingAction,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.red,
                    side: const BorderSide(color: AppColors.red),
                    minimumSize: const Size.fromHeight(48),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  icon: const Icon(Icons.cancel_outlined),
                  label: const Text('HỦY ĐƠN HÀNG NÀY', style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ],
            ]),

            const SizedBox(height: 12),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                  : const Text('LƯU ĐƠN HÀNG'),
            ),
          ],
        ),
      ),
    );
  }

  // ───────────────────────── Widget con ─────────────────────────

  Widget _section(String title, List<Widget> children) => Padding(
        padding: const EdgeInsets.only(top: 18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          ),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
          ),
        ]),
      );

  Widget _photoGroup(PhotoType type) {
    final saved = _photos.where((p) => p.type == type).toList();
    final pending = _pending.where((p) => p.type == type).toList();
    final total = saved.length + pending.length;
    final me = context.read<AuthProvider>().currentUser!;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('${type.label}  ($total/$kMaxPhotosPerType)', style: const TextStyle(fontWeight: FontWeight.w700)),
      const SizedBox(height: 8),
      Wrap(spacing: 10, runSpacing: 10, children: [
        for (final p in saved)
          _thumb(p, pending: false, canDelete: me.role.canSeeAllBookings || p.takenBy == me.username),
        for (final p in pending) _thumb(p, pending: true, canDelete: true),
        if (total < kMaxPhotosPerType && _canCapture) _addTile(type),
      ]),
      if (!_canCapture && total == 0)
        const Padding(
          padding: EdgeInsets.only(top: 4),
          child: Text('Chưa có ảnh. Ảnh được chụp bằng ứng dụng trên điện thoại.',
              style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
        ),
    ]);
  }

  Widget _thumb(BookingPhoto p, {required bool pending, required bool canDelete}) => SizedBox(
        width: 92,
        child: Column(children: [
          Stack(children: [
            GestureDetector(
              onTap: () => _viewPhoto(p),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.memory(p.bytes, width: 92, height: 92, fit: BoxFit.cover, gaplessPlayback: true),
              ),
            ),
            if (pending)
              Positioned(
                left: 4,
                bottom: 4,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: AppColors.orange, borderRadius: BorderRadius.circular(8)),
                  child: const Text('Chưa lưu', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700)),
                ),
              ),
            if (canDelete)
              Positioned(
                right: 2,
                top: 2,
                child: InkWell(
                  onTap: () => pending ? setState(() => _pending.remove(p)) : _deleteSaved(p),
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                    child: const Icon(Icons.close, size: 16),
                  ),
                ),
              ),
          ]),
          const SizedBox(height: 3),
          Text(Fmt.dateTime(p.takenAt).split(' - ').first,
              style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
        ]),
      );

  Widget _addTile(PhotoType type) => PopupMenuButton<ImageSource>(
        tooltip: 'Thêm ảnh',
        onSelected: (s) => _addPhoto(type, s),
        itemBuilder: (_) => const [
          PopupMenuItem(
            value: ImageSource.camera,
            child: Row(children: [Icon(Icons.photo_camera_outlined), SizedBox(width: 10), Text('Chụp ảnh')]),
          ),
          PopupMenuItem(
            value: ImageSource.gallery,
            child: Row(children: [Icon(Icons.photo_library_outlined), SizedBox(width: 10), Text('Chọn từ thư viện')]),
          ),
        ],
        child: Container(
          width: 92,
          height: 92,
          decoration: BoxDecoration(
            color: AppColors.orange.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.orange, width: 1.5),
          ),
          child: const Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.add_a_photo_outlined, color: AppColors.orange, size: 30),
            SizedBox(height: 4),
            Text('Thêm ảnh', style: TextStyle(fontSize: 12, color: AppColors.orange)),
          ]),
        ),
      );

  Widget _serviceRow(int i, List<RentalService> catalog) {
    final line = _lines[i];
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          flex: 3,
          child: TextFormField(
            controller: line.name,
            onChanged: (_) => line.serviceId = null,
            decoration: InputDecoration(
              labelText: 'Thiết bị / dịch vụ',
              suffixIcon: PopupMenuButton<RentalService>(
                tooltip: 'Chọn từ danh mục',
                icon: const Icon(Icons.arrow_drop_down),
                enabled: catalog.isNotEmpty,
                onSelected: (s) {
                  line.name.text = s.name;
                  line.serviceId = s.id;
                  line.price.text = Fmt.thousands(s.price);
                  _recalcTotal();
                  setState(() {});
                },
                itemBuilder: (_) => [
                  for (final s in catalog)
                    PopupMenuItem(value: s, child: Text('${s.name} — ${Fmt.money(s.price)}')),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 54,
          child: TextFormField(
            controller: line.qty,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(labelText: 'SL'),
            onChanged: (_) {
              _recalcTotal();
              setState(() {});
            },
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 2,
          child: TextFormField(
            controller: line.price,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.right,
            inputFormatters: [ThousandsInputFormatter()],
            decoration: const InputDecoration(labelText: 'Đơn giá', suffixText: 'đ'),
            onChanged: (_) => _recalcTotal(),
          ),
        ),
        if (_lines.length > 1)
          IconButton(
            icon: const Icon(Icons.remove_circle_outline, color: AppColors.red),
            onPressed: () => setState(() {
              _lines.removeAt(i).dispose();
              _recalcTotal();
            }),
          ),
      ]),
    );
  }

  Widget _timeTile(String label, DateTime? value, void Function(DateTime) onPicked) => ListTile(
        contentPadding: EdgeInsets.zero,
        dense: true,
        leading: const Icon(Icons.event_available_outlined, color: AppColors.textMuted),
        title: Text(label),
        trailing: Text(Fmt.dateTime(value),
            style: TextStyle(fontWeight: FontWeight.w600, color: value == null ? AppColors.textMuted : Colors.white)),
        onTap: () async {
          final picked = await _pickDateTime(value);
          if (picked != null) setState(() => onPicked(picked));
        },
      );

  Widget _moneyField(TextEditingController c, String label,
          {VoidCallback? onUserEdit, bool required = false}) =>
      TextFormField(
        controller: c,
        keyboardType: TextInputType.number,
        textAlign: TextAlign.right,
        inputFormatters: [ThousandsInputFormatter()],
        decoration: InputDecoration(labelText: label, suffixText: 'đ'),
        onChanged: (_) => onUserEdit?.call(),
        validator: required ? (v) => Fmt.parseMoney(v ?? '') <= 0 ? 'Nhập tổng chi phí' : null : null,
      );

  Widget _debtTile() {
    final debt = _debt;
    final color = debt > 0 ? AppColors.orange : AppColors.green;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text('Công nợ (tự tính)', style: TextStyle(color: color)),
        Text(Fmt.money(debt < 0 ? 0 : debt),
            style: TextStyle(color: color, fontSize: 20, fontWeight: FontWeight.w800)),
      ]),
    );
  }

  Widget _assigneeDropdown() {
    final users = context.watch<UserProvider>().users.where((u) => u.isActive).toList();
    final value = users.any((u) => u.username == _assignedUser) ? _assignedUser : null;
    return DropdownButtonFormField<String>(
      // ignore: deprecated_member_use
      value: value,
      decoration: const InputDecoration(labelText: 'Nhân viên phụ trách', prefixIcon: Icon(Icons.badge_outlined)),
      items: [for (final u in users) DropdownMenuItem(value: u.username, child: Text(u.displayName))],
      onChanged: (v) => setState(() => _assignedUser = v),
    );
  }
}

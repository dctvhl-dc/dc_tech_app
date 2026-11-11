import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/file_saver.dart';
import '../../../core/utils/slip_renderer.dart';
import '../../../data/models/booking_model.dart';
import '../../../data/models/store_model.dart';
import '../../../data/models/user_model.dart';
import '../../../data/services/google_sheets_service.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/user_provider.dart';

/// Xem trước, lưu, chia sẻ và in phiếu giao / biên nhận.
class SlipScreen extends StatefulWidget {
  final Booking booking;
  final SlipKind kind;
  const SlipScreen({super.key, required this.booking, required this.kind});

  @override
  State<SlipScreen> createState() => _SlipScreenState();
}

class _SlipScreenState extends State<SlipScreen> {
  SlipResult? _res;
  String? _error;

  bool get _isMobile => Platform.isAndroid || Platform.isIOS;
  String get _base => '${widget.kind.filePrefix}_${widget.booking.id}';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _build());
  }

  /// Nhân viên phụ trách để in ở ô chữ ký và thông tin cửa hàng.
  AppUser? _findAssignedUser() {
    final b = widget.booking;
    final me = context.read<AuthProvider>().currentUser;
    if (me != null && me.username == b.assignedUser) return me;
    for (final u in context.read<UserProvider>().users) {
      if (u.username == b.assignedUser) return u;
    }
    return null;
  }

  Future<void> _build() async {
    try {
      final user = _findAssignedUser();
      final staffName = user?.displayName ?? (widget.booking.assignedUser.isNotEmpty ? widget.booking.assignedUser : 'DC TECH');

      Map<String, String> settings = const {};
      try {
        settings = await GoogleSheetsService.instance.fetchSettings();
      } catch (_) {}

      final storeList = StoreInfo.listFromSettings(settings);
      StoreInfo? targetStore;

      // Ưu tiên lấy cửa hàng gán cho nhân viên phụ trách đơn này
      if (user != null && user.storeName.isNotEmpty) {
        targetStore = storeList.firstWhere(
          (s) => s.name.toLowerCase() == user.storeName.toLowerCase(),
          orElse: () => StoreInfo(id: 'custom', name: user.storeName, address: settings['company_address'] ?? '', phone: settings['company_phone'] ?? ''),
        );
      }
      
      // Nếu chưa có, lấy Cửa hàng chính
      targetStore ??= storeList.firstWhere((s) => s.isMain, orElse: () => storeList.first);

      final company = <String, String>{
        'company_name': targetStore.name,
        'company_address': targetStore.address,
        'company_phone': targetStore.phone.isNotEmpty ? targetStore.phone : (settings['company_phone'] ?? ''),
        'staff_store': user?.storeName.isNotEmpty == true ? user!.storeName : targetStore.name,
      };

      final res = await SlipRenderer.render(
        booking: widget.booking,
        kind: widget.kind,
        staffName: staffName,
        company: company,
      );
      if (mounted) setState(() => _res = res);
    } catch (e) {
      if (mounted) setState(() => _error = 'Không tạo được phiếu: $e');
    }
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: error ? AppColors.red : AppColors.green));
  }

  Future<void> _save(bool pdf) async {
    final r = _res!;
    try {
      final path = await FileSaver.save(
        fileName: '$_base.${pdf ? 'pdf' : 'png'}',
        bytes: pdf ? r.pdf : r.png,
        extensions: [pdf ? 'pdf' : 'png'],
      );
      if (path != null) _snack('Đã lưu: $path');
    } catch (e) {
      _snack('Lưu file thất bại: $e', error: true);
    }
  }

  /// Mobile: chia sẻ qua Zalo, email, ... (ảnh phù hợp để gửi Zalo, PDF để in).
  Future<void> _share(bool pdf) async {
    final r = _res!;
    final name = '$_base.${pdf ? 'pdf' : 'png'}';
    // iPad bắt buộc có vị trí neo cho bảng chia sẻ; các máy khác bỏ qua
    final box = context.findRenderObject() as RenderBox?;
    final origin = box == null ? null : box.localToGlobal(Offset.zero) & box.size;
    try {
      await Share.shareXFiles(
        [XFile.fromData(pdf ? r.pdf : r.png, mimeType: pdf ? 'application/pdf' : 'image/png', name: name)],
        sharePositionOrigin: origin,
        fileNameOverrides: [name],
        text: '${widget.kind.label} #${widget.booking.id}',
      );
    } catch (e) {
      _snack('Không chia sẻ được: $e', error: true);
    }
  }

  /// Desktop: ghi PDF tạm rồi mở bằng trình xem PDF mặc định để in (Ctrl+P).
  Future<void> _openToPrint() async {
    try {
      final file = File('${Directory.systemTemp.path}${Platform.pathSeparator}$_base.pdf');
      await file.writeAsBytes(_res!.pdf);
      if (!await launchUrl(Uri.file(file.path))) _snack('Không mở được trình xem PDF.', error: true);
    } catch (e) {
      _snack('Không mở được file để in: $e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = _res;
    return Scaffold(
      appBar: AppBar(title: Text(widget.kind.label.toUpperCase())),
      body: _error != null
          ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!, style: const TextStyle(color: AppColors.red))))
          : r == null
              ? const Center(child: CircularProgressIndicator())
              : Container(
                  color: Colors.grey.shade800,
                  child: InteractiveViewer(
                    maxScale: 4,
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Image.memory(r.png, fit: BoxFit.contain),
                      ),
                    ),
                  ),
                ),
      bottomNavigationBar: r == null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                child: Wrap(spacing: 10, runSpacing: 8, alignment: WrapAlignment.center, children: [
                  if (_isMobile)
                    PopupMenuButton<bool>(
                      onSelected: _share,
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: false, child: Text('Gửi dạng ảnh (Zalo...)')),
                        PopupMenuItem(value: true, child: Text('Gửi dạng PDF')),
                      ],
                      child: IgnorePointer(
                        child: FilledButton.icon(
                          onPressed: () {}, // chỉ để nút hiện đúng màu; chạm sẽ mở menu
                          style: FilledButton.styleFrom(minimumSize: const Size(150, 48)),
                          icon: const Icon(Icons.share),
                          label: const Text('Chia sẻ'),
                        ),
                      ),
                    )
                  else
                    FilledButton.icon(
                      onPressed: _openToPrint,
                      style: FilledButton.styleFrom(minimumSize: const Size(150, 48)),
                      icon: const Icon(Icons.print_outlined),
                      label: const Text('Mở để in'),
                    ),
                  OutlinedButton.icon(
                    onPressed: () => _save(true),
                    icon: const Icon(Icons.picture_as_pdf_outlined),
                    label: const Text('Lưu PDF'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _save(false),
                    icon: const Icon(Icons.image_outlined),
                    label: const Text('Lưu ảnh'),
                  ),
                ]),
              ),
            ),
    );
  }
}

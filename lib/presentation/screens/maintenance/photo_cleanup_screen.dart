import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/file_saver.dart';
import '../../../core/utils/zip_writer.dart';
import '../../../data/models/photo_model.dart';
import '../../../data/services/google_sheets_service.dart';

/// Dọn ảnh giao / thu hồi cũ để Google Sheet không bị nặng.
/// Luôn xuất ZIP trước khi xóa; chỉ xóa khi đã đọc đủ toàn bộ ảnh.
class PhotoCleanupScreen extends StatefulWidget {
  const PhotoCleanupScreen({super.key});
  @override
  State<PhotoCleanupScreen> createState() => _PhotoCleanupScreenState();
}

class _PhotoCleanupScreenState extends State<PhotoCleanupScreen> {
  final _sheets = GoogleSheetsService.instance;
  int _months = 3;
  PhotoCleanupPlan? _plan;
  bool _busy = false;
  String _progress = '';

  DateTime get _cutoff {
    final n = DateTime.now();
    return DateTime(n.year, n.month - _months, n.day);
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: error ? AppColors.red : AppColors.green));
  }

  static String _stamp(DateTime d) {
    String t(int v) => v.toString().padLeft(2, '0');
    return '${d.year}${t(d.month)}${t(d.day)}_${t(d.hour)}${t(d.minute)}${t(d.second)}';
  }

  Future<void> _scan() async {
    setState(() {
      _busy = true;
      _progress = 'Đang quét tab Photos...';
      _plan = null;
    });
    try {
      final plan = await _sheets.planPhotoCleanup(_cutoff);
      if (mounted) setState(() => _plan = plan);
    } catch (e) {
      _snack('Quét thất bại: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _confirm(String title, String message, {bool danger = false}) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Hủy')),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
                minimumSize: const Size(110, 44), backgroundColor: danger ? AppColors.red : AppColors.orange),
            child: const Text('Tiếp tục'),
          ),
        ],
      ),
    );
    return ok == true;
  }

  /// Xuất toàn bộ ảnh cũ ra ZIP (mỗi đơn 1 thư mục). Nếu [thenDelete] thì xóa sau khi lưu thành công.
  Future<void> _export({required bool thenDelete}) async {
    final plan = _plan!;
    if (!await _confirm(
      thenDelete ? 'Xuất ZIP rồi xóa?' : 'Xuất ZIP?',
      thenDelete
          ? 'Sẽ tải ${plan.photos} ảnh về, lưu thành file ZIP, rồi XÓA chúng khỏi Google Sheet.'
          : 'Sẽ tải ${plan.photos} ảnh về và lưu thành file ZIP (không xóa).',
      danger: thenDelete,
    )) {
      return;
    }
    setState(() {
      _busy = true;
      _progress = 'Đang tải ảnh...';
    });
    try {
      final photos = await _sheets.fetchPhotoBlock(
        plan.rows,
        onProgress: (d, t) {
          if (mounted) setState(() => _progress = 'Đang tải ảnh... $d/$t dòng');
        },
      );
      if (photos.length < plan.photos) {
        _snack('Chỉ đọc được ${photos.length}/${plan.photos} ảnh nên KHÔNG xóa để tránh mất dữ liệu. Hãy thử lại.', error: true);
        return;
      }
      final files = <String, Uint8List>{};
      for (final p in photos) {
        final tail = p.id.length > 6 ? p.id.substring(p.id.length - 6) : p.id;
        final folder = p.bookingId.isEmpty ? 'khong_ro_don' : p.bookingId;
        files['$folder/${p.type.value}_${_stamp(p.takenAt)}_${p.takenBy}_$tail.jpg'] = p.bytes;
      }
      final zip = ZipWriter.build(files);
      final path = await FileSaver.save(
        fileName: 'AnhCu_den_${_stamp(_cutoff)}.zip',
        bytes: zip,
        extensions: ['zip'],
      );
      if (path == null) {
        _snack('Đã hủy lưu file nên chưa xóa gì.');
        return;
      }
      if (thenDelete) {
        setState(() => _progress = 'Đang xóa ảnh cũ trên Sheet...');
        await _sheets.deletePhotoBlock(plan.rows);
        if (mounted) setState(() => _plan = const PhotoCleanupPlan(0, 0, null));
        _snack('Đã lưu ZIP ($path) và xóa ${plan.photos} ảnh cũ.');
      } else {
        _snack('Đã lưu ZIP: $path');
      }
    } catch (e) {
      _snack('Thất bại: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteOnly() async {
    final plan = _plan!;
    if (!await _confirm(
      'Xóa ${plan.photos} ảnh cũ?',
      'Ảnh sẽ bị xóa vĩnh viễn khỏi Google Sheet và KHÔNG thể khôi phục (trừ khi bạn có bản sao lưu Sheet).',
      danger: true,
    )) {
      return;
    }
    setState(() {
      _busy = true;
      _progress = 'Đang xóa...';
    });
    try {
      await _sheets.deletePhotoBlock(plan.rows);
      if (mounted) setState(() => _plan = const PhotoCleanupPlan(0, 0, null));
      _snack('Đã xóa ${plan.photos} ảnh cũ.');
    } catch (e) {
      _snack('Xóa thất bại: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final plan = _plan;
    return Scaffold(
      appBar: AppBar(title: const Text('DỌN ẢNH CŨ')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(padding: const EdgeInsets.all(16), children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16)),
              child: const Text(
                'Ảnh giao / thu hồi được lưu trong tab Photos của Google Sheet nên sẽ làm Sheet nặng dần. '
                'Hãy xuất ảnh cũ ra file ZIP (mỗi đơn một thư mục) rồi xóa khỏi Sheet. '
                'Bảng tính nên được sao lưu (Tệp → Tạo bản sao) trước khi xóa.',
                style: TextStyle(height: 1.5, color: AppColors.textMuted),
              ),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<int>(
              // ignore: deprecated_member_use
              value: _months,
              decoration: const InputDecoration(labelText: 'Ảnh cũ hơn', prefixIcon: Icon(Icons.history)),
              items: const [
                DropdownMenuItem(value: 1, child: Text('1 tháng')),
                DropdownMenuItem(value: 2, child: Text('2 tháng')),
                DropdownMenuItem(value: 3, child: Text('3 tháng')),
                DropdownMenuItem(value: 6, child: Text('6 tháng')),
                DropdownMenuItem(value: 12, child: Text('12 tháng')),
              ],
              onChanged: _busy ? null : (v) => setState(() {
                    _months = v ?? _months;
                    _plan = null;
                  }),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _busy ? null : _scan,
              icon: const Icon(Icons.search),
              label: const Text('QUÉT ẢNH CŨ'),
            ),
            if (_busy)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Column(children: [const LinearProgressIndicator(), const SizedBox(height: 8), Text(_progress)]),
              ),
            if (plan != null && !_busy) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.orange.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.orange),
                ),
                child: plan.photos == 0
                    ? const Text('Không có ảnh nào cũ hơn mốc này.')
                    : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('${plan.photos} ảnh cũ (${plan.rows} dòng trong Sheet)',
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                        const SizedBox(height: 4),
                        Text(
                          'Cũ nhất: ${plan.oldest!.day.toString().padLeft(2, '0')}/${plan.oldest!.month.toString().padLeft(2, '0')}/${plan.oldest!.year}',
                          style: const TextStyle(color: AppColors.textMuted),
                        ),
                      ]),
              ),
              if (plan.photos > 0) ...[
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: () => _export(thenDelete: true),
                  icon: const Icon(Icons.archive_outlined),
                  label: const Text('XUẤT ZIP RỒI XÓA'),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: () => _export(thenDelete: false),
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50), shape: const StadiumBorder()),
                  icon: const Icon(Icons.download_outlined),
                  label: const Text('Chỉ xuất ZIP (không xóa)'),
                ),
                const SizedBox(height: 10),
                TextButton.icon(
                  onPressed: _deleteOnly,
                  icon: const Icon(Icons.delete_outline, color: AppColors.red),
                  label: const Text('Chỉ xóa, không xuất', style: TextStyle(color: AppColors.red)),
                ),
              ],
            ],
          ]),
        ),
      ),
    );
  }
}

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/local_config_storage.dart';
import '../../../data/services/google_sheets_service.dart';

/// Cấu hình kết nối Google Sheets (chỉ Super Admin).
/// - [isInitialSetup] = true: hiện ở lần chạy đầu khi máy chưa có cấu hình.
/// - Bấm "Kết nối & lưu" sẽ THỬ kết nối thật; chỉ lưu khi thành công.
class ApiConfigScreen extends StatefulWidget {
  final VoidCallback? onConnected;
  final bool isInitialSetup;
  const ApiConfigScreen({super.key, this.onConnected, this.isInitialSetup = false});

  @override
  State<ApiConfigScreen> createState() => _ApiConfigScreenState();
}

class _ApiConfigScreenState extends State<ApiConfigScreen> {
  final _sheetId = TextEditingController();
  final _json = TextEditingController();
  String? _storedCredentials;
  String? _clientEmail;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _loadExisting();
  }

  @override
  void dispose() {
    _sheetId.dispose();
    _json.dispose();
    super.dispose();
  }

  Future<void> _loadExisting() async {
    final cfg = await LocalConfigStorage.load();
    if (!mounted) return;
    setState(() {
      _sheetId.text = cfg.sheetId ?? '';
      _storedCredentials = cfg.credentials;
      _clientEmail = _readEmail(cfg.credentials);
    });
  }

  static String? _readEmail(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final m = jsonDecode(raw);
      return m is Map ? m['client_email'] as String? : null;
    } catch (_) {
      return null;
    }
  }

  /// Cho phép dán cả URL: https://docs.google.com/spreadsheets/d/`ID`/edit
  static String _extractSheetId(String s) =>
      RegExp(r'/d/([a-zA-Z0-9-_]+)').firstMatch(s)?.group(1) ?? s.trim();

  static String? _validate(String raw) {
    try {
      final m = jsonDecode(raw);
      if (m is! Map ||
          m['type'] != 'service_account' ||
          m['client_email'] == null ||
          m['private_key'] == null) {
        return 'Đây không phải file Service Account (cần có type, client_email, private_key).';
      }
      return null;
    } catch (_) {
      return 'Nội dung không phải JSON hợp lệ.';
    }
  }

  String _friendly(String e) {
    if (e.contains('403') || e.toLowerCase().contains('permission')) {
      return 'Chưa có quyền truy cập Sheet. Hãy Share Sheet cho email '
          '${_clientEmail ?? 'của Service Account'} với quyền Editor.';
    }
    if (e.contains('404')) return 'Không tìm thấy Sheet. Kiểm tra lại Sheet ID.';
    return e;
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData('text/plain');
    if (data?.text == null) return;
    _json.text = data!.text!;
    setState(() => _clientEmail = _readEmail(_json.text) ?? _clientEmail);
  }

  Future<void> _connect() async {
    final id = _extractSheetId(_sheetId.text);
    final raw = _json.text.trim().isNotEmpty ? _json.text.trim() : (_storedCredentials ?? '');
    if (id.isEmpty) {
      setState(() => _error = 'Vui lòng nhập Google Sheet ID.');
      return;
    }
    if (raw.isEmpty) {
      setState(() => _error = 'Vui lòng dán nội dung file JSON Service Account.');
      return;
    }
    final invalid = _validate(raw);
    if (invalid != null) {
      setState(() => _error = invalid);
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await GoogleSheetsService.instance.init(credentialsJson: raw, spreadsheetId: id);
      await LocalConfigStorage.save(sheetId: id, credentials: raw);
      if (!mounted) return;
      widget.onConnected?.call();
      if (!widget.isInitialSetup) Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() => _error = _friendly(e.toString()));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('KẾT NỐI GOOGLE SHEETS')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Text(
                  '1. Tạo Service Account trên Google Cloud, bật Google Sheets API, tải file JSON.\n'
                  '2. Tạo Google Sheet trống, bấm Share, thêm email Service Account với quyền Editor.\n'
                  '3. Dán Sheet ID (hoặc cả URL) và nội dung file JSON vào bên dưới.',
                  style: TextStyle(height: 1.5, color: AppColors.textMuted),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _sheetId,
                decoration: const InputDecoration(
                  labelText: 'Google Sheet ID hoặc URL',
                  prefixIcon: Icon(Icons.description_outlined),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _json,
                maxLines: 6,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                onChanged: (v) => setState(() => _clientEmail = _readEmail(v) ?? _clientEmail),
                decoration: InputDecoration(
                  labelText: 'Nội dung file JSON Service Account',
                  alignLabelWithHint: true,
                  hintText: _storedCredentials != null
                      ? 'Đã lưu khóa trên máy. Dán JSON mới nếu muốn thay đổi.'
                      : '{ "type": "service_account", ... }',
                ),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _paste,
                  icon: const Icon(Icons.content_paste),
                  label: const Text('Dán từ clipboard'),
                ),
              ),
              if (_clientEmail != null)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.mark_email_read_outlined, color: AppColors.green),
                  title: const Text('Share Sheet cho email này (Editor):'),
                  subtitle: SelectableText(_clientEmail!),
                  trailing: IconButton(
                    icon: const Icon(Icons.copy),
                    onPressed: () => Clipboard.setData(ClipboardData(text: _clientEmail!)),
                  ),
                ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(_error!, style: const TextStyle(color: AppColors.red)),
                ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _busy ? null : _connect,
                icon: _busy
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5))
                    : const Icon(Icons.lock_outline),
                label: const Text('KẾT NỐI & LƯU'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

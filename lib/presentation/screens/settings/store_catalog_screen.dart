import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/models/store_model.dart';
import '../../../data/services/google_sheets_service.dart';

/// Quản lý danh mục cửa hàng (Cửa hàng chính & Cửa hàng phụ / Chi nhánh).
class StoreCatalogScreen extends StatefulWidget {
  const StoreCatalogScreen({super.key});

  @override
  State<StoreCatalogScreen> createState() => _StoreCatalogScreenState();
}

class _StoreCatalogScreenState extends State<StoreCatalogScreen> {
  final _formKey = GlobalKey<FormState>();
  final _sheets = GoogleSheetsService.instance;

  // Cửa hàng chính
  final _mainName = TextEditingController();
  final _mainAddr = TextEditingController();
  final _mainPhone = TextEditingController();

  // Cửa hàng phụ / Chi nhánh 1
  final _subName = TextEditingController();
  final _subAddr = TextEditingController();
  final _subPhone = TextEditingController();

  // Các chi nhánh bổ sung khác (chi nhánh 2, 3...)
  final List<StoreInfo> _extraBranches = [];

  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadStores();
  }

  @override
  void dispose() {
    _mainName.dispose();
    _mainAddr.dispose();
    _mainPhone.dispose();
    _subName.dispose();
    _subAddr.dispose();
    _subPhone.dispose();
    super.dispose();
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: error ? AppColors.red : AppColors.green),
    );
  }

  Future<void> _loadStores() async {
    setState(() => _loading = true);
    try {
      final settings = await _sheets.fetchSettings();
      final all = StoreInfo.listFromSettings(settings);

      final main = all.firstWhere((s) => s.isMain, orElse: () => all.first);
      final remaining = all.where((s) => s.id != main.id).toList();

      final sub = remaining.isNotEmpty
          ? remaining.first
          : const StoreInfo(
              id: 'store_sub',
              name: 'DC TECH - Chi nhánh 2',
              address: 'Phường Hồng Gai, Thành phố Hạ Long, Quảng Ninh',
              phone: '0912345678',
            );

      final extra = remaining.length > 1 ? remaining.sublist(1) : <StoreInfo>[];

      if (mounted) {
        setState(() {
          _mainName.text = main.name;
          _mainAddr.text = main.address;
          _mainPhone.text = main.phone;

          _subName.text = sub.name;
          _subAddr.text = sub.address;
          _subPhone.text = sub.phone;

          _extraBranches.clear();
          _extraBranches.addAll(extra);
        });
      }
    } catch (e) {
      _snack('Không tải được danh mục cửa hàng: $e', error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _saveStores() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    try {
      final mainStore = StoreInfo(
        id: 'store_main',
        name: _mainName.text.trim(),
        address: _mainAddr.text.trim(),
        phone: _mainPhone.text.trim(),
        isMain: true,
      );

      final subStore = StoreInfo(
        id: 'store_sub',
        name: _subName.text.trim(),
        address: _subAddr.text.trim(),
        phone: _subPhone.text.trim(),
        isMain: false,
      );

      final allStores = [mainStore, subStore, ..._extraBranches];
      final jsonStr = StoreInfo.listToJson(allStores);

      // 1. Lưu kho stores_json
      await _sheets.saveSetting('stores_json', jsonStr);

      // 2. Lưu từng key lẻ để đồng bộ với Sheet & phiếu in
      await _sheets.saveSetting('main_store_name', mainStore.name);
      await _sheets.saveSetting('main_store_address', mainStore.address);
      await _sheets.saveSetting('main_store_phone', mainStore.phone);

      await _sheets.saveSetting('sub_store_name', subStore.name);
      await _sheets.saveSetting('sub_store_address', subStore.address);
      await _sheets.saveSetting('sub_store_phone', subStore.phone);

      await _sheets.saveSetting('company_name', mainStore.name);
      await _sheets.saveSetting('company_address', mainStore.address);
      await _sheets.saveSetting('company_phone', mainStore.phone);

      _snack('Đã lưu thông tin cửa hàng chính & cửa hàng phụ thành công!');
    } catch (e) {
      _snack('Lưu thất bại: $e', error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _addExtraBranch([StoreInfo? existing, int? index]) async {
    final res = await showDialog<StoreInfo>(
      context: context,
      builder: (_) => _ExtraBranchDialog(existing: existing),
    );
    if (res == null) return;

    setState(() {
      if (index != null && index >= 0 && index < _extraBranches.length) {
        _extraBranches[index] = res;
      } else {
        _extraBranches.add(res);
      }
    });
  }

  void _removeExtraBranch(int index) {
    setState(() => _extraBranches.removeAt(index));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('DANH MỤC CỬA HÀNG')),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Center(
            heightFactor: 1,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: FilledButton.icon(
                onPressed: _saving ? null : _saveStores,
                icon: _saving
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.save_outlined),
                label: const Text('LƯU DANH MỤC CỬA HÀNG'),
              ),
            ),
          ),
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : Form(
                  key: _formKey,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      _card('CỬA HÀNG CHÍNH', AppColors.orange, Icons.store, [
                        TextFormField(
                          controller: _mainName,
                          decoration: const InputDecoration(
                            labelText: 'Tên cửa hàng chính',
                            prefixIcon: Icon(Icons.storefront),
                          ),
                          validator: (v) => (v == null || v.trim().isEmpty) ? 'Nhập tên cửa hàng chính' : null,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _mainAddr,
                          maxLines: 2,
                          decoration: const InputDecoration(
                            labelText: 'Địa chỉ cửa hàng chính',
                            prefixIcon: Icon(Icons.location_on_outlined),
                          ),
                          validator: (v) => (v == null || v.trim().isEmpty) ? 'Nhập địa chỉ cửa hàng chính' : null,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _mainPhone,
                          keyboardType: TextInputType.phone,
                          decoration: const InputDecoration(
                            labelText: 'Hotline / Số điện thoại',
                            prefixIcon: Icon(Icons.phone_outlined),
                          ),
                        ),
                      ]),
                      const SizedBox(height: 16),
                      _card('CỬA HÀNG PHỤ / CHI NHÁNH 1', AppColors.blue, Icons.storefront, [
                        TextFormField(
                          controller: _subName,
                          decoration: const InputDecoration(
                            labelText: 'Tên cửa hàng phụ / chi nhánh',
                            prefixIcon: Icon(Icons.storefront),
                          ),
                          validator: (v) => (v == null || v.trim().isEmpty) ? 'Nhập tên cửa hàng phụ' : null,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _subAddr,
                          maxLines: 2,
                          decoration: const InputDecoration(
                            labelText: 'Địa chỉ cửa hàng phụ / chi nhánh',
                            prefixIcon: Icon(Icons.location_on_outlined),
                          ),
                          validator: (v) => (v == null || v.trim().isEmpty) ? 'Nhập địa chỉ cửa hàng phụ' : null,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _subPhone,
                          keyboardType: TextInputType.phone,
                          decoration: const InputDecoration(
                            labelText: 'Hotline / Số điện thoại chi nhánh',
                            prefixIcon: Icon(Icons.phone_outlined),
                          ),
                        ),
                      ]),
                      const SizedBox(height: 16),
                      if (_extraBranches.isNotEmpty) ...[
                        const Padding(
                          padding: EdgeInsets.only(left: 4, bottom: 8),
                          child: Text('CÁC CHI NHÁNH BỔ SUNG KHÁC', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                        ),
                        for (var i = 0; i < _extraBranches.length; i++) ...[
                          _extraBranchTile(_extraBranches[i], i),
                          const SizedBox(height: 10),
                        ],
                      ],
                      OutlinedButton.icon(
                        onPressed: () => _addExtraBranch(),
                        icon: const Icon(Icons.add_business_outlined),
                        label: const Text('Thêm chi nhánh khác'),
                      ),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
        ),
      ),
    );
  }

  Widget _card(String title, Color badgeColor, IconData icon, List<Widget> children) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: badgeColor.withValues(alpha: 0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: badgeColor, size: 24),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: badgeColor),
                  ),
                ),
              ],
            ),
            const Divider(height: 20),
            ...children,
          ],
        ),
      );

  Widget _extraBranchTile(StoreInfo b, int index) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        ),
        child: Row(
          children: [
            const Icon(Icons.storefront, color: AppColors.blue),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(b.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                  Text(b.address, style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
                  if (b.phone.isNotEmpty)
                    Text('Hotline: ${b.phone}', style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.edit_outlined, size: 20),
              onPressed: () => _addExtraBranch(b, index),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, color: AppColors.red, size: 20),
              onPressed: () => _removeExtraBranch(index),
            ),
          ],
        ),
      );
}

class _ExtraBranchDialog extends StatefulWidget {
  final StoreInfo? existing;
  const _ExtraBranchDialog({this.existing});

  @override
  State<_ExtraBranchDialog> createState() => _ExtraBranchDialogState();
}

class _ExtraBranchDialogState extends State<_ExtraBranchDialog> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late final _address = TextEditingController(text: widget.existing?.address ?? '');
  late final _phone = TextEditingController(text: widget.existing?.phone ?? '');

  @override
  void dispose() {
    _name.dispose();
    _address.dispose();
    _phone.dispose();
    super.dispose();
  }

  void _save() {
    if (!_form.currentState!.validate()) return;
    final store = StoreInfo(
      id: widget.existing?.id ?? 'store_${DateTime.now().millisecondsSinceEpoch}',
      name: _name.text.trim(),
      address: _address.text.trim(),
      phone: _phone.text.trim(),
      isMain: false,
    );
    Navigator.pop(context, store);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surface,
      title: Text(widget.existing == null ? 'Thêm chi nhánh khác' : 'Sửa chi nhánh'),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _name,
                  decoration: const InputDecoration(
                    labelText: 'Tên chi nhánh',
                    prefixIcon: Icon(Icons.storefront),
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Nhập tên chi nhánh' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _address,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Địa chỉ chi nhánh',
                    prefixIcon: Icon(Icons.location_on_outlined),
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Nhập địa chỉ chi nhánh' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Số điện thoại chi nhánh',
                    prefixIcon: Icon(Icons.phone_outlined),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Hủy')),
        FilledButton(onPressed: _save, child: const Text('Thêm')),
      ],
    );
  }
}

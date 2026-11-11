import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../data/models/service_model.dart';
import '../../../providers/service_provider.dart';

/// Danh mục dịch vụ / thiết bị cho thuê (Admin, Super Admin).
class ServiceCatalogScreen extends StatefulWidget {
  const ServiceCatalogScreen({super.key});
  @override
  State<ServiceCatalogScreen> createState() => _ServiceCatalogScreenState();
}

class _ServiceCatalogScreenState extends State<ServiceCatalogScreen> {
  final _search = TextEditingController();

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
        SnackBar(content: Text(msg), backgroundColor: error ? AppColors.red : AppColors.green));
  }

  Future<void> _reload() async {
    try {
      await context.read<ServiceProvider>().load(force: true);
    } catch (e) {
      _snack('Không tải được danh mục: $e');
    }
  }

  Future<void> _openForm([RentalService? existing]) async {
    final ok = await showDialog<bool>(context: context, builder: (_) => _ServiceDialog(existing: existing));
    if (ok == true) _snack(existing == null ? 'Đã thêm dịch vụ' : 'Đã cập nhật dịch vụ', error: false);
  }

  Future<void> _delete(RentalService s) async {
    final provider = context.read<ServiceProvider>();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Xóa dịch vụ?'),
        content: Text('Xóa "${s.name}" khỏi danh mục.\nCác đơn cũ vẫn giữ nguyên tên và giá đã lưu.'),
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
    if (confirm != true) return;
    try {
      await provider.delete(s.id);
      _snack('Đã xóa "${s.name}"', error: false);
    } catch (e) {
      _snack('Xóa thất bại: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<ServiceProvider>();
    final q = _search.text.trim().toLowerCase();
    final list = p.services
        .where((s) => q.isEmpty || s.name.toLowerCase().contains(q) || s.description.toLowerCase().contains(q))
        .toList();

    return Scaffold(
      appBar: AppBar(title: const Text('DANH MỤC DỊCH VỤ')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openForm(),
        backgroundColor: AppColors.orange,
        foregroundColor: Colors.white,
        tooltip: 'Thêm dịch vụ',
        child: const Icon(Icons.add, size: 28),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: TextField(
                controller: _search,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(hintText: 'Tìm kiếm dịch vụ, thiết bị...', prefixIcon: Icon(Icons.search)),
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _reload,
                child: p.loading && p.services.isEmpty
                    ? const Center(child: CircularProgressIndicator())
                    : list.isEmpty
                        ? ListView(children: const [
                            SizedBox(height: 120),
                            Center(child: Text('Chưa có dịch vụ nào', style: TextStyle(color: AppColors.textMuted))),
                          ])
                        : ListView.builder(
                            padding: const EdgeInsets.fromLTRB(16, 4, 16, 90),
                            itemCount: list.length,
                            itemBuilder: (_, i) => _card(list[i]),
                          ),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _card(RentalService s) => Card(
        color: AppColors.surface,
        margin: const EdgeInsets.only(bottom: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: AppColors.field.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.speaker, color: s.isActive ? AppColors.orange : AppColors.textMuted, size: 30),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Flexible(
                    child: Text(s.name,
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: s.isActive ? Colors.white : AppColors.textMuted)),
                  ),
                  if (!s.isActive)
                    Container(
                      margin: const EdgeInsets.only(left: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(color: Colors.grey.shade700, borderRadius: BorderRadius.circular(10)),
                      child: const Text('Ngưng', style: TextStyle(fontSize: 11)),
                    ),
                ]),
                if (s.description.isNotEmpty)
                  Text(s.description, style: const TextStyle(color: AppColors.textMuted, fontSize: 13)),
                const SizedBox(height: 4),
                Text(Fmt.money(s.price),
                    style: const TextStyle(color: AppColors.orange, fontSize: 16, fontWeight: FontWeight.w800)),
                Text(
                  s.quantity > 0 ? 'Số lượng: ${s.quantity}' : 'Chưa khai báo số lượng (chưa kiểm tra trùng lịch)',
                  style: TextStyle(
                      fontSize: 12, color: s.quantity > 0 ? AppColors.textMuted : AppColors.orange),
                ),
              ]),
            ),
            IconButton(
              tooltip: 'Sửa',
              icon: const Icon(Icons.edit_outlined, color: AppColors.blue),
              onPressed: () => _openForm(s),
            ),
            IconButton(
              tooltip: 'Xóa',
              icon: const Icon(Icons.delete_outline, color: AppColors.red),
              onPressed: () => _delete(s),
            ),
          ]),
        ),
      );
}

/// Form thêm / sửa dịch vụ.
class _ServiceDialog extends StatefulWidget {
  final RentalService? existing;
  const _ServiceDialog({this.existing});
  @override
  State<_ServiceDialog> createState() => _ServiceDialogState();
}

class _ServiceDialogState extends State<_ServiceDialog> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late final _price = TextEditingController(
      text: (widget.existing?.price ?? 0) == 0 ? '' : Fmt.thousands(widget.existing!.price));
  late final _desc = TextEditingController(text: widget.existing?.description ?? '');
  late final _qty = TextEditingController(
      text: (widget.existing?.quantity ?? 0) == 0 ? '' : '${widget.existing!.quantity}');
  late bool _active = widget.existing?.isActive ?? true;
  bool _busy = false;
  String? _error;

  bool get _isEdit => widget.existing != null;

  @override
  void dispose() {
    _name.dispose();
    _price.dispose();
    _desc.dispose();
    _qty.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final provider = context.read<ServiceProvider>();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final id = widget.existing?.id ?? await provider.nextId();
      await provider.save(
        RentalService(
          id: id,
          name: _name.text.trim(),
          price: Fmt.parseMoney(_price.text),
          description: _desc.text.trim(),
          isActive: _active,
          quantity: int.tryParse(_qty.text.trim()) ?? 0,
        ),
        isNew: !_isEdit,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(_isEdit ? 'Sửa dịch vụ' : 'Thêm dịch vụ'),
        content: SizedBox(
          width: 400,
          child: SingleChildScrollView(
            child: Form(
              key: _form,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextFormField(
                  controller: _name,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(labelText: 'Tên dịch vụ / thiết bị'),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Nhập tên dịch vụ' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _price,
                  keyboardType: TextInputType.number,
                  inputFormatters: [ThousandsInputFormatter()],
                  textAlign: TextAlign.right,
                  decoration: const InputDecoration(labelText: 'Đơn giá / ngày', suffixText: 'đ'),
                  validator: (v) => Fmt.parseMoney(v ?? '') <= 0 ? 'Nhập đơn giá lớn hơn 0' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _qty,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    labelText: 'Số lượng có thể nhận',
                    helperText: 'Tổng số thiết bị đang có. Dùng để cảnh báo khi đặt trùng lịch.',
                    prefixIcon: Icon(Icons.inventory_2_outlined),
                  ),
                  validator: (v) => (int.tryParse((v ?? '').trim()) ?? 0) < 1 ? 'Nhập số lượng từ 1 trở lên' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _desc,
                  maxLines: 2,
                  decoration: const InputDecoration(labelText: 'Mô tả (tuỳ chọn)'),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Đang cho thuê'),
                  subtitle: const Text('Tắt để ẩn khỏi danh sách khi tạo đơn', style: TextStyle(fontSize: 12)),
                  value: _active,
                  activeThumbColor: AppColors.orange,
                  onChanged: (v) => setState(() => _active = v),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(_error!, style: const TextStyle(color: AppColors.red)),
                  ),
              ]),
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: _busy ? null : () => Navigator.pop(context, false), child: const Text('Hủy')),
          FilledButton(
            onPressed: _busy ? null : _save,
            style: FilledButton.styleFrom(minimumSize: const Size(100, 44)),
            child: _busy
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Lưu'),
          ),
        ],
      );
}

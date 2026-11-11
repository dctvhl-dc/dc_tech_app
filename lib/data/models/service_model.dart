/// Một dòng trong danh mục "Services" (thiết bị / dịch vụ cho thuê).
class RentalService {
  final String id;
  final String name;
  final int price; // VND / đơn vị
  final String description;
  final bool isActive; // false = ngưng cho thuê, không hiện khi tạo đơn

  /// Số lượng có thể nhận cùng lúc (tổng số thiết bị đang có).
  /// 0 = chưa khai báo -> chưa kiểm tra trùng lịch cho dịch vụ này.
  final int quantity;

  const RentalService({
    required this.id,
    required this.name,
    required this.price,
    this.description = '',
    this.isActive = true,
    this.quantity = 0,
  });

  static bool _parseActive(String? s) {
    const off = {'ngưng', 'ngưng hoạt động', 'tạm ngưng', 'khóa', 'khoá', 'false', '0', 'inactive'};
    return !off.contains((s ?? '').trim().toLowerCase());
  }

  static int _int(String? s) => int.tryParse((s ?? '').replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;

  factory RentalService.fromMap(Map<String, String> m) => RentalService(
        id: m['id'] ?? '',
        name: m['name'] ?? '',
        price: _int(m['price']),
        description: m['description'] ?? '',
        isActive: _parseActive(m['status']),
        quantity: _int(m['quantity']),
      );

  Map<String, String> toMap() => {
        'id': id,
        'name': name,
        'price': '$price',
        'description': description,
        'status': isActive ? 'Hoạt động' : 'Ngưng hoạt động',
        'quantity': '$quantity',
      };
}

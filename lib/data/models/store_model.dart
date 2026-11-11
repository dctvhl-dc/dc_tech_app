import 'dart:convert';

/// Thông tin cửa hàng (Cửa hàng chính, Cửa hàng phụ / Chi nhánh).
class StoreInfo {
  final String id;
  final String name;
  final String address;
  final String phone;
  final bool isMain;

  const StoreInfo({
    required this.id,
    required this.name,
    required this.address,
    this.phone = '',
    this.isMain = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'address': address,
        'phone': phone,
        'isMain': isMain,
      };

  factory StoreInfo.fromJson(Map<String, dynamic> j) => StoreInfo(
        id: j['id']?.toString() ?? '',
        name: j['name']?.toString() ?? '',
        address: j['address']?.toString() ?? '',
        phone: j['phone']?.toString() ?? '',
        isMain: j['isMain'] == true || j['is_main'] == true,
      );

  static List<StoreInfo> listFromSettings(Map<String, String> settings) {
    final raw = settings['stores_json'] ?? '';
    if (raw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          final list = decoded.map((e) => StoreInfo.fromJson(Map<String, dynamic>.from(e))).toList();
          if (list.isNotEmpty) return list;
        }
      } catch (_) {}
    }

    // Đọc từ key lẻ (nếu có) hoặc dùng mặc định
    final mainName = (settings['main_store_name'] ?? settings['company_name'] ?? '').trim();
    final mainAddr = (settings['main_store_address'] ?? settings['company_address'] ?? '').trim();
    final mainPhone = (settings['main_store_phone'] ?? settings['company_phone'] ?? '').trim();

    final subName = (settings['sub_store_name'] ?? '').trim();
    final subAddr = (settings['sub_store_address'] ?? '').trim();
    final subPhone = (settings['sub_store_phone'] ?? '').trim();

    return [
      StoreInfo(
        id: 'store_main',
        name: mainName.isNotEmpty ? mainName : 'DC TECH - Cửa hàng chính',
        address: mainAddr.isNotEmpty ? mainAddr : 'Phường Bãi Cháy, Thành phố Hạ Long, Quảng Ninh',
        phone: mainPhone.isNotEmpty ? mainPhone : '0987654321',
        isMain: true,
      ),
      StoreInfo(
        id: 'store_sub',
        name: subName.isNotEmpty ? subName : 'DC TECH - Chi nhánh 2',
        address: subAddr.isNotEmpty ? subAddr : 'Phường Hồng Gai, Thành phố Hạ Long, Quảng Ninh',
        phone: subPhone.isNotEmpty ? subPhone : '0912345678',
        isMain: false,
      ),
    ];
  }

  static List<StoreInfo> listFromJson(String raw) {
    if (raw.trim().isEmpty) return defaultStores;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        final list = decoded.map((e) => StoreInfo.fromJson(Map<String, dynamic>.from(e))).toList();
        if (list.isNotEmpty) return list;
      }
    } catch (_) {}
    return defaultStores;
  }

  static String listToJson(List<StoreInfo> stores) =>
      jsonEncode(stores.map((e) => e.toJson()).toList());

  static const List<StoreInfo> defaultStores = [
    StoreInfo(
      id: 'store_main',
      name: 'DC TECH - Cửa hàng chính',
      address: 'Phường Bãi Cháy, Thành phố Hạ Long, Quảng Ninh',
      phone: '0987654321',
      isMain: true,
    ),
    StoreInfo(
      id: 'store_sub',
      name: 'DC TECH - Chi nhánh 2',
      address: 'Phường Hồng Gai, Thành phố Hạ Long, Quảng Ninh',
      phone: '0912345678',
      isMain: false,
    ),
  ];
}

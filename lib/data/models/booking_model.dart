import 'dart:convert';

/// Trạng thái đơn. Lưu nguyên nhãn tiếng Việt vào Sheet cho dễ đọc.
enum BookingStatus {
  pending('Chưa giao'),
  delivered('Đã giao loa'),
  returned('Đã trả loa'),
  cancelled('Đã hủy');

  final String label;
  const BookingStatus(this.label);

  static BookingStatus fromString(String? s) => BookingStatus.values
      .firstWhere((e) => e.label == s?.trim(), orElse: () => BookingStatus.pending);
}

/// Một dịch vụ trong đơn: chọn từ danh mục hoặc nhập tay. Giá là giá *tại thời
/// điểm tạo đơn* (sửa danh mục sau này không làm đổi đơn cũ).
class BookingServiceItem {
  final String name;
  final int price; // đơn giá 1 đơn vị
  final int qty; // số lượng thuê (mặc định 1)
  final String? serviceId; // mã trong danh mục (null = nhập tay, không kiểm tra tồn kho)
  const BookingServiceItem({required this.name, required this.price, this.qty = 1, this.serviceId});

  /// Thành tiền của dòng = đơn giá x số lượng.
  int get lineTotal => price * qty;

  Map<String, dynamic> toJson() => {
        'name': name,
        'price': price,
        if (qty != 1) 'qty': qty,
        if (serviceId != null) 'id': serviceId,
      };
  factory BookingServiceItem.fromJson(Map<String, dynamic> j) => BookingServiceItem(
        name: '${j['name'] ?? ''}',
        price: (j['price'] as num?)?.toInt() ?? 0,
        qty: ((j['qty'] as num?)?.toInt() ?? 1) < 1 ? 1 : ((j['qty'] as num?)?.toInt() ?? 1),
        serviceId: j['id']?.toString(),
      );

  /// Cột `services_info` là JSON. Nếu gặp text thường (ai đó gõ tay trong Sheet)
  /// thì coi như 1 dịch vụ giá 0 thay vì crash.
  static List<BookingServiceItem> listFromCell(String raw) {
    if (raw.trim().isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded
            .map((e) => BookingServiceItem.fromJson(Map<String, dynamic>.from(e)))
            .toList();
      }
    } catch (_) {}
    return [BookingServiceItem(name: raw, price: 0)];
  }

  static String listToCell(List<BookingServiceItem> items) =>
      jsonEncode(items.map((e) => e.toJson()).toList());
}

class Booking {
  final String id;
  final DateTime createdAt;
  final String customerName;
  final String customerPhone;
  final List<BookingServiceItem> services;
  final DateTime? serviceTime; // thời điểm sử dụng
  final DateTime? installTime; // giờ giao / lắp đặt
  final DateTime? collectTime; // giờ thu hồi
  final String locationText;
  final String gpsLocation; // "lat,lng" (tách từ link Google Maps)
  final String mapLink; // link Google Maps khách gửi
  final String note;
  final int totalCost;
  final int paidAmount; // khách đã trả (nhân viên đã thu)
  final int submittedToCompany; // nhân viên đã nộp về cty
  final bool requireInvoice;
  final String invoiceInfo;
  final BookingStatus status;
  final String assignedUser; // username nhân viên phụ trách
  final String createdBy; // username người tạo đơn
  final String updatedBy; // username người cập nhật gần nhất
  final DateTime? updatedAt;
  final String cancelReason; // lý do hủy đơn (nếu đã hủy)

  const Booking({
    required this.id,
    required this.createdAt,
    required this.customerName,
    required this.customerPhone,
    required this.services,
    this.serviceTime,
    this.installTime,
    this.collectTime,
    this.locationText = '',
    this.gpsLocation = '',
    this.mapLink = '',
    this.note = '',
    this.totalCost = 0,
    this.paidAmount = 0,
    this.submittedToCompany = 0,
    this.requireInvoice = false,
    this.invoiceInfo = '',
    this.status = BookingStatus.pending,
    required this.assignedUser,
    this.createdBy = '',
    this.updatedBy = '',
    this.updatedAt,
    this.cancelReason = '',
  });

  /// Công nợ = Tổng - Đã thanh toán. KHÔNG nhận từ ngoài: luôn tự tính.
  int get debtAmount => status == BookingStatus.cancelled ? 0 : totalCost - paidAmount;

  /// Tiền nhân viên đang giữ, chưa nộp cty.
  int get pendingToCompany => paidAmount - submittedToCompany;

  /// Dùng cho thao tác nhanh: User bấm "Giao loa" / "Thu loa" / "Hủy đơn".
  Booking copyWith({
    BookingStatus? status,
    int? paidAmount,
    int? submittedToCompany,
    String? cancelReason,
    String? updatedBy,
    DateTime? updatedAt,
  }) =>
      Booking(
        id: id,
        createdAt: createdAt,
        customerName: customerName,
        customerPhone: customerPhone,
        services: services,
        serviceTime: serviceTime,
        installTime: installTime,
        collectTime: collectTime,
        locationText: locationText,
        gpsLocation: gpsLocation,
        mapLink: mapLink,
        note: note,
        totalCost: totalCost,
        paidAmount: paidAmount ?? this.paidAmount,
        submittedToCompany: submittedToCompany ?? this.submittedToCompany,
        requireInvoice: requireInvoice,
        invoiceInfo: invoiceInfo,
        status: status ?? this.status,
        assignedUser: assignedUser,
        createdBy: createdBy,
        updatedBy: updatedBy ?? this.updatedBy,
        updatedAt: updatedAt ?? this.updatedAt,
        cancelReason: cancelReason ?? this.cancelReason,
      );

  static int _int(String? s) =>
      int.tryParse((s ?? '').replaceAll(RegExp(r'[^0-9-]'), '')) ?? 0;
  static DateTime? _dt(String? s) =>
      (s == null || s.isEmpty) ? null : DateTime.tryParse(s);

  factory Booking.fromMap(Map<String, String> m) => Booking(
        id: m['id'] ?? '',
        createdAt: _dt(m['created_at']) ?? DateTime.now(),
        customerName: m['customer_name'] ?? '',
        // Bỏ dấu ' (xem toMap) nếu Sheets trả về kèm
        customerPhone: (m['customer_phone'] ?? '').replaceFirst("'", ''),
        services: BookingServiceItem.listFromCell(m['services_info'] ?? ''),
        serviceTime: _dt(m['service_time']),
        installTime: _dt(m['install_time']),
        collectTime: _dt(m['collect_time']),
        locationText: m['location_text'] ?? '',
        gpsLocation: m['gps_location'] ?? '',
        mapLink: m['map_link'] ?? '',
        note: m['note'] ?? '',
        totalCost: _int(m['total_cost']),
        paidAmount: _int(m['paid_amount']),
        submittedToCompany: _int(m['submitted_to_company']),
        requireInvoice: const {'true', 'có', 'co', 'yes', '1'}
            .contains((m['require_invoice'] ?? '').trim().toLowerCase()),
        invoiceInfo: m['invoice_info'] ?? '',
        status: BookingStatus.fromString(m['status']),
        assignedUser: m['assigned_user'] ?? '',
        createdBy: m['created_by'] ?? '',
        updatedBy: m['updated_by'] ?? '',
        updatedAt: _dt(m['updated_at']),
        cancelReason: m['cancel_reason'] ?? '',
      );

  /// Mọi value đều là String để Google Sheets không tự đổi kiểu.
  Map<String, String> toMap() => {
        'id': id,
        'created_at': createdAt.toIso8601String(),
        'customer_name': customerName,
        // Tiền tố ' ép Sheets giữ là text -> không mất số 0 đầu của SĐT
        'customer_phone': "'$customerPhone",
        'services_info': BookingServiceItem.listToCell(services),
        'service_time': serviceTime?.toIso8601String() ?? '',
        'install_time': installTime?.toIso8601String() ?? '',
        'collect_time': collectTime?.toIso8601String() ?? '',
        'location_text': locationText,
        'gps_location': gpsLocation,
        'map_link': mapLink,
        'note': note,
        'total_cost': '$totalCost',
        'paid_amount': '$paidAmount',
        'submitted_to_company': '$submittedToCompany',
        'debt_amount': '$debtAmount', // tự tính
        'require_invoice': requireInvoice ? 'TRUE' : 'FALSE',
        'invoice_info': invoiceInfo,
        'status': status.label,
        'assigned_user': assignedUser,
        'created_by': createdBy,
        'updated_by': updatedBy,
        'updated_at': updatedAt?.toIso8601String() ?? '',
        'cancel_reason': cancelReason,
      };
}

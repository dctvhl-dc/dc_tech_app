/// Tên các tab trong Google Sheet.
class SheetNames {
  static const users = 'Users';
  static const services = 'Services';
  static const bookings = 'Bookings';
  static const settings = 'Settings';
  static const photos = 'Photos'; // ảnh giao / thu hồi loa (base64, chia nhỏ)
}

/// Header (hàng 1) của từng tab. gsheets dùng hàng này làm "key" cho Map.
/// => KHÔNG đổi tên cột sau khi đã có dữ liệu.
class SheetSchema {
  static const Map<String, List<String>> headers = {
    SheetNames.users: [
      'id', 'username', 'password', 'role', 'full_name', 'phone', 'is_active',
      'created_at', 'must_change_password', 'reset_requested', 'store_name',
    ],
    SheetNames.services: ['id', 'name', 'price', 'description', 'status', 'quantity'],
    SheetNames.bookings: [
      'id', 'created_at', 'customer_name', 'customer_phone', 'services_info',
      'service_time', 'install_time', 'collect_time', 'location_text',
      'gps_location', 'map_link', 'note', 'total_cost', 'paid_amount', 'submitted_to_company',
      'debt_amount', 'require_invoice', 'invoice_info', 'status',
      'assigned_user', 'created_by', 'updated_by', 'updated_at',
    ],
    // Dạng key/value: company_name, hotline, ...
    SheetNames.settings: ['key', 'value'],
    SheetNames.photos: ['id', 'booking_id', 'type', 'taken_at', 'taken_by', 'part', 'data'],
  };

  /// Tên cột thay thế được chấp nhận (so khớp không phân biệt hoa/thường).
  /// Nhờ vậy Sheet có header tiếng Việt vẫn dùng được, không cần đổi tên.
  /// Cột nào còn thiếu, app tự thêm vào cuối hàng tiêu đề (tên tiếng Anh).
  static const Map<String, Map<String, List<String>>> aliases = {
    SheetNames.users: {
      'id': ['mã', 'mã nv', 'mã nhân viên'],
      'username': ['tên đăng nhập', 'tài khoản'],
      'password': ['mật khẩu'],
      'role': ['phân quyền', 'quyền', 'vai trò'],
      'full_name': ['họ và tên', 'họ tên', 'tên nhân viên'],
      'phone': ['số điện thoại', 'sđt', 'điện thoại'],
      'is_active': ['trạng thái', 'hoạt động'],
      'created_at': ['ngày tạo'],
      'store_name': ['cửa hàng', 'tên cửa hàng', 'chi nhánh', 'cửa hàng làm việc', 'cửa hàng phụ trách'],
    },
    SheetNames.services: {
      'id': ['mã', 'mã dịch vụ'],
      'name': ['tên dịch vụ', 'tên', 'tên thiết bị'],
      'price': ['giá', 'đơn giá', 'đơn giá (vnđ)', 'giá thuê'],
      'description': ['mô tả'],
      'status': ['trạng thái'],
      'quantity': ['số lượng', 'số lượng có thể nhận', 'sl'],
    },
    SheetNames.bookings: {
      'id': ['mã đơn', 'mã'],
      'created_at': ['ngày tạo'],
      'customer_name': ['tên khách hàng', 'khách hàng', 'họ và tên khách'],
      'customer_phone': ['số điện thoại khách', 'sđt khách', 'số điện thoại'],
      'services_info': ['dịch vụ', 'thông tin dịch vụ'],
      'service_time': ['thời gian sử dụng'],
      'install_time': ['thời gian giao', 'giờ giao'],
      'collect_time': ['thời gian thu hồi', 'giờ thu hồi'],
      'location_text': ['địa chỉ', 'địa điểm'],
      'gps_location': ['gps', 'tọa độ', 'toạ độ'],
      'map_link': ['link google map', 'link bản đồ', 'link google maps'],
      'note': ['ghi chú', 'ghi chú đơn hàng'],
      'total_cost': ['tổng chi phí', 'tổng tiền'],
      'paid_amount': ['đã thanh toán', 'đã thu'],
      'submitted_to_company': ['đã nộp cty', 'đã nộp công ty'],
      'debt_amount': ['công nợ', 'chưa thanh toán'],
      'require_invoice': ['xuất hóa đơn', 'xuất hoá đơn', 'yêu cầu hóa đơn'],
      'invoice_info': ['thông tin hóa đơn', 'thông tin hoá đơn'],
      'status': ['trạng thái'],
      'assigned_user': ['nhân viên', 'người phụ trách', 'nhân viên phụ trách'],
      'created_by': ['người tạo'],
      'updated_by': ['người cập nhật'],
      'updated_at': ['cập nhật lúc'],
    },
  };
}

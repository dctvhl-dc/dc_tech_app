import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Cấu hình thương hiệu & Tên ứng dụng dùng chung (Whitelabel / Nhân bản dự án).
/// Khi tạo ứng dụng mới cho lĩnh vực mới (Cho thuê Xe, Máy ảnh, Trang phục, Đồ tiệc...):
/// Chỉ cần sửa thông tin tại file này.
class AppConfig {
  /// Tên thương hiệu / Ứng dụng
  static const String appName = 'DC TECH';

  /// Tiêu đề dịch vụ cho thuê (Ví dụ: 'Quản lý thuê loa', 'Quản lý thuê xe', 'Quản lý thiết bị'...)
  static const String appSubtitle = 'Quản lý cho thuê';

  /// Mô tả ngắn hiển thị ở màn hình đăng nhập
  static const String appDescription = 'Hệ thống quản lý dịch vụ cho thuê';

  /// Đường dẫn file Logo trong assets
  static const String logoPath = 'assets/images/logo.png';

  /// Màu sắc chủ đạo (mặc định da cam DC TECH)
  static const Color primaryColor = AppColors.orange;
  static const Color secondaryColor = AppColors.blue;

  /// Sheet ID mặc định (nếu muốn điền sẵn cho khách hàng)
  static const String? defaultSheetId = null;

  /// Credentials JSON mặc định (nếu muốn tích hợp sẵn)
  static const String? defaultCredentialsJson = null;
}

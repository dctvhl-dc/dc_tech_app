/// Vai trò + quyền (RBAC). Mọi kiểm tra quyền đặt ở đây để UI chỉ hỏi `role.canXxx`.
enum UserRole {
  superAdmin('super_admin', 'Super Admin'),
  admin('admin', 'Admin'),
  user('user', 'User');

  final String value; // giá trị lưu trong Sheet
  final String label;
  const UserRole(this.value, this.label);

  /// "Super Admin", "super_admin", "super-admin" đều nhận được.
  static UserRole fromString(String? s) {
    final n = (s ?? '').trim().toLowerCase().replaceAll(RegExp(r'[\s-]+'), '_');
    return UserRole.values.firstWhere((r) => r.value == n, orElse: () => UserRole.user);
  }

  bool get canConfigureApi => this == superAdmin;
  bool get canManageUsers => this != user;
  bool get canManageServices => this != user;
  bool get canViewReports => this != user;
  bool get canSeeAllBookings => this != user; // User chỉ thấy đơn của mình
}

class AppUser {
  final String id;
  final String username;
  final String passwordHash;
  final UserRole role;
  final String fullName;
  final String phone;
  final bool isActive;

  /// Cửa hàng đang làm việc / thực hiện.
  final String storeName;

  /// true = phải đổi mật khẩu ở lần đăng nhập kế tiếp
  /// (sau khi được reset, hoặc tài khoản mới / mật khẩu mặc định).
  final bool mustChangePassword;

  /// Thời điểm (ISO) nhân viên bấm "Quên mật khẩu"; rỗng = không có yêu cầu.
  final String resetRequested;

  const AppUser({
    required this.id,
    required this.username,
    required this.passwordHash,
    required this.role,
    this.fullName = '',
    this.phone = '',
    this.isActive = true,
    this.storeName = '',
    this.mustChangePassword = false,
    this.resetRequested = '',
  });

  AppUser copyWith({
    String? passwordHash,
    UserRole? role,
    String? fullName,
    String? phone,
    bool? isActive,
    String? storeName,
    bool? mustChangePassword,
    String? resetRequested,
  }) =>
      AppUser(
        id: id,
        username: username,
        passwordHash: passwordHash ?? this.passwordHash,
        role: role ?? this.role,
        fullName: fullName ?? this.fullName,
        phone: phone ?? this.phone,
        isActive: isActive ?? this.isActive,
        storeName: storeName ?? this.storeName,
        mustChangePassword: mustChangePassword ?? this.mustChangePassword,
        resetRequested: resetRequested ?? this.resetRequested,
      );

  /// [m] là 1 hàng từ Sheet: key = tên cột chuẩn, value = String.
  factory AppUser.fromMap(Map<String, String> m) => AppUser(
        id: m['id'] ?? '',
        username: m['username'] ?? '',
        passwordHash: m['password'] ?? '',
        role: UserRole.fromString(m['role']),
        fullName: m['full_name'] ?? '',
        phone: m['phone'] ?? '',
        isActive: _parseActive(m['is_active']),
        storeName: m['store_name'] ?? '',
        mustChangePassword: const {'true', 'có', 'co', 'yes', '1'}
            .contains((m['must_change_password'] ?? '').trim().toLowerCase()),
        resetRequested: m['reset_requested'] ?? '',
      );

  Map<String, String> toMap() => {
        'id': id,
        'username': username,
        'password': passwordHash,
        'role': role.value,
        'full_name': fullName,
        'phone': phone,
        'is_active': isActive ? 'Hoạt động' : 'Khóa',
        'store_name': storeName,
        'must_change_password': mustChangePassword ? 'TRUE' : 'FALSE',
        'reset_requested': resetRequested,
      };

  /// Ô trống => đang hoạt động. Chỉ các giá trị "khóa" mới coi là tắt.
  static bool _parseActive(String? s) {
    const off = {'false', '0', 'khóa', 'khoá', 'bị khóa', 'ngưng', 'inactive', 'locked', 'không hoạt động'};
    return !off.contains((s ?? '').trim().toLowerCase());
  }

  String get displayName => fullName.isNotEmpty ? fullName : username;
}

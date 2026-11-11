import 'package:flutter/foundation.dart';

import '../core/utils/local_config_storage.dart';
import '../core/utils/password_hasher.dart';
import '../data/models/user_model.dart';
import '../data/services/google_sheets_service.dart';

class AuthProvider extends ChangeNotifier {
  final _sheets = GoogleSheetsService.instance;

  /// Phiên đăng nhập kéo dài tối đa bao nhiêu ngày kể từ lần SỬ DỤNG CUỐI.
  static const int sessionDays = 7;

  AppUser? currentUser;
  bool loading = false;
  String? error;

  bool get isLoggedIn => currentUser != null;
  UserRole get role => currentUser?.role ?? UserRole.user;

  /// [remember] = true: nhớ tên đăng nhập + mật khẩu để điền sẵn lần sau.
  /// Dù chọn gì, đăng nhập thành công vẫn tạo phiên 7 ngày (tự đăng nhập lại).
  Future<bool> login(String username, String password, {bool remember = true}) async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      final users = await _sheets.fetchUsers();
      final byName = users.where(
          (u) => u.username.trim().toLowerCase() == username.trim().toLowerCase());
      // Log chẩn đoán (chỉ in ở chế độ debug, không in mật khẩu)
      debugPrint('[login] số user=${users.length}, '
          'tìm thấy username=${byName.isNotEmpty}, '
          'cột password dạng hash=${byName.isNotEmpty && PasswordHasher.isHashed(byName.first.passwordHash)}');

      final match = byName.where((u) => PasswordHasher.verify(password, u.passwordHash));
      if (match.isEmpty) {
        error = 'Sai tên đăng nhập hoặc mật khẩu';
      } else if (!match.first.isActive) {
        error = 'Tài khoản đã bị khóa';
      } else {
        var user = match.first;
        // Mật khẩu đang lưu dạng thô (vd: tự gõ vào Sheet để khôi phục) -> ghi lại dạng hash
        if (!PasswordHasher.isHashed(user.passwordHash)) {
          try {
            final upgraded = user.copyWith(passwordHash: PasswordHasher.hash(password));
            await _sheets.updateUser(upgraded);
            user = upgraded;
          } catch (_) {}
        }
        currentUser = user;
        try {
          await LocalConfigStorage.saveSession(userId: user.id, passwordHash: user.passwordHash);
          if (remember) {
            await LocalConfigStorage.saveCredentials(username.trim(), password);
          } else {
            await LocalConfigStorage.clearCredentials();
          }
        } catch (_) {
          // Không lưu được vào kho an toàn: vẫn cho đăng nhập, chỉ không nhớ phiên
        }
      }
    } catch (e) {
      error = e.toString();
    }
    loading = false;
    notifyListeners();
    return currentUser != null;
  }

  /// Gọi lúc mở app: nếu còn phiên (dưới [sessionDays] ngày kể từ lần dùng cuối) và tài khoản
  /// vẫn hợp lệ thì tự đăng nhập. Hết hạn / đổi mật khẩu / bị khóa -> xóa phiên, hiện màn đăng nhập.
  Future<bool> restoreSession() async {
    try {
      final s = await LocalConfigStorage.loadSession();
      if (s == null) return false;
      if (DateTime.now().difference(s.lastActive) > const Duration(days: sessionDays)) {
        await LocalConfigStorage.clearSession();
        return false;
      }
      final users = await _sheets.fetchUsers();
      final matches = users.where((u) => u.id == s.userId);
      if (matches.isEmpty ||
          !matches.first.isActive ||
          matches.first.passwordHash != s.passwordHash) {
        await LocalConfigStorage.clearSession();
        return false;
      }
      currentUser = matches.first;
      await LocalConfigStorage.touchSession();
      notifyListeners();
      return true;
    } catch (_) {
      // Lỗi mạng / kho an toàn: không xóa phiên, chỉ hiện màn hình đăng nhập
      return false;
    }
  }

  /// Ghi lại "lần sử dụng cuối" (gọi định kỳ + khi mở / ra nền app).
  void touchSession() {
    if (currentUser != null) {
      LocalConfigStorage.touchSession().catchError((_) {});
    }
  }

  /// Trả về null nếu thành công, ngược lại là thông báo lỗi.
  Future<String?> changePassword(String oldPw, String newPw) async {
    final u = currentUser;
    if (u == null) return 'Chưa đăng nhập';
    if (!PasswordHasher.verify(oldPw, u.passwordHash)) return 'Mật khẩu hiện tại không đúng';
    if (newPw.length < 6) return 'Mật khẩu mới tối thiểu 6 ký tự';
    if (newPw == oldPw) return 'Mật khẩu mới phải khác mật khẩu hiện tại';
    try {
      final updated = u.copyWith(
        passwordHash: PasswordHasher.hash(newPw),
        mustChangePassword: false, // đã đổi xong -> bỏ yêu cầu bắt buộc
        resetRequested: '',
      );
      await _sheets.updateUser(updated);
      currentUser = updated;
      try {
        await LocalConfigStorage.saveSession(userId: updated.id, passwordHash: updated.passwordHash);
        // Đang ghi nhớ mật khẩu -> cập nhật sang mật khẩu mới
        if (await LocalConfigStorage.loadCredentials() != null) {
          await LocalConfigStorage.saveCredentials(updated.username, newPw);
        }
      } catch (_) {}
      notifyListeners();
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  static String _normPhone(String s) {
    var d = s.replaceAll(RegExp(r'[^0-9]'), '');
    if (d.startsWith('84')) d = '0${d.substring(2)}';
    return d;
  }

  /// "Quên mật khẩu": ghi yêu cầu để quản trị viên cấp mật khẩu tạm.
  /// Chỉ ghi khi username + số điện thoại khớp tài khoản đang hoạt động.
  /// LUÔN trả về thành công khi không lỗi mạng, để người ngoài không dò được
  /// tài khoản nào tồn tại.
  Future<String?> requestPasswordReset(String username, String phone) async {
    try {
      final users = await _sheets.fetchUsers();
      final match = users.where((u) =>
          u.username.trim().toLowerCase() == username.trim().toLowerCase() &&
          u.isActive &&
          u.phone.isNotEmpty &&
          _normPhone(u.phone) == _normPhone(phone));
      if (match.isNotEmpty) {
        await _sheets.updateUser(match.first.copyWith(resetRequested: DateTime.now().toIso8601String()));
      }
      return null;
    } catch (e) {
      return 'Không gửi được yêu cầu: $e';
    }
  }

  /// Đăng xuất chủ động: xóa phiên (tên đăng nhập / mật khẩu đã ghi nhớ vẫn giữ để điền sẵn).
  void logout() {
    currentUser = null;
    LocalConfigStorage.clearSession().catchError((_) {});
    notifyListeners();
  }
}

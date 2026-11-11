import 'dart:convert';
import 'package:crypto/crypto.dart';

/// Không lưu mật khẩu thô trong Sheet — chỉ lưu SHA-256.
/// (Production nên dùng bcrypt/argon2 + salt qua backend riêng.)
class PasswordHasher {
  static String hash(String plain) =>
      sha256.convert(utf8.encode(plain)).toString();

  /// Chuỗi SHA-256 hex dài 64 ký tự?
  static bool isHashed(String s) => RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(s.trim());

  /// Nếu ô trong Sheet là hash -> so sánh hash.
  /// Nếu là mật khẩu thô (ai đó gõ tay vào Sheet) -> so sánh trực tiếp;
  /// AuthProvider sẽ tự nâng cấp sang hash sau khi đăng nhập thành công.
  static bool verify(String plain, String stored) {
    final s = stored.trim();
    return isHashed(s) ? hash(plain).toLowerCase() == s.toLowerCase() : plain == s;
  }
}

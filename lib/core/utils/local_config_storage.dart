import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Lưu Sheet ID + Service Account JSON trên THIẾT BỊ.
class LocalConfigStorage {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
  static const _kSheetId = 'sheet_id';
  static const _kCredentials = 'api_credentials';

  static Future<({String? sheetId, String? credentials})> load() async {
    try {
      final sheetId = await _storage.read(key: _kSheetId);
      final credentials = await _storage.read(key: _kCredentials);
      return (sheetId: sheetId, credentials: credentials);
    } catch (_) {
      try {
        await _storage.deleteAll();
      } catch (_) {}
      return (sheetId: null, credentials: null);
    }
  }

  static Future<void> save(
      {required String sheetId, required String credentials}) async {
    try {
      await _storage.write(key: _kSheetId, value: sheetId);
      await _storage.write(key: _kCredentials, value: credentials);
    } catch (_) {}
  }

  // Nhắc lịch giao / thu (lưu trên từng máy)
  static Future<({bool enabled, int leadMinutes})> loadReminder() async {
    try {
      final e = await _storage.read(key: 'reminder_enabled');
      final l = await _storage.read(key: 'reminder_lead');
      return (enabled: e != 'false', leadMinutes: int.tryParse(l ?? '') ?? 60);
    } catch (_) {
      return (enabled: true, leadMinutes: 60);
    }
  }

  static Future<void> saveReminder({required bool enabled, required int leadMinutes}) async {
    try {
      await _storage.write(key: 'reminder_enabled', value: '$enabled');
      await _storage.write(key: 'reminder_lead', value: '$leadMinutes');
    } catch (_) {}
  }

  // ───────── Phiên đăng nhập (tự đăng nhập lại) ─────────
  static const _kSessUser = 'session_user_id';
  static const _kSessPwd = 'session_pwd_hash';
  static const _kSessAt = 'session_last_active';

  /// Lưu phiên sau khi đăng nhập.
  static Future<void> saveSession({required String userId, required String passwordHash}) async {
    try {
      await _storage.write(key: _kSessUser, value: userId);
      await _storage.write(key: _kSessPwd, value: passwordHash);
      await _storage.write(key: _kSessAt, value: DateTime.now().toIso8601String());
    } catch (_) {}
  }

  static Future<({String userId, String passwordHash, DateTime lastActive})?> loadSession() async {
    try {
      final id = await _storage.read(key: _kSessUser);
      final pwd = await _storage.read(key: _kSessPwd);
      final at = DateTime.tryParse(await _storage.read(key: _kSessAt) ?? '');
      if (id == null || pwd == null || at == null) return null;
      return (userId: id, passwordHash: pwd, lastActive: at);
    } catch (_) {
      return null;
    }
  }

  /// Gia hạn phiên: ghi lại thời điểm sử dụng gần nhất.
  static Future<void> touchSession() async {
    try {
      if (await _storage.read(key: _kSessUser) == null) return;
      await _storage.write(key: _kSessAt, value: DateTime.now().toIso8601String());
    } catch (_) {}
  }

  static Future<void> clearSession() async {
    try {
      await _storage.delete(key: _kSessUser);
      await _storage.delete(key: _kSessPwd);
      await _storage.delete(key: _kSessAt);
    } catch (_) {}
  }

  // ───────── Ghi nhớ tên đăng nhập + mật khẩu ─────────
  static Future<void> saveCredentials(String username, String password) async {
    try {
      await _storage.write(key: 'saved_username', value: username);
      await _storage.write(key: 'saved_password', value: password);
    } catch (_) {}
  }

  static Future<({String username, String password})?> loadCredentials() async {
    try {
      final u = await _storage.read(key: 'saved_username');
      final p = await _storage.read(key: 'saved_password');
      if (u == null || p == null) return null;
      return (username: u, password: p);
    } catch (_) {
      return null;
    }
  }

  static Future<void> clearCredentials() async {
    try {
      await _storage.delete(key: 'saved_username');
      await _storage.delete(key: 'saved_password');
    } catch (_) {}
  }
}

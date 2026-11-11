import 'package:flutter/foundation.dart';

import '../data/models/user_model.dart';
import '../data/services/google_sheets_service.dart';

/// Danh sách nhân viên: Admin dùng để gán đơn và quản lý tài khoản.
class UserProvider extends ChangeNotifier {
  final _sheets = GoogleSheetsService.instance;
  List<AppUser> users = [];
  bool loading = false;

  Future<void> load() async {
    loading = true;
    notifyListeners();
    try {
      users = await _sheets.fetchUsers();
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<String> nextId() => _sheets.nextUserId();

  Future<void> create(AppUser u) async {
    await _sheets.saveUser(u);
    users = [...users, u];
    notifyListeners();
  }

  Future<void> update(AppUser u) async {
    await _sheets.updateUser(u);
    users = [for (final x in users) x.id == u.id ? u : x];
    notifyListeners();
  }
}

import 'package:flutter/foundation.dart';

import '../data/models/service_model.dart';
import '../data/services/google_sheets_service.dart';

/// Danh mục dịch vụ (tab "Services").
class ServiceProvider extends ChangeNotifier {
  final _sheets = GoogleSheetsService.instance;
  List<RentalService> services = [];
  bool loading = false;

  /// Chỉ các dịch vụ đang cho thuê (dùng khi tạo đơn).
  List<RentalService> get activeServices => services.where((s) => s.isActive).toList();

  Future<void> load({bool force = false}) async {
    if (services.isNotEmpty && !force) return; // cache trong phiên
    loading = true;
    notifyListeners();
    try {
      services = await _sheets.fetchServices();
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<String> nextId() => _sheets.nextServiceId();

  Future<void> save(RentalService s, {required bool isNew}) async {
    isNew ? await _sheets.addService(s) : await _sheets.updateService(s);
    final i = services.indexWhere((x) => x.id == s.id);
    if (i >= 0) {
      services[i] = s;
    } else {
      services.add(s);
    }
    notifyListeners();
  }

  Future<void> delete(String id) async {
    await _sheets.deleteService(id);
    services.removeWhere((s) => s.id == id);
    notifyListeners();
  }
}

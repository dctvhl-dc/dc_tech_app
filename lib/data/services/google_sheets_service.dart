import 'dart:math' as math;

import 'package:gsheets/gsheets.dart';

import '../../core/constants/app_constants.dart';
import '../../core/utils/password_hasher.dart';
import '../models/booking_model.dart';
import '../models/photo_model.dart';
import '../models/service_model.dart';
import '../models/user_model.dart';

class SheetsException implements Exception {
  final String message;
  SheetsException(this.message);
  @override
  String toString() => message;
}

/// Lớp duy nhất nói chuyện với Google Sheets (Singleton).
///
/// Quan trọng: service ĐỌC HÀNG TIÊU ĐỀ THỰC TẾ của từng tab và ghép với tên cột
/// chuẩn (xem SheetSchema.aliases). Vì vậy:
///  - Header tiếng Việt hay thứ tự cột khác đều dùng được.
///  - Cột còn thiếu được tự thêm vào cuối hàng tiêu đề.
///  - Cột lạ (không thuộc schema) được giữ nguyên, không bị ghi đè.
///
/// Điều kiện: Sheet phải Share cho email Service Account (quyền Editor).
class GoogleSheetsService {
  GoogleSheetsService._();
  static final GoogleSheetsService instance = GoogleSheetsService._();

  Spreadsheet? _spreadsheet;
  final Map<String, Worksheet> _sheets = {};

  /// sheet -> tên cột chuẩn của từng cột (null = cột lạ, bỏ qua).
  final Map<String, List<String?>> _cols = {};

  bool get isReady => _spreadsheet != null;

  // ───────────────────────── Kết nối ─────────────────────────

  Future<void> init({
    required String credentialsJson,
    required String spreadsheetId,
  }) async {
    try {
      final gsheets = GSheets(credentialsJson);
      _spreadsheet = await gsheets.spreadsheet(spreadsheetId);
      _sheets.clear();
      _cols.clear();
      for (final title in SheetSchema.headers.keys) {
        _sheets[title] = await _ensureWorksheet(title);
      }
      await _seedDefaultSuperAdmin();
    } catch (e) {
      _spreadsheet = null;
      throw SheetsException('Không kết nối được Google Sheets: $e');
    }
  }

  static String _norm(String s) => s.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  /// Header (tiếng Anh hoặc bí danh tiếng Việt) -> tên cột chuẩn, hoặc null.
  String? _canonicalKey(String sheet, String header) {
    final n = _norm(header);
    if (n.isEmpty) return null;
    for (final key in SheetSchema.headers[sheet]!) {
      if (key == n) return key;
    }
    for (final e in (SheetSchema.aliases[sheet] ?? const {}).entries) {
      if (e.value.contains(n)) return e.key;
    }
    return null;
  }

  Future<Worksheet> _ensureWorksheet(String title) async {
    var ws = _spreadsheet!.worksheetByTitle(title);
    ws ??= await _spreadsheet!.addWorksheet(title);

    final canonical = SheetSchema.headers[title]!;
    var header = await ws.values.row(1);
    if (header.every((c) => c.trim().isEmpty)) {
      await ws.values.insertRow(1, canonical); // tab trống -> ghi header chuẩn
      header = List<String>.from(canonical);
    }

    final cols = <String?>[for (final h in header) _canonicalKey(title, h)];
    // Thêm cột còn thiếu vào cuối hàng tiêu đề
    for (final key in canonical) {
      if (!cols.contains(key)) {
        cols.add(key);
        await ws.values.insertValue(key, column: cols.length, row: 1);
      }
    }
    _cols[title] = cols;
    return ws;
  }

  /// Sheet chưa có user nào => tạo admin/admin123 (hãy đổi mật khẩu ngay).
  Future<void> _seedDefaultSuperAdmin() async {
    if ((await fetchUsers()).isNotEmpty) return;
    await saveUser(AppUser(
      id: 'U-1',
      username: 'admin',
      passwordHash: PasswordHasher.hash('admin123'),
      role: UserRole.superAdmin,
      fullName: 'Super Admin',
      mustChangePassword: true, // bắt đổi mật khẩu mặc định ngay lần đăng nhập đầu
    ));
  }

  Worksheet _ws(String name) {
    final ws = _sheets[name];
    if (ws == null) throw SheetsException('Chưa kết nối Google Sheets.');
    return ws;
  }

  // ───────────────── CRUD generic (dựa trên header thực tế) ─────────────────

  /// Tab Settings dùng cột "key" làm khoá, các tab khác dùng "id".
  String _keyName(String sheet) => sheet == SheetNames.settings ? 'key' : 'id';

  /// Đọc toàn bộ hàng dữ liệu (bỏ header, bỏ hàng trống) thành `Map` (key là tên cột chuẩn).
  Future<List<Map<String, String>>> _getAll(String sheet) async {
    final cols = _cols[sheet]!;
    final rows = await _ws(sheet).values.allRows(fromRow: 2);
    final out = <Map<String, String>>[];
    for (final r in rows) {
      if (r.every((c) => c.trim().isEmpty)) continue;
      final m = <String, String>{};
      for (var i = 0; i < cols.length; i++) {
        final k = cols[i];
        if (k != null) m.putIfAbsent(k, () => i < r.length ? r[i].trim() : '');
      }
      out.add(m);
    }
    return out;
  }

  Future<void> _append(String sheet, Map<String, String> row) async {
    final cols = _cols[sheet]!;
    final data = {...row};
    if (cols.contains('created_at')) {
      data.putIfAbsent('created_at', () => DateTime.now().toIso8601String());
    }
    final ok = await _ws(sheet).values.appendRow([
      for (final k in cols) k == null ? '' : (data[k] ?? ''),
    ]);
    if (!ok) throw SheetsException('Ghi dữ liệu vào "$sheet" thất bại.');
  }

  /// Số thứ tự hàng (bắt đầu từ 1) của bản ghi có khoá [id]; ném lỗi nếu không thấy.
  Future<int> _findRow(String sheet, String id) async {
    final keyCol = _cols[sheet]!.indexOf(_keyName(sheet));
    final values = await _ws(sheet).values.column(keyCol + 1); // gồm header ở vị trí 0
    final index = values.indexWhere((v) => v.trim() == id);
    if (index < 1) throw SheetsException('Không tìm thấy "$id" trong "$sheet".');
    return index + 1;
  }

  /// Cập nhật hàng: chỉ ghi đè các cột có trong [row]; cột khác (kể cả cột lạ
  /// do bạn tự thêm) giữ nguyên giá trị cũ.
  Future<void> _updateById(String sheet, String id, Map<String, String> row) async {
    final ws = _ws(sheet);
    final rowNo = await _findRow(sheet, id);
    final existing = await ws.values.row(rowNo);
    final cols = _cols[sheet]!;
    final merged = <String>[];
    for (var i = 0; i < cols.length; i++) {
      final k = cols[i];
      if (k != null && row.containsKey(k)) {
        merged.add(row[k]!);
      } else {
        merged.add(i < existing.length ? existing[i] : '');
      }
    }
    final ok = await ws.values.insertRow(rowNo, merged);
    if (!ok) throw SheetsException('Cập nhật "$sheet" thất bại.');
  }

  Future<void> _deleteById(String sheet, String id) async {
    final rowNo = await _findRow(sheet, id);
    await _ws(sheet).deleteRow(rowNo);
  }

  /// Sinh mã tăng dần: TL-1001, TL-1002... (2 máy cùng lúc có thể trùng mã).
  Future<String> _nextId(String sheet, String prefix, int start,
      {String sep = '-', int pad = 0}) async {
    final keyCol = _cols[sheet]!.indexOf(_keyName(sheet));
    final ids = await _ws(sheet).values.column(keyCol + 1);
    var max = start - 1;
    for (final id in ids.skip(1)) {
      final n = int.tryParse(id.replaceAll(RegExp(r'[^0-9]'), ''));
      if (n != null && n > max) max = n;
    }
    return '$prefix$sep${(max + 1).toString().padLeft(pad, '0')}';
  }

  // ───────────────────────── Users ─────────────────────────

  Future<List<AppUser>> fetchUsers() async =>
      (await _getAll(SheetNames.users)).map(AppUser.fromMap).toList();

  Future<void> saveUser(AppUser u) => _append(SheetNames.users, u.toMap());
  Future<void> updateUser(AppUser u) => _updateById(SheetNames.users, u.id, u.toMap());
  Future<String> nextUserId() => _nextId(SheetNames.users, 'U', 1);

  // ───────────────────────── Services ─────────────────────────

  Future<List<RentalService>> fetchServices() async =>
      (await _getAll(SheetNames.services)).map(RentalService.fromMap).toList();

  Future<void> addService(RentalService s) => _append(SheetNames.services, s.toMap());
  Future<void> updateService(RentalService s) => _updateById(SheetNames.services, s.id, s.toMap());
  Future<void> deleteService(String id) => _deleteById(SheetNames.services, id);
  Future<String> nextServiceId() => _nextId(SheetNames.services, 'S', 1, sep: '', pad: 3);

  // ───────────────────────── Bookings ─────────────────────────

  /// Truyền [assignedUser] (username) để chỉ lấy đơn của nhân viên đó (role User):
  /// đơn được GIAO cho họ phụ trách, hoặc do chính họ TẠO / CẬP NHẬT.
  Future<List<Booking>> fetchBookings({String? assignedUser}) async {
    final all = (await _getAll(SheetNames.bookings)).map(Booking.fromMap);
    final list = assignedUser == null
        ? all.toList()
        : all
            .where((b) =>
                b.assignedUser == assignedUser || b.createdBy == assignedUser || b.updatedBy == assignedUser)
            .toList();
    list.sort((a, b) => b.createdAt.compareTo(a.createdAt)); // mới nhất trước
    return list;
  }

  Future<void> addBooking(Booking b) => _append(SheetNames.bookings, b.toMap());
  Future<void> updateBooking(Booking b) => _updateById(SheetNames.bookings, b.id, b.toMap());
  Future<void> deleteBooking(String id) => _deleteById(SheetNames.bookings, id);
  Future<String> nextBookingId() => _nextId(SheetNames.bookings, 'TL', 1001);

  // ───────────────────────── Settings (key/value) ─────────────────────────

  Future<Map<String, String>> fetchSettings() async {
    final rows = await _getAll(SheetNames.settings);
    return {for (final r in rows) r['key'] ?? '': r['value'] ?? ''};
  }

  Future<void> saveSetting(String key, String value) async {
    final exists = (await _getAll(SheetNames.settings)).any((r) => r['key'] == key);
    final row = {'key': key, 'value': value};
    exists ? await _updateById(SheetNames.settings, key, row) : await _append(SheetNames.settings, row);
  }

  // ───────────────────────── Photos (ảnh giao / thu hồi) ─────────────────────────
  //
  // Ảnh được nén nhỏ rồi lưu base64 trong tab "Photos". Một ô Sheets tối đa 50.000
  // ký tự nên mỗi ảnh được chia thành nhiều dòng (cột `part`). KHÔNG đọc cả tab
  // này bằng _getAll (rất nặng) — chỉ đọc đúng các dòng của 1 đơn.

  Map<String, String> _rowToMap(String sheet, List<String> r) {
    final cols = _cols[sheet]!;
    final m = <String, String>{};
    for (var i = 0; i < cols.length; i++) {
      final k = cols[i];
      if (k != null) m.putIfAbsent(k, () => i < r.length ? r[i].trim() : '');
    }
    return m;
  }

  Future<List<BookingPhoto>> fetchPhotos(String bookingId) async {
    final ws = _ws(SheetNames.photos);
    final col = _cols[SheetNames.photos]!.indexOf('booking_id');
    final ids = await ws.values.column(col + 1); // chỉ tải cột booking_id (nhẹ)
    final rowNos = [for (var i = 1; i < ids.length; i++) if (ids[i].trim() == bookingId) i + 1];
    if (rowNos.isEmpty) return [];
    final rows = await Future.wait(
      rowNos.map((n) async => _rowToMap(SheetNames.photos, await ws.values.row(n))),
    );
    return BookingPhoto.fromRows(rows);
  }

  /// Ghi tuần tự từng dòng (các phần của 1 ảnh nằm liền nhau).
  Future<void> addPhoto(BookingPhoto p) async {
    for (final row in p.toRows()) {
      await _append(SheetNames.photos, row);
    }
  }

  /// Xóa mọi dòng của ảnh; xóa từ dưới lên để chỉ số hàng không bị lệch.
  Future<void> deletePhoto(String photoId) async {
    final ws = _ws(SheetNames.photos);
    final col = _cols[SheetNames.photos]!.indexOf('id');
    final ids = await ws.values.column(col + 1);
    final rows = [for (var i = 1; i < ids.length; i++) if (ids[i].trim() == photoId) i + 1];
    for (final r in rows.reversed) {
      await ws.deleteRow(r);
    }
  }

  // ───────────────────── Dọn ảnh cũ ─────────────────────

  /// Quét các ảnh có `taken_at` cũ hơn [cutoff]. Chỉ tính phần cũ LIỀN NHAU ở đầu tab
  /// (dừng ở dòng đầu tiên không cũ) để xóa được bằng 1 lệnh.
  Future<PhotoCleanupPlan> planPhotoCleanup(DateTime cutoff) async {
    final ws = _ws(SheetNames.photos);
    final cols = _cols[SheetNames.photos]!;
    final taken = await ws.values.column(cols.indexOf('taken_at') + 1, fromRow: 2);
    var k = 0;
    DateTime? oldest;
    for (final v in taken) {
      final d = DateTime.tryParse(v.trim());
      if (d == null || !d.isBefore(cutoff)) break;
      oldest ??= d;
      k++;
    }
    if (k == 0) return const PhotoCleanupPlan(0, 0, null);
    final ids = await ws.values.column(cols.indexOf('id') + 1, fromRow: 2, length: k);
    return PhotoCleanupPlan(k, ids.where((i) => i.trim().isNotEmpty).toSet().length, oldest);
  }

  /// Đọc [rows] dòng đầu của tab Photos thành danh sách ảnh (để xuất ZIP).
  /// Cột `data` rất nặng nên đọc từng đợt 40 dòng.
  Future<List<BookingPhoto>> fetchPhotoBlock(int rows, {void Function(int done, int total)? onProgress}) async {
    final ws = _ws(SheetNames.photos);
    final cols = _cols[SheetNames.photos]!;
    final result = <Map<String, String>>[for (var i = 0; i < rows; i++) <String, String>{}];
    for (final key in const ['id', 'booking_id', 'type', 'taken_at', 'taken_by', 'part', 'data']) {
      final colIdx = cols.indexOf(key) + 1;
      final step = key == 'data' ? 40 : rows;
      var offset = 0;
      while (offset < rows) {
        final len = math.min(step, rows - offset);
        final values = await ws.values.column(colIdx, fromRow: 2 + offset, length: len);
        for (var i = 0; i < values.length && offset + i < rows; i++) {
          result[offset + i][key] = values[i];
        }
        offset += len;
        if (key == 'data') onProgress?.call(offset, rows);
      }
    }
    return BookingPhoto.fromRows(result);
  }

  /// Xóa [rows] dòng đầu (dữ liệu) của tab Photos bằng 1 lệnh.
  Future<void> deletePhotoBlock(int rows) async {
    final ok = await _ws(SheetNames.photos).deleteRow(2, count: rows);
    if (!ok) throw SheetsException('Không xóa được ảnh cũ trong tab Photos.');
  }
}

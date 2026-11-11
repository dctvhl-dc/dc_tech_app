import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/services/reminder_service.dart';
import '../data/models/booking_model.dart';
import '../data/models/photo_model.dart';
import '../data/models/user_model.dart';
import '../data/services/google_sheets_service.dart';

class BookingProvider extends ChangeNotifier {
  final _sheets = GoogleSheetsService.instance;
  List<Booking> bookings = [];
  bool loading = false;
  String? _loadedFor; // username của lần tải gần nhất

  /// RBAC ở tầng dữ liệu: role User chỉ tải đơn của chính mình.
  Future<void> load(AppUser viewer) async {
    // Đổi tài khoản -> bỏ dữ liệu cũ để không lộ đơn của người trước
    if (_loadedFor != viewer.username) bookings = [];
    _loadedFor = viewer.username;
    loading = true;
    notifyListeners();
    try {
      bookings = await _sheets.fetchBookings(
        assignedUser: viewer.role.canSeeAllBookings ? null : viewer.username,
      );
      unawaited(ReminderService.instance.sync(bookings));
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<String> nextId() => _sheets.nextBookingId();

  Future<void> save(Booking b, {required bool isNew}) async {
    isNew ? await _sheets.addBooking(b) : await _sheets.updateBooking(b);
    final i = bookings.indexWhere((x) => x.id == b.id);
    if (i >= 0) {
      bookings[i] = b;
    } else {
      bookings.insert(0, b);
    }
    notifyListeners();
    unawaited(ReminderService.instance.sync(bookings));
  }

  /// Thao tác nhanh của User: Giao loa / Thu loa.
  Future<void> changeStatus(Booking b, BookingStatus s) =>
      save(b.copyWith(status: s), isNew: false);

  /// Hủy đơn hàng kèm lý do (chỉ dành cho đơn chưa giao).
  Future<void> cancelBooking(Booking b, String reason, String username) => save(
        b.copyWith(
          status: BookingStatus.cancelled,
          cancelReason: reason,
          updatedBy: username,
          updatedAt: DateTime.now(),
        ),
        isNew: false,
      );

  /// TẤT CẢ đơn (kể cả của người khác) — chỉ dùng để kiểm tra trùng lịch / tồn kho,
  /// không lưu vào danh sách hiển thị.
  Future<List<Booking>> fetchAll() => _sheets.fetchBookings();

  // Ảnh giao / thu hồi
  Future<List<BookingPhoto>> loadPhotos(String bookingId) => _sheets.fetchPhotos(bookingId);
  Future<void> addPhoto(BookingPhoto p) => _sheets.addPhoto(p);
  Future<void> deletePhoto(String photoId) => _sheets.deletePhoto(photoId);
}

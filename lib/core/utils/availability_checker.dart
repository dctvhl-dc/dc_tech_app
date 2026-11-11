import '../../data/models/booking_model.dart';
import '../../data/models/service_model.dart';

/// Một cảnh báo thiếu thiết bị trong khoảng thời gian của đơn.
class StockConflict {
  final RentalService service;
  final int needed; // số lượng đơn này cần
  final int alreadyUsed; // số lượng lớn nhất các đơn khác đang giữ cùng lúc
  final DateTime at; // thời điểm bị chiếm nhiều nhất
  final List<String> bookingIds; // các đơn đang giữ thiết bị
  const StockConflict(this.service, this.needed, this.alreadyUsed, this.at, this.bookingIds);

  int get capacity => service.quantity;
  int get available => capacity - alreadyUsed < 0 ? 0 : capacity - alreadyUsed;
}

/// Kiểm tra trùng lịch theo SỐ LƯỢNG: dịch vụ có `quantity = 3` thì tối đa 3 đơn
/// (hoặc tổng 3 chiếc) được giữ cùng lúc.
/// Chỉ tính các đơn chưa trả loa; khoảng giữ = [thời gian giao, thời gian thu hồi).
class AvailabilityChecker {
  /// Ghép dòng dịch vụ trong đơn với danh mục: theo mã, không có thì theo tên.
  static RentalService? resolve(BookingServiceItem it, List<RentalService> catalog) {
    if (it.serviceId != null) {
      for (final s in catalog) {
        if (s.id == it.serviceId) return s;
      }
    }
    final n = it.name.trim().toLowerCase();
    for (final s in catalog) {
      if (s.name.trim().toLowerCase() == n) return s;
    }
    return null;
  }

  static List<StockConflict> check({
    required DateTime start,
    required DateTime end,
    required List<BookingServiceItem> lines,
    required List<Booking> all,
    required List<RentalService> catalog,
    String? excludeBookingId, // đơn đang sửa
  }) {
    // Số lượng đơn này cần theo từng dịch vụ (bỏ qua dịch vụ chưa khai báo số lượng)
    final need = <String, int>{};
    final byId = <String, RentalService>{};
    for (final it in lines) {
      final s = resolve(it, catalog);
      if (s == null || s.quantity <= 0) continue;
      need[s.id] = (need[s.id] ?? 0) + it.qty;
      byId[s.id] = s;
    }
    if (need.isEmpty) return [];

    final others = all
        .where((b) =>
            b.id != excludeBookingId &&
            b.status != BookingStatus.returned &&
            b.installTime != null &&
            b.collectTime != null &&
            b.installTime!.isBefore(end) &&
            b.collectTime!.isAfter(start))
        .toList();

    final out = <StockConflict>[];
    for (final e in need.entries) {
      final s = byId[e.key]!;
      // Số lượng dịch vụ này trong từng đơn khác
      final usage = <Booking, int>{};
      for (final b in others) {
        var q = 0;
        for (final it in b.services) {
          if (resolve(it, catalog)?.id == s.id) q += it.qty;
        }
        if (q > 0) usage[b] = q;
      }
      if (usage.isEmpty) {
        if (e.value > s.quantity) out.add(StockConflict(s, e.value, 0, start, const []));
        continue;
      }
      // Mức chiếm dụng cao nhất xảy ra tại thời điểm bắt đầu của một đơn nào đó
      final times = <DateTime>{start, for (final b in usage.keys) if (b.installTime!.isAfter(start)) b.installTime!};
      var peak = 0;
      var peakAt = start;
      var peakIds = <String>[];
      for (final t in times) {
        var sum = 0;
        final ids = <String>[];
        usage.forEach((b, q) {
          if (!b.installTime!.isAfter(t) && b.collectTime!.isAfter(t)) {
            sum += q;
            ids.add(b.id);
          }
        });
        if (sum > peak) {
          peak = sum;
          peakAt = t;
          peakIds = ids;
        }
      }
      if (peak + e.value > s.quantity) out.add(StockConflict(s, e.value, peak, peakAt, peakIds));
    }
    return out;
  }
}

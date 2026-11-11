import '../../data/models/booking_model.dart';

/// Một việc cần làm: giao hoặc thu hồi loa.
class TaskItem {
  final Booking booking;
  final bool isDelivery;
  final DateTime time;
  final bool overdue; // đã quá giờ mà chưa làm
  const TaskItem(this.booking, this.isDelivery, this.time, this.overdue);

  /// Nhãn hiển thị: Quá giờ / Chuẩn bị (≤ 2 giờ nữa) / Chờ giao / Chờ thu.
  String statusLabel(DateTime now) {
    if (overdue) return 'Quá giờ';
    if (time.difference(now).inMinutes <= 120) return 'Chuẩn bị';
    return isDelivery ? 'Chờ giao' : 'Chờ thu';
  }
}

class ScheduleUtils {
  static bool sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

  static List<TaskItem> _tasks(List<Booking> all, DateTime now, bool delivery) {
    final startOfToday = DateTime(now.year, now.month, now.day);
    final out = <TaskItem>[];
    for (final b in all) {
      final wanted = delivery ? BookingStatus.pending : BookingStatus.delivered;
      if (b.status != wanted) continue;
      final t = delivery ? b.installTime : b.collectTime;
      if (t == null) continue;
      // Hôm nay, hoặc các ngày trước mà vẫn chưa xử lý (quá hạn)
      if (sameDay(t, now) || t.isBefore(startOfToday)) {
        out.add(TaskItem(b, delivery, t, t.isBefore(now)));
      }
    }
    out.sort((a, b) => a.time.compareTo(b.time));
    return out;
  }

  /// Cần giao: đơn "Chưa giao" có giờ giao hôm nay hoặc đã quá hạn.
  static List<TaskItem> deliveries(List<Booking> all, DateTime now) => _tasks(all, now, true);

  /// Cần thu: đơn "Đã giao loa" có giờ thu hồi hôm nay hoặc đã quá hạn.
  static List<TaskItem> collections(List<Booking> all, DateTime now) => _tasks(all, now, false);
}

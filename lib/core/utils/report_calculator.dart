import '../../data/models/booking_model.dart';

enum PeriodType { month, quarter, year }

/// Kỳ báo cáo: tháng (1-12), quý (1-4) hoặc cả năm.
class ReportPeriod {
  final PeriodType type;
  final int year;
  final int number; // tháng hoặc quý; bỏ qua nếu type == year
  const ReportPeriod(this.type, this.year, this.number);

  bool contains(DateTime d) {
    if (d.year != year) return false;
    return switch (type) {
      PeriodType.month => d.month == number,
      PeriodType.quarter => ((d.month - 1) ~/ 3) + 1 == number,
      PeriodType.year => true,
    };
  }

  String get label => switch (type) {
        PeriodType.month => 'Tháng ${number.toString().padLeft(2, '0')}/$year',
        PeriodType.quarter => 'Quý $number/$year',
        PeriodType.year => 'Năm $year',
      };
}

/// Số liệu tổng hợp. Các phần được chia để KHÔNG chồng lấn:
///   doanh thu = đã nộp cty + NV đang giữ (đã thu, chưa nộp) + công nợ (chưa thu)
class ReportSummary {
  final int count;
  final int revenue; // tổng chi phí các đơn
  final int paid; // đã thu từ khách
  final int debt; // chưa thu = công nợ
  final int submitted; // đã nộp về công ty
  final int holding; // đã thu nhưng nhân viên chưa nộp cty
  const ReportSummary(this.count, this.revenue, this.paid, this.debt, this.submitted, this.holding);
}

class UserStat {
  final String username;
  final int count;
  final int revenue;
  final int debt;
  final int deliveryCount; // số lần giao loa
  final int collectionCount; // số lần thu hồi loa

  const UserStat(
    this.username,
    this.count,
    this.revenue,
    this.debt, {
    this.deliveryCount = 0,
    this.collectionCount = 0,
  });
}

class ReportCalculator {
  /// Ngày ghi nhận doanh thu: ngày giao; nếu chưa có thì ngày sử dụng, rồi ngày tạo đơn.
  static DateTime recordDate(Booking b) => b.installTime ?? b.serviceTime ?? b.createdAt;

  static List<Booking> filter(List<Booking> all, ReportPeriod p, {String? username}) => all
      .where((b) => p.contains(recordDate(b)) && (username == null || b.assignedUser == username))
      .toList();

  static int _pos(int v) => v < 0 ? 0 : v;

  static ReportSummary summarize(List<Booking> list) {
    var revenue = 0, paid = 0, debt = 0, submitted = 0, holding = 0;
    for (final b in list) {
      revenue += b.totalCost;
      paid += b.paidAmount;
      debt += _pos(b.debtAmount);
      submitted += b.submittedToCompany;
      holding += _pos(b.pendingToCompany);
    }
    return ReportSummary(list.length, revenue, paid, debt, submitted, holding);
  }

  /// Xếp hạng nhân viên theo doanh thu giảm dần + thống kê số lần giao/thu loa.
  static List<UserStat> rankByUser(List<Booking> list) {
    final map = <String, List<Booking>>{};
    for (final b in list) {
      map.putIfAbsent(b.assignedUser.isEmpty ? '(chưa gán)' : b.assignedUser, () => []).add(b);
    }
    final out = [
      for (final e in map.entries)
        UserStat(
          e.key,
          e.value.length,
          e.value.fold<int>(0, (s, b) => s + b.totalCost),
          e.value.fold<int>(0, (s, b) => s + _pos(b.debtAmount)),
          deliveryCount: e.value.where((b) => b.status == BookingStatus.delivered || b.status == BookingStatus.returned || b.installTime != null).length,
          collectionCount: e.value.where((b) => b.status == BookingStatus.returned).length,
        )
    ];
    out.sort((a, b) => b.revenue.compareTo(a.revenue));
    return out;
  }
}

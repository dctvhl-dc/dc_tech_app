import 'dart:typed_data';

import '../../data/models/booking_model.dart';
import 'formatters.dart';
import 'report_calculator.dart';
import 'xlsx_writer.dart';

/// Dựng file Excel báo cáo gồm 3 sheet: Tổng hợp / Theo nhân viên / Chi tiết đơn.
class ReportExporter {
  static Uint8List build({
    required ReportPeriod period,
    required String userLabel,
    required ReportSummary summary,
    required List<UserStat> ranking,
    required List<Booking> bookings,
    required Map<String, String> names, // username -> tên hiển thị
  }) {
    String nameOf(String u) => names[u] ?? u;

    final summarySheet = XlsxSheet(
      'Tổng hợp',
      [
        ['BÁO CÁO DOANH THU - DC TECH'],
        ['Kỳ báo cáo', period.label],
        ['Nhân viên', userLabel],
        ['Ngày xuất', Fmt.dateTime(DateTime.now())],
        <Object?>[],
        ['Chỉ tiêu', 'Giá trị'],
        ['Số đơn hàng', summary.count],
        ['Doanh thu (VNĐ)', summary.revenue],
        ['Đã thu (VNĐ)', summary.paid],
        ['Công nợ - chưa thu (VNĐ)', summary.debt],
        ['Đã nộp công ty (VNĐ)', summary.submitted],
        ['NV đang giữ - chưa nộp (VNĐ)', summary.holding],
      ],
      boldRows: {0, 5},
      widths: [34, 24],
    );

    final rankSheet = XlsxSheet(
      'Theo nhân viên',
      [
        ['Hạng', 'Nhân viên', 'Số đơn', 'Giao loa (lần)', 'Thu loa (lần)', 'Doanh thu (VNĐ)', 'Công nợ (VNĐ)'],
        for (var i = 0; i < ranking.length; i++)
          [
            i + 1,
            nameOf(ranking[i].username),
            ranking[i].count,
            ranking[i].deliveryCount,
            ranking[i].collectionCount,
            ranking[i].revenue,
            ranking[i].debt,
          ],
      ],
      boldRows: {0},
      widths: [8, 26, 10, 14, 14, 20, 20],
    );

    final sorted = [...bookings]
      ..sort((a, b) => ReportCalculator.recordDate(a).compareTo(ReportCalculator.recordDate(b)));
    final detailSheet = XlsxSheet(
      'Chi tiết đơn',
      [
        [
          'Mã đơn', 'Ngày giao', 'Khách hàng', 'SĐT', 'Dịch vụ', 'Tổng chi phí',
          'Đã thanh toán', 'Công nợ', 'Đã nộp cty', 'Trạng thái', 'Nhân viên',
        ],
        for (final b in sorted)
          [
            b.id,
            Fmt.dateTime(ReportCalculator.recordDate(b)),
            b.customerName,
            b.customerPhone, // dạng chuỗi -> giữ số 0 đầu
            b.services.map((s) => s.qty > 1 ? '${s.name} ×${s.qty}' : s.name).join(', '),
            b.totalCost,
            b.paidAmount,
            b.debtAmount < 0 ? 0 : b.debtAmount,
            b.submittedToCompany,
            b.status.label,
            nameOf(b.assignedUser),
          ],
      ],
      boldRows: {0},
      widths: [12, 20, 24, 14, 36, 16, 16, 14, 14, 14, 20],
    );

    return XlsxWriter.build([summarySheet, rankSheet, detailSheet]);
  }
}

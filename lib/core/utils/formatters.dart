import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

/// Các hàm format dùng chung (tiền VND, ngày giờ).
class Fmt {
  static final _num = NumberFormat.decimalPattern('vi_VN'); // 1.200.000
  static final _dt = DateFormat('HH:mm - dd/MM/yyyy');

  static String thousands(int v) => _num.format(v);
  static String money(int v) => '${_num.format(v)} đ';
  static String dateTime(DateTime? d) => d == null ? 'Chọn thời gian' : _dt.format(d);

  /// "1.200.000 đ" -> 1200000
  static int parseMoney(String s) =>
      int.tryParse(s.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
}

/// Tự chèn dấu chấm ngăn cách hàng nghìn khi gõ số tiền.
class ThousandsInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue old, TextEditingValue neu) {
    final digits = neu.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return const TextEditingValue(text: '');
    final text = Fmt.thousands(int.parse(digits));
    return TextEditingValue(
        text: text, selection: TextSelection.collapsed(offset: text.length));
  }
}

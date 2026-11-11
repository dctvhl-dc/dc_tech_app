/// Đọc số tiền bằng chữ tiếng Việt: 1250000 -> "Một triệu hai trăm năm mươi nghìn đồng".
class VnNumber {
  static const _digits = ['không', 'một', 'hai', 'ba', 'bốn', 'năm', 'sáu', 'bảy', 'tám', 'chín'];

  /// Đọc một nhóm 3 chữ số (0-999). [full] = true khi cần đọc đủ hàng trăm
  /// (nhóm không phải nhóm đầu tiên): 5 -> "không trăm lẻ năm".
  static String _group(int n, {required bool full}) {
    final h = n ~/ 100, t = (n % 100) ~/ 10, o = n % 10;
    final parts = <String>[];
    if (h > 0 || full) parts.add('${_digits[h]} trăm');
    if (t > 1) {
      parts.add('${_digits[t]} mươi');
    } else if (t == 1) {
      parts.add('mười');
    } else if (o > 0 && (h > 0 || full)) {
      parts.add('lẻ');
    }
    if (o > 0) {
      if (o == 1 && t > 1) {
        parts.add('mốt');
      } else if (o == 5 && t > 0) {
        parts.add('lăm');
      } else if (o == 4 && t > 1) {
        parts.add('tư');
      } else {
        parts.add(_digits[o]);
      }
    }
    return parts.join(' ');
  }

  static String money(int amount) {
    if (amount <= 0) return 'Không đồng';
    const units = ['', ' nghìn', ' triệu', ' tỷ'];
    final groups = <int>[];
    var n = amount;
    while (n > 0) {
      groups.add(n % 1000);
      n ~/= 1000;
    }
    final parts = <String>[];
    for (var i = groups.length - 1; i >= 0; i--) {
      final g = groups[i];
      if (g == 0) continue;
      final unit = i < units.length ? units[i] : '';
      final isLeading = parts.isEmpty;
      parts.add('${_group(g, full: !isLeading)}$unit');
    }
    final text = '${parts.join(' ')} đồng';
    return text[0].toUpperCase() + text.substring(1);
  }
}

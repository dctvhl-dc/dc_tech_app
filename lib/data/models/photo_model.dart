import 'dart:convert';
import 'dart:typed_data';

enum PhotoType {
  delivery('giao', 'Ảnh khi giao loa'),
  returned('tra', 'Ảnh khi thu hồi / trả loa');

  final String value; // giá trị lưu trong Sheet
  final String label;
  const PhotoType(this.value, this.label);

  static PhotoType fromString(String? s) => PhotoType.values
      .firstWhere((t) => t.value == (s ?? '').trim().toLowerCase(), orElse: () => PhotoType.delivery);
}

/// Mỗi loại ảnh (giao / thu hồi) tối đa bao nhiêu tấm cho 1 đơn — để Sheet không phình quá nhanh.
const int kMaxPhotosPerType = 3;

class BookingPhoto {
  final String id;
  final String bookingId;
  final PhotoType type;
  final DateTime takenAt;
  final String takenBy; // username người chụp
  final Uint8List bytes; // JPEG đã nén

  const BookingPhoto({
    required this.id,
    required this.bookingId,
    required this.type,
    required this.takenAt,
    required this.takenBy,
    required this.bytes,
  });

  /// Ảnh chụp trước khi đơn có mã -> gán mã đơn lúc lưu.
  BookingPhoto withBooking(String bookingId) => BookingPhoto(
        id: id,
        bookingId: bookingId,
        type: type,
        takenAt: takenAt,
        takenBy: takenBy,
        bytes: bytes,
      );

  // Giới hạn 1 ô Google Sheets là 50.000 ký tự -> mỗi phần tối đa 45.000.
  static const int _chunkChars = 45000;
  // Tiền tố an toàn: tránh ô bắt đầu bằng + hoặc = bị Sheets hiểu là công thức.
  static const String _prefix = 'x';

  /// Chia ảnh (base64) thành nhiều dòng, mỗi dòng 1 phần.
  List<Map<String, String>> toRows() {
    final b64 = base64Encode(bytes);
    final rows = <Map<String, String>>[];
    for (var i = 0, part = 0; i < b64.length; i += _chunkChars, part++) {
      final end = i + _chunkChars > b64.length ? b64.length : i + _chunkChars;
      rows.add({
        'id': id,
        'booking_id': bookingId,
        'type': type.value,
        'taken_at': takenAt.toIso8601String(),
        'taken_by': takenBy,
        'part': '$part',
        'data': '$_prefix${b64.substring(i, end)}',
      });
    }
    return rows;
  }

  /// Ghép các dòng (có thể của nhiều ảnh) lại thành danh sách ảnh.
  static List<BookingPhoto> fromRows(List<Map<String, String>> rows) {
    final groups = <String, List<Map<String, String>>>{};
    for (final r in rows) {
      final id = r['id'] ?? '';
      if (id.isNotEmpty) groups.putIfAbsent(id, () => []).add(r);
    }
    final out = <BookingPhoto>[];
    for (final g in groups.values) {
      g.sort((a, b) => (int.tryParse(a['part'] ?? '') ?? 0).compareTo(int.tryParse(b['part'] ?? '') ?? 0));
      final data = g.map((r) {
        final d = r['data'] ?? '';
        return d.startsWith(_prefix) ? d.substring(_prefix.length) : d;
      }).join();
      try {
        out.add(BookingPhoto(
          id: g.first['id']!,
          bookingId: g.first['booking_id'] ?? '',
          type: PhotoType.fromString(g.first['type']),
          takenAt: DateTime.tryParse(g.first['taken_at'] ?? '') ?? DateTime.now(),
          takenBy: g.first['taken_by'] ?? '',
          bytes: base64Decode(data),
        ));
      } catch (_) {
        // ảnh hỏng / thiếu phần: bỏ qua thay vì làm lỗi cả màn hình
      }
    }
    out.sort((a, b) => a.takenAt.compareTo(b.takenAt));
    return out;
  }
}

/// Kết quả quét ảnh cũ: các dòng cũ nằm liền nhau ở đầu tab Photos
/// (ảnh luôn được ghi nối tiếp theo thời gian) nên xóa được bằng 1 lệnh.
class PhotoCleanupPlan {
  final int rows; // số dòng cũ (mỗi ảnh có thể chiếm nhiều dòng)
  final int photos; // số ảnh cũ
  final DateTime? oldest;
  const PhotoCleanupPlan(this.rows, this.photos, this.oldest);
}

import 'dart:convert';
import 'dart:typed_data';

/// Ghi file ZIP kiểu "stored" (không nén) từ dữ liệu nhị phân.
/// Dùng để xuất ảnh JPEG (vốn đã nén) — không cần package ngoài.
class ZipWriter {
  static final List<int> _crcTable = List<int>.generate(256, (n) {
    var c = n;
    for (var k = 0; k < 8; k++) {
      c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
    }
    return c;
  });

  static int _crc32(List<int> data) {
    var c = 0xFFFFFFFF;
    for (final b in data) {
      c = _crcTable[(c ^ b) & 0xFF] ^ (c >> 8);
    }
    return c ^ 0xFFFFFFFF;
  }

  static List<int> _u16(int v) => [v & 0xFF, (v >> 8) & 0xFF];
  static List<int> _u32(int v) => [v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, (v >> 24) & 0xFF];

  /// [files]: đường dẫn trong ZIP (UTF-8, dùng "/" để tạo thư mục) -> nội dung.
  static Uint8List build(Map<String, Uint8List> files) {
    final out = BytesBuilder();
    final central = BytesBuilder();
    var count = 0;
    const dosDate = 0x21; // 01/01/1980
    files.forEach((name, data) {
      final nameBytes = utf8.encode(name);
      final crc = _crc32(data);
      final offset = out.length;
      out
        ..add(_u32(0x04034b50))
        ..add(_u16(20))
        ..add(_u16(0x0800)) // tên file UTF-8
        ..add(_u16(0)) // stored
        ..add(_u16(0))
        ..add(_u16(dosDate))
        ..add(_u32(crc))
        ..add(_u32(data.length))
        ..add(_u32(data.length))
        ..add(_u16(nameBytes.length))
        ..add(_u16(0))
        ..add(nameBytes)
        ..add(data);
      central
        ..add(_u32(0x02014b50))
        ..add(_u16(20))
        ..add(_u16(20))
        ..add(_u16(0x0800))
        ..add(_u16(0))
        ..add(_u16(0))
        ..add(_u16(dosDate))
        ..add(_u32(crc))
        ..add(_u32(data.length))
        ..add(_u32(data.length))
        ..add(_u16(nameBytes.length))
        ..add(_u16(0))
        ..add(_u16(0))
        ..add(_u16(0))
        ..add(_u16(0))
        ..add(_u32(0))
        ..add(_u32(offset))
        ..add(nameBytes);
      count++;
    });
    final cdOffset = out.length;
    final cd = central.toBytes();
    out
      ..add(cd)
      ..add(_u32(0x06054b50))
      ..add(_u16(0))
      ..add(_u16(0))
      ..add(_u16(count))
      ..add(_u16(count))
      ..add(_u32(cd.length))
      ..add(_u32(cdOffset))
      ..add(_u16(0));
    return out.toBytes();
  }
}

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Tạo PDF 1 trang từ ảnh RGB (không cần package ngoài).
/// Phiếu in được vẽ thành ảnh bằng Flutter (hiển thị đúng tiếng Việt),
/// rồi nhúng vào trang PDF khổ [pageWidth] x [pageHeight] điểm (1pt = 1/72 inch).
class PdfWriter {
  static Uint8List fromRgb({
    required Uint8List rgb, // width*height*3 byte
    required int width,
    required int height,
    required double pageWidth,
    required double pageHeight,
  }) {
    final out = BytesBuilder();
    final offsets = <int>[];

    void add(String s) => out.add(ascii.encode(s));
    void obj(int n, String dict, {Uint8List? stream}) {
      offsets.add(out.length);
      add('$n 0 obj\n');
      if (stream == null) {
        add('$dict\nendobj\n');
      } else {
        add('${dict.replaceFirst('>>', '/Length ${stream.length} >>')}\nstream\n');
        out.add(stream);
        add('\nendstream\nendobj\n');
      }
    }

    final w = pageWidth.toStringAsFixed(2);
    final h = pageHeight.toStringAsFixed(2);
    final image = Uint8List.fromList(zlib.encode(rgb)); // FlateDecode = zlib
    final content = Uint8List.fromList(ascii.encode('q $w 0 0 $h 0 0 cm /Im0 Do Q'));

    add('%PDF-1.4\n');
    obj(1, '<< /Type /Catalog /Pages 2 0 R >>');
    obj(2, '<< /Type /Pages /Kids [3 0 R] /Count 1 >>');
    obj(3, '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 $w $h] '
        '/Resources << /XObject << /Im0 4 0 R >> >> /Contents 5 0 R >>');
    obj(4, '<< /Type /XObject /Subtype /Image /Width $width /Height $height '
        '/ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /FlateDecode >>', stream: image);
    obj(5, '<< >>', stream: content);

    final xrefPos = out.length;
    add('xref\n0 6\n0000000000 65535 f \n');
    for (final o in offsets) {
      add('${o.toString().padLeft(10, '0')} 00000 n \n');
    }
    add('trailer\n<< /Size 6 /Root 1 0 R >>\nstartxref\n$xrefPos\n%%EOF\n');
    return out.toBytes();
  }
}

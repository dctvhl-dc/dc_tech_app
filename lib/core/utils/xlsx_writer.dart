import 'dart:convert';
import 'dart:typed_data';

/// Một sheet: [rows] là lưới giá trị. int/double -> ô số (định dạng #,##0),
/// còn lại -> ô chuỗi. null / hàng rỗng -> bỏ qua.
class XlsxSheet {
  final String name;
  final List<List<Object?>> rows;
  final Set<int> boldRows; // chỉ số hàng (từ 0) in đậm
  final List<double> widths; // độ rộng từng cột
  const XlsxSheet(this.name, this.rows, {this.boldRows = const {}, this.widths = const []});
}

/// Ghi file .xlsx tối thiểu (nhiều sheet) — không cần package ngoài.
/// .xlsx thực chất là file ZIP chứa các file XML; ở đây ghi ZIP kiểu "stored"
/// (không nén) nên rất đơn giản, file báo cáo vốn nhỏ.
class XlsxWriter {
  static Uint8List build(List<XlsxSheet> sheets) {
    final files = <String, String>{
      '[Content_Types].xml': _contentTypes(sheets.length),
      '_rels/.rels': _rootRels,
      'xl/workbook.xml': _workbook(sheets),
      'xl/_rels/workbook.xml.rels': _workbookRels(sheets.length),
      'xl/styles.xml': _styles,
      for (var i = 0; i < sheets.length; i++) 'xl/worksheets/sheet${i + 1}.xml': _sheetXml(sheets[i]),
    };
    return _zip(files);
  }

  // ───────────── XML ─────────────

  static const _xmlHead = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>';
  static const _ns = 'http://schemas.openxmlformats.org/spreadsheetml/2006/main';
  static const _rel = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships';

  static String _esc(String s) => s
      .replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]'), '')
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');

  static String _sheetName(String s) {
    final clean = s.replaceAll(RegExp(r'[\[\]:*?/\\]'), ' ').trim();
    return clean.length > 31 ? clean.substring(0, 31) : clean;
  }

  /// 0 -> A, 25 -> Z, 26 -> AA
  static String _col(int i) {
    var s = '';
    var n = i + 1;
    while (n > 0) {
      final r = (n - 1) % 26;
      s = String.fromCharCode(65 + r) + s;
      n = (n - 1) ~/ 26;
    }
    return s;
  }

  static String _contentTypes(int n) => '$_xmlHead'
      '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
      '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
      '<Default Extension="xml" ContentType="application/xml"/>'
      '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
      '${[for (var i = 1; i <= n; i++) '<Override PartName="/xl/worksheets/sheet$i.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'].join()}'
      '<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>'
      '</Types>';

  static const _rootRels = '$_xmlHead'
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
      '<Relationship Id="rId1" Type="$_rel/officeDocument" Target="xl/workbook.xml"/>'
      '</Relationships>';

  static String _workbook(List<XlsxSheet> sheets) => '$_xmlHead'
      '<workbook xmlns="$_ns" xmlns:r="$_rel"><sheets>'
      '${[for (var i = 0; i < sheets.length; i++) '<sheet name="${_esc(_sheetName(sheets[i].name))}" sheetId="${i + 1}" r:id="rId${i + 1}"/>'].join()}'
      '</sheets></workbook>';

  static String _workbookRels(int n) => '$_xmlHead'
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
      '${[for (var i = 1; i <= n; i++) '<Relationship Id="rId$i" Type="$_rel/worksheet" Target="worksheets/sheet$i.xml"/>'].join()}'
      '<Relationship Id="rId${n + 1}" Type="$_rel/styles" Target="styles.xml"/>'
      '</Relationships>';

  // Style: 0 = mặc định, 1 = in đậm, 2 = số #,##0
  static const _styles = '$_xmlHead'
      '<styleSheet xmlns="$_ns">'
      '<fonts count="2"><font><sz val="11"/><name val="Arial"/></font><font><b/><sz val="11"/><name val="Arial"/></font></fonts>'
      '<fills count="2"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill></fills>'
      '<borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>'
      '<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>'
      '<cellXfs count="3">'
      '<xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>'
      '<xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0" applyFont="1"/>'
      '<xf numFmtId="3" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/>'
      '</cellXfs>'
      '<cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>'
      '</styleSheet>';

  static String _sheetXml(XlsxSheet sh) {
    final b = StringBuffer('$_xmlHead<worksheet xmlns="$_ns">');
    if (sh.widths.isNotEmpty) {
      b.write('<cols>');
      for (var i = 0; i < sh.widths.length; i++) {
        b.write('<col min="${i + 1}" max="${i + 1}" width="${sh.widths[i]}" customWidth="1"/>');
      }
      b.write('</cols>');
    }
    b.write('<sheetData>');
    for (var r = 0; r < sh.rows.length; r++) {
      final row = sh.rows[r];
      if (row.isEmpty) continue;
      final bold = sh.boldRows.contains(r);
      b.write('<row r="${r + 1}">');
      for (var c = 0; c < row.length; c++) {
        final v = row[c];
        if (v == null) continue;
        final ref = '${_col(c)}${r + 1}';
        if (v is num) {
          b.write('<c r="$ref" s="${bold ? 1 : 2}"><v>$v</v></c>');
        } else {
          final style = bold ? ' s="1"' : '';
          b.write('<c r="$ref" t="inlineStr"$style><is><t xml:space="preserve">${_esc('$v')}</t></is></c>');
        }
      }
      b.write('</row>');
    }
    b.write('</sheetData></worksheet>');
    return b.toString();
  }

  // ───────────── ZIP (stored) ─────────────

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

  static Uint8List _zip(Map<String, String> files) {
    final out = BytesBuilder();
    final central = BytesBuilder();
    var count = 0;
    const dosDate = 0x21; // 01/01/1980
    files.forEach((name, content) {
      final nameBytes = utf8.encode(name);
      final data = utf8.encode(content);
      final crc = _crc32(data);
      final offset = out.length;
      // Local file header
      out
        ..add(_u32(0x04034b50))
        ..add(_u16(20)) // version needed
        ..add(_u16(0x0800)) // flags: tên file UTF-8
        ..add(_u16(0)) // method: stored
        ..add(_u16(0)) // mod time
        ..add(_u16(dosDate))
        ..add(_u32(crc))
        ..add(_u32(data.length))
        ..add(_u32(data.length))
        ..add(_u16(nameBytes.length))
        ..add(_u16(0)) // extra length
        ..add(nameBytes)
        ..add(data);
      // Central directory header
      central
        ..add(_u32(0x02014b50))
        ..add(_u16(20)) // version made by
        ..add(_u16(20)) // version needed
        ..add(_u16(0x0800))
        ..add(_u16(0))
        ..add(_u16(0))
        ..add(_u16(dosDate))
        ..add(_u32(crc))
        ..add(_u32(data.length))
        ..add(_u32(data.length))
        ..add(_u16(nameBytes.length))
        ..add(_u16(0)) // extra
        ..add(_u16(0)) // comment
        ..add(_u16(0)) // disk start
        ..add(_u16(0)) // internal attrs
        ..add(_u32(0)) // external attrs
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

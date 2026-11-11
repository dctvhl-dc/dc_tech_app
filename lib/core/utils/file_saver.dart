import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

/// Lưu file qua hộp thoại "Lưu thành..." (Web + Android + Windows).
class FileSaver {
  /// Trả về đường dẫn đã lưu, hoặc null nếu người dùng hủy.
  static Future<String?> save({
    required String fileName,
    required Uint8List bytes,
    required List<String> extensions, // vd ['pdf']
  }) async {
    if (kIsWeb || Platform.isAndroid || Platform.isIOS) {
      return FilePicker.platform.saveFile(dialogTitle: 'Lưu file', fileName: fileName, bytes: bytes);
    }
    // Desktop: chỉ trả về đường dẫn, ta tự ghi file
    var path = await FilePicker.platform.saveFile(
      dialogTitle: 'Lưu file',
      fileName: fileName,
      type: FileType.custom,
      allowedExtensions: extensions,
    );
    if (path == null) return null;
    final ext = '.${extensions.first}';
    if (!path.toLowerCase().endsWith(ext)) path = '$path$ext';
    await File(path).writeAsBytes(bytes);
    return path;
  }
}

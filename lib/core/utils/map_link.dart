import 'dart:io';

import 'package:url_launcher/url_launcher.dart';

class LatLng {
  final double lat;
  final double lng;
  const LatLng(this.lat, this.lng);
  String get text => '${lat.toStringAsFixed(6)},${lng.toStringAsFixed(6)}';
}

/// Xử lý link Google Maps khách gửi: tách toạ độ, mở bản đồ, gọi điện.
class MapLink {
  /// Khách hay dán kèm chữ ("Địa chỉ nhà em: https://maps.app.goo.gl/xxx") -> lấy riêng URL.
  static String? extractUrl(String text) =>
      RegExp(r'https?://[^\s]+').firstMatch(text)?.group(0);

  static bool _validLatLng(double lat, double lng) => lat >= -90 && lat <= 90 && lng >= -180 && lng <= 180;

  /// Tách toạ độ trực tiếp từ chuỗi (link đầy đủ hoặc "lat,lng"). Không cần mạng.
  static LatLng? parseCoords(String input) {
    String s;
    try {
      s = Uri.decodeFull(input);
    } catch (_) {
      s = input;
    }
    const n = r'(-?\d{1,3}(?:\.\d+)?)';
    final patterns = [
      RegExp('!3d$n!4d$n'), // vị trí ghim chính xác (ưu tiên số 1)
      RegExp('@$n,$n'), // tâm khung nhìn: .../@21.0285,105.8542,17z
      RegExp('[?&](?:q|ll|query|destination|daddr)=$n\\s*,\\s*$n'),
      RegExp('^\\s*$n\\s*[,; ]\\s*$n\\s*\$'), // dán thẳng "21.0285,105.8542"
    ];
    for (final re in patterns) {
      final m = re.firstMatch(s);
      if (m == null) continue;
      final lat = double.tryParse(m.group(1)!);
      final lng = double.tryParse(m.group(2)!);
      if (lat != null && lng != null && _validLatLng(lat, lng)) return LatLng(lat, lng);
    }
    return null;
  }

  /// Link rút gọn (maps.app.goo.gl/...) không chứa toạ độ -> theo dõi chuyển hướng
  /// (tối đa 6 lần) để lấy link đầy đủ. Cần có mạng.
  static Future<String> resolve(String url) async {
    var current = url;
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 8)
      ..userAgent = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
          '(KHTML, like Gecko) Chrome/124.0 Safari/537.36';
    try {
      for (var i = 0; i < 6; i++) {
        final req = await client.getUrl(Uri.parse(current));
        req.followRedirects = false;
        final res = await req.close().timeout(const Duration(seconds: 10));
        await res.drain<void>();
        final loc = res.headers.value(HttpHeaders.locationHeader);
        if (res.statusCode >= 300 && res.statusCode < 400 && loc != null) {
          current = Uri.parse(current).resolve(loc).toString();
          if (parseCoords(current) != null) break;
        } else {
          break;
        }
      }
    } finally {
      client.close();
    }
    return current;
  }

  /// Dán link (hoặc chữ chứa link) -> toạ độ khách. null nếu không đọc được.
  static Future<LatLng?> toCoords(String raw) async {
    final text = extractUrl(raw) ?? raw.trim();
    final direct = parseCoords(text);
    if (direct != null) return direct;
    if (!text.startsWith('http')) return null;
    return parseCoords(await resolve(text));
  }

  /// Mở Google Maps: ưu tiên link khách gửi, không có thì dùng toạ độ.
  static Future<bool> open({String link = '', String gps = ''}) async {
    String? url;
    final l = extractUrl(link) ?? link.trim();
    if (l.startsWith('http')) {
      url = l;
    } else {
      final c = parseCoords(gps);
      if (c != null) url = 'https://www.google.com/maps/search/?api=1&query=${c.text}';
    }
    if (url == null) return false;
    return launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  static Future<bool> call(String phone) =>
      launchUrl(Uri(scheme: 'tel', path: phone.replaceAll(RegExp(r'[^0-9+]'), '')));
}

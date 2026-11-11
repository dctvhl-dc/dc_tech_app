import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../../data/models/booking_model.dart';
import 'formatters.dart';
import 'pdf_writer.dart';
import 'vn_number.dart';

enum SlipKind {
  confirmation('Phiếu xác nhận đặt trước', 'XacNhanDat'),
  delivery('Phiếu giao loa', 'PhieuGiao'),
  receipt('Biên nhận thuê loa', 'BienNhan');

  final String label;
  final String filePrefix;
  const SlipKind(this.label, this.filePrefix);
}

class SlipResult {
  final Uint8List png;
  final Uint8List pdf;
  const SlipResult(this.png, this.pdf);
}

/// Vẽ phiếu giao / biên nhận khổ A4 bằng canvas của Flutter, xuất ra PNG và PDF.
class SlipRenderer {
  static const double _w = 595; // A4: 595 x 842 pt
  static const double _minH = 842;
  static const double _scale = 2; // 2 px / pt (~144 dpi)
  static const double _m = 36; // lề
  static const _ink = Color(0xFF111111);
  static const _muted = Color(0xFF555555);
  static const _line = Color(0xFFBBBBBB);

  static Future<SlipResult> render({
    required Booking booking,
    required SlipKind kind,
    required String staffName,
    Map<String, String> company = const {},
  }) async {
    final data = await rootBundle.load('assets/images/logo.png');
    final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
    final logo = (await codec.getNextFrame()).image;

    // Lượt 1: chỉ đo chiều cao nội dung; lượt 2: vẽ thật
    final measured = _draw(null, booking, kind, staffName, company, logo);
    final h = math.max(_minH, measured);

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.scale(_scale);
    canvas.drawRect(Rect.fromLTWH(0, 0, _w, h), Paint()..color = Colors.white);
    _draw(canvas, booking, kind, staffName, company, logo);
    final picture = recorder.endRecording();
    final image = await picture.toImage((_w * _scale).round(), (h * _scale).round());

    final png = (await image.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
    final raw = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    final rgb = _rgbaToRgb(raw);
    final pdf = PdfWriter.fromRgb(
      rgb: rgb,
      width: image.width,
      height: image.height,
      pageWidth: _w,
      pageHeight: h,
    );
    image.dispose();
    picture.dispose();
    logo.dispose();
    return SlipResult(png, pdf);
  }

  static Uint8List _rgbaToRgb(ByteData raw) {
    final src = raw.buffer.asUint8List(raw.offsetInBytes, raw.lengthInBytes);
    final out = Uint8List(src.length ~/ 4 * 3);
    var j = 0;
    for (var i = 0; i < src.length; i += 4) {
      out[j++] = src[i];
      out[j++] = src[i + 1];
      out[j++] = src[i + 2];
    }
    return out;
  }

  /// Vẽ (hoặc chỉ đo nếu [c] == null) và trả về chiều cao cần thiết.
  static double _draw(
    Canvas? c,
    Booking b,
    SlipKind kind,
    String staff,
    Map<String, String> co,
    ui.Image logo,
  ) {
    final contentW = _w - 2 * _m;
    var y = _m;
    final isReceipt = kind != SlipKind.delivery;
    final isConfirm = kind == SlipKind.confirmation;

    double text(String s, double x, double top,
        {double size = 12, bool bold = false, Color color = _ink, double? width, TextAlign align = TextAlign.left}) {
      final tp = TextPainter(
        text: TextSpan(
          text: s,
          style: TextStyle(
            fontSize: size,
            fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
            color: color,
            height: 1.3,
          ),
        ),
        textDirection: TextDirection.ltr,
        textAlign: align,
      );
      tp.layout(minWidth: align == TextAlign.left ? 0 : (width ?? 0), maxWidth: width ?? (_w - x - _m));
      if (c != null) tp.paint(c, Offset(x, top));
      return tp.height;
    }

    void hline(double yy, {Color color = _line, double w = 1}) {
      c?.drawLine(Offset(_m, yy), Offset(_w - _m, yy), Paint()..color = color..strokeWidth = w);
    }

    void info(String label, String value, {bool bold = false}) {
      final h1 = text(label, _m, y, size: 12, color: _muted, width: 110);
      final h2 = text(value, _m + 115, y, size: 12, bold: bold, width: contentW - 115);
      y += math.max(h1, h2) + 4;
    }

    // ── Đầu phiếu: logo + cửa hàng (tên công ty = tên cửa hàng) ──
    const logoH = 54.0;
    final logoW = logoH * logo.width / logo.height;
    c?.drawImageRect(
      logo,
      Rect.fromLTWH(0, 0, logo.width.toDouble(), logo.height.toDouble()),
      Rect.fromLTWH(_m, y, logoW, logoH),
      Paint()..filterQuality = FilterQuality.high,
    );
    final tx = _m + logoW + 12;
    var ty = y;
    final storeName = co['company_name'] ?? 'DC TECH - Cửa hàng chính';
    final storeAddr = co['company_address'] ?? 'Phường Bãi Cháy, Thành phố Hạ Long, Quảng Ninh';
    
    ty += text(storeName, tx, ty, size: 13, bold: true, width: 290);
    ty += text('Địa chỉ: $storeAddr', tx, ty, size: 11, color: _muted, width: 290);
    if ((co['company_phone'] ?? '').isNotEmpty) {
      ty += text('Hotline: ${co['company_phone']}', tx, ty, size: 11, color: _muted, width: 290, bold: true);
    }

    text('Mã đơn: #${b.id}', _w - _m - 170, y, size: 12, bold: true, width: 170, align: TextAlign.right);
    text('Ngày lập: ${Fmt.dateTime(DateTime.now())}', _w - _m - 170, y + 18,
        size: 10, color: _muted, width: 170, align: TextAlign.right);
    y += math.max(logoH, ty - y) + 12;
    hline(y, color: _ink, w: 1.5);
    y += 14;

    y += text(kind.label.toUpperCase(), _m, y, size: 22, bold: true, width: contentW, align: TextAlign.center) + 12;

    // ── Thông tin khách / thời gian ──
    info('Khách hàng:', '${b.customerName} - ${b.customerPhone}', bold: true);

    if (b.locationText.isNotEmpty) info('Địa chỉ:', b.locationText);
    if (isConfirm && b.serviceTime != null) info('Thời gian sử dụng:', Fmt.dateTime(b.serviceTime));
    info('Thời gian thuê:', 'Giao: ${b.installTime == null ? '—' : Fmt.dateTime(b.installTime)} | Thu: ${b.collectTime == null ? '—' : Fmt.dateTime(b.collectTime)}');
    y += 8;

    // ── Bảng thiết bị / dịch vụ ──
    const wStt = 30.0, wQty = 40.0;
    final wPrice = isReceipt ? 90.0 : 0.0;
    final wTotal = isReceipt ? 100.0 : 0.0;
    final wNote = isReceipt ? 0.0 : 170.0;
    final wName = contentW - wStt - wQty - wPrice - wTotal - wNote;
    final xName = _m + wStt;
    final xQty = xName + wName;
    final xA = xQty + wQty;
    final xB = xA + (isReceipt ? wPrice : wNote);

    c?.drawRect(Rect.fromLTWH(_m, y, contentW, 22), Paint()..color = const Color(0xFFEFEFEF));
    text('STT', _m, y + 4, size: 11, bold: true, width: wStt, align: TextAlign.center);
    text('Thiết bị / dịch vụ', xName + 4, y + 4, size: 11, bold: true, width: wName - 8);
    text('SL', xQty, y + 4, size: 11, bold: true, width: wQty, align: TextAlign.center);
    if (isReceipt) {
      text('Đơn giá', xA, y + 4, size: 11, bold: true, width: wPrice - 6, align: TextAlign.right);
      text('Thành tiền', xB, y + 4, size: 11, bold: true, width: wTotal - 4, align: TextAlign.right);
    } else {
      text('Tình trạng khi giao', xA + 4, y + 4, size: 11, bold: true, width: wNote - 8);
    }
    y += 22;
    hline(y);

    for (var i = 0; i < b.services.length; i++) {
      final s = b.services[i];
      final hName = text(s.name, xName + 4, y + 5, size: 12, width: wName - 8);
      text('${i + 1}', _m, y + 5, size: 12, width: wStt, align: TextAlign.center);
      text('${s.qty}', xQty, y + 5, size: 12, width: wQty, align: TextAlign.center);
      if (isReceipt) {
        text(Fmt.thousands(s.price), xA, y + 5, size: 12, width: wPrice - 6, align: TextAlign.right);
        text(Fmt.thousands(s.lineTotal), xB, y + 5, size: 12, width: wTotal - 4, align: TextAlign.right);
      }
      y += math.max(hName, 16) + 10;
      hline(y);
    }
    y += 10;

    if (isReceipt) {
      // ── Tổng tiền ──
      final debt = b.totalCost - b.paidAmount;
      void total(String label, int value, {bool bold = false}) {
        text(label, _w - _m - 300, y, size: 12, bold: bold, width: 170);
        y += text(Fmt.money(value), _w - _m - 130, y, size: 12, bold: bold, width: 130, align: TextAlign.right) + 4;
      }

      total('Tổng cộng:', b.totalCost, bold: true);
      total(isConfirm ? 'Đã thanh toán trước:' : 'Đã thanh toán:', b.paidAmount);
      total(isConfirm ? 'Còn lại phải thanh toán:' : 'Còn lại:', debt < 0 ? 0 : debt, bold: true);
      y += 4;
      y += text('Bằng chữ: ${VnNumber.money(b.totalCost)}', _m, y, size: 12, width: contentW, bold: true, align: TextAlign.center) + 6;
      if (b.note.trim().isNotEmpty) {
        y += text('Ghi chú: ${b.note.trim()}', _m, y, size: 11, width: contentW) + 6;
      }
      if (b.requireInvoice) {
        y += text('Khách yêu cầu xuất hoá đơn: ${b.invoiceInfo}', _m, y, size: 11, color: _muted, width: contentW) + 6;
      }
    } else {
      // ── Ghi chú tình trạng (viết tay) ──
      y += text('Ghi chú khi giao:', _m, y, size: 12, bold: true, width: contentW) + 6;
      for (var i = 0; i < 2; i++) {
        y += 18;
        hline(y, color: _line);
      }
      y += 10;
      if (b.note.trim().isNotEmpty) {
        y += text('Ghi chú đơn hàng: ${b.note.trim()}', _m, y, size: 11, width: contentW) + 6;
      }
    }

    final note = isConfirm
        ? 'Phiếu xác nhận thông tin đặt trước dịch vụ. Quý khách vui lòng liên hệ hotline nếu cần thay đổi thời gian hoặc nội dung dịch vụ.'
        : 'Quý khách vui lòng kiểm tra thiết bị khi nhận và hoàn trả đúng thời gian đã thỏa thuận.';
    y += text(note,
            _m, y, size: 11, color: _muted, width: contentW) +
        18;

    // ── Chữ ký & Thông tin nhân viên / cửa hàng ──
    final half = contentW / 2;
    text(isConfirm ? 'Đại diện cho thuê' : 'Người giao hàng', _m, y, size: 12, bold: true, width: half, align: TextAlign.center);
    final hSig = text(isConfirm ? 'Khách hàng xác nhận' : 'Khách hàng', _m + half, y, size: 12, bold: true, width: half, align: TextAlign.center);
    y += hSig;
    text('(Ký, ghi rõ họ tên)', _m, y, size: 10, color: _muted, width: half, align: TextAlign.center);
    y += text('(Ký, ghi rõ họ tên)', _m + half, y, size: 10, color: _muted, width: half, align: TextAlign.center);
    y += 56;

    final staffStore = co['staff_store'] ?? storeName;
    final staffLabel = '$staff\n($staffStore)';
    y += text(staffLabel, _m, y, size: 11, bold: true, width: half, align: TextAlign.center);
    y += 18;

    hline(y);
    y += 8;
    final phone = co['company_phone'] ?? '';
    final thanks = isConfirm
        ? 'Cảm ơn quý khách đã đặt dịch vụ!${phone.isEmpty ? '' : ' Hotline: $phone'}'
        : 'Cảm ơn quý khách đã sử dụng dịch vụ!';
    y += text(thanks, _m, y, size: 11, color: _muted, width: contentW, align: TextAlign.center);
    return y + _m;
  }
}

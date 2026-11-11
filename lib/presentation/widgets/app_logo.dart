import 'package:flutter/material.dart';

/// Logo DC TECH. Logo có nền trắng và chữ D xanh đậm nên đặt trong "thẻ" trắng
/// bo góc để luôn rõ nét trên nền xanh navy của app.
class AppLogo extends StatelessWidget {
  final double height;
  final bool badge; // false = chỉ ảnh, không có thẻ trắng
  const AppLogo({super.key, this.height = 48, this.badge = true});

  @override
  Widget build(BuildContext context) {
    final img = Image.asset('assets/images/logo.png', height: height, fit: BoxFit.contain);
    if (!badge) return img;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: height * 0.14, vertical: height * 0.08),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(height * 0.25)),
      child: img,
    );
  }
}

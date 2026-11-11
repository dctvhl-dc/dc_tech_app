import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../../data/models/booking_model.dart';
import '../utils/local_config_storage.dart';

/// Một lời nhắc hiển thị trong app (dùng cho Windows, nơi chưa có thông báo hệ thống).
class UpcomingReminder {
  final String key; // duy nhất cho mỗi sự kiện -> mỗi lời nhắc chỉ hiện 1 lần
  final String title;
  final String body;
  const UpcomingReminder(this.key, this.title, this.body);
}

/// Nhắc lịch giao / thu hồi loa.
///  - Android: LÊN LỊCH thông báo hệ thống bằng Báo thức báo thức (AlarmClock) để hiện
///    chính xác kể cả khi điện thoại tắt màn hình, vào Doze mode hay ở chế độ tiết kiệm pin.
///  - Windows: app tự nhắc bằng thông báo trong app khi đang mở (xem MainShell).
class ReminderService {
  ReminderService._();
  static final ReminderService instance = ReminderService._();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;
  bool enabled = true;
  int leadMinutes = 60; // nhắc trước bao nhiêu phút

  static bool get supportsSystemNotifications => Platform.isAndroid || Platform.isIOS;

  Future<void> init() async {
    try {
      final cfg = await LocalConfigStorage.loadReminder();
      enabled = cfg.enabled;
      leadMinutes = cfg.leadMinutes;

      // Khởi tạo cơ sở dữ liệu timezone
      try {
        tz_data.initializeTimeZones();
        tz.setLocalLocation(tz.getLocation('Asia/Ho_Chi_Minh'));
      } catch (_) {}

      if (!supportsSystemNotifications) return;

      await _plugin.initialize(
        const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          iOS: DarwinInitializationSettings(
            requestAlertPermission: true,
            requestBadgePermission: true,
            requestSoundPermission: true,
          ),
        ),
      );

      // Android: hỏi quyền & tạo Kênh thông báo độ ưu tiên cao nhất
      if (Platform.isAndroid) {
        final androidImpl = _plugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
        if (androidImpl != null) {
          try {
            await androidImpl.requestNotificationsPermission();
          } catch (_) {}
          try {
            await androidImpl.requestExactAlarmsPermission();
          } catch (_) {}
          try {
            await androidImpl.createNotificationChannel(
              const AndroidNotificationChannel(
                'dctech_reminders',
                'Nhắc lịch giao / thu loa',
                description: 'Nhắc trước giờ giao hoặc thu hồi loa',
                importance: Importance.max,
                playSound: true,
                enableVibration: true,
              ),
            );
          } catch (_) {}
        }
      }
      _ready = true;
    } catch (_) {
      // Đảm bảo không làm hỏng luồng khởi động ứng dụng
    }
  }

  /// Yêu cầu cấp quyền Báo thức chính xác trên Android (an toàn, không bắn ngoại lệ).
  Future<bool?> requestExactAlarmsPermission() async {
    if (!Platform.isAndroid) return true;
    try {
      final androidImpl = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      return await androidImpl?.requestExactAlarmsPermission();
    } catch (_) {
      return false;
    }
  }

  /// Gửi thông báo thử nghiệm ngay lập tức để kiểm tra hệ thống thông báo.
  Future<void> showTestNotification() async {
    if (!_ready || !supportsSystemNotifications) return;
    try {
      await _plugin.show(
        999999,
        'DC TECH · Bật thông báo thành công',
        'Hệ thống thông báo nhắc lịch giao / thu loa đã sẵn sàng hoạt động trên thiết bị.',
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'dctech_reminders',
            'Nhắc lịch giao / thu loa',
            channelDescription: 'Nhắc trước giờ giao hoặc thu hồi loa',
            importance: Importance.max,
            priority: Priority.high,
            icon: '@mipmap/ic_launcher',
            visibility: NotificationVisibility.public,
            category: AndroidNotificationCategory.alarm,
          ),
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentSound: true,
            presentBadge: true,
          ),
        ),
      );
    } catch (_) {}
  }

  Future<void> configure({bool? enabled, int? leadMinutes, List<Booking>? bookings}) async {
    if (enabled != null) this.enabled = enabled;
    if (leadMinutes != null) this.leadMinutes = leadMinutes;
    await LocalConfigStorage.saveReminder(enabled: this.enabled, leadMinutes: this.leadMinutes);
    if (bookings != null) await sync(bookings);
  }

  static String _hm(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  static String _body(Booking b) {
    final s = b.services.map((x) => x.qty > 1 ? '${x.name} ×${x.qty}' : x.name).join(', ');
    return '${b.customerName} · ${b.customerPhone}\n$s';
  }

  /// Các sự kiện cần nhắc của đơn hàng:
  /// - Giao loa: nếu đơn chưa giao (pending) và có giờ giao.
  /// - Thu hồi loa: nếu đơn chưa hoàn tất trả (chưa returned) và có giờ thu hồi.
  static List<(bool, DateTime)> _events(Booking b) => [
        if (b.status == BookingStatus.pending && b.installTime != null) (true, b.installTime!),
        if (b.status != BookingStatus.returned && b.collectTime != null) (false, b.collectTime!),
      ];

  static int _id(String bookingId, bool delivery, bool isExact) =>
      ((bookingId.hashCode & 0x1fffffff) * 4) + (delivery ? 0 : 1) + (isExact ? 2 : 0);

  /// Đặt lại toàn bộ lịch nhắc theo danh sách đơn hiện tại.
  Future<void> sync(List<Booking> bookings) async {
    if (!_ready) return;
    try {
      try {
        await _plugin.cancelAll();
      } catch (_) {}
      if (!enabled) return;

      final now = DateTime.now();
      final horizon = now.add(const Duration(days: 14));
      var count = 0;

      for (final b in bookings) {
        for (final (isDelivery, time) in _events(b)) {
          if (!time.isAfter(now) || time.isAfter(horizon) || count >= 60) continue;

          // 1. Nhắc trước (Lead time)
          final leadTime = time.subtract(Duration(minutes: leadMinutes));
          final targetLeadTime = leadTime.isAfter(now) ? leadTime : now.add(const Duration(seconds: 10));

          await _scheduleSingle(
            id: _id(b.id, isDelivery, false),
            title: isDelivery ? 'Sắp tới giờ GIAO loa · ${_hm(time)}' : 'Sắp tới giờ THU HỒI loa · ${_hm(time)}',
            body: _body(b),
            scheduledDate: targetLeadTime,
          );

          // 2. Nhắc ĐÚNG GIỜ giao / thu hồi
          await _scheduleSingle(
            id: _id(b.id, isDelivery, true),
            title: isDelivery ? 'ĐÃ TỚI GIỜ GIAO LOA · ${_hm(time)}' : 'ĐÃ TỚI GIỜ THU HỒI LOA · ${_hm(time)}',
            body: _body(b),
            scheduledDate: time,
          );

          count++;
        }
      }
    } catch (_) {
      // Đảm bảo không để bất kỳ lỗi nào làm gián đoạn app
    }
  }

  Future<void> _scheduleSingle({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledDate,
  }) async {
    final now = DateTime.now();
    // Bắt buộc thời gian đặt lịch phải ở tương lai
    if (!scheduledDate.isAfter(now)) return;

    final tzWhen = tz.TZDateTime.from(scheduledDate, tz.local);
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'dctech_reminders',
        'Nhắc lịch giao / thu loa',
        channelDescription: 'Nhắc trước giờ giao hoặc thu hồi loa',
        importance: Importance.max,
        priority: Priority.high,
        icon: '@mipmap/ic_launcher',
        visibility: NotificationVisibility.public,
        category: AndroidNotificationCategory.alarm,
      ),
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentSound: true,
        presentBadge: true,
      ),
    );

    // Dùng chế độ AlarmClock trước (chế độ báo thức chuẩn Android - vượt Doze/Tiết kiệm pin)
    try {
      await _plugin.zonedSchedule(
        id,
        title,
        body,
        tzWhen,
        details,
        androidScheduleMode: AndroidScheduleMode.alarmClock,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
    } catch (_) {
      try {
        await _plugin.zonedSchedule(
          id,
          title,
          body,
          tzWhen,
          details,
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
        );
      } catch (_) {
        try {
          await _plugin.zonedSchedule(
            id,
            title,
            body,
            tzWhen,
            details,
            androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
            uiLocalNotificationDateInterpretation:
                UILocalNotificationDateInterpretation.absoluteTime,
          );
        } catch (_) {}
      }
    }
  }

  /// Các việc sắp tới giờ trong [leadMinutes] phút tới (hoặc vừa quá giờ dưới 30 phút).
  List<UpcomingReminder> upcoming(List<Booking> bookings, DateTime now) {
    if (!enabled) return const [];
    final out = <UpcomingReminder>[];
    for (final b in bookings) {
      for (final (isDelivery, time) in _events(b)) {
        final mins = time.difference(now).inMinutes;
        if (mins <= leadMinutes && mins >= -30) {
          out.add(UpcomingReminder(
            '${b.id}:${isDelivery ? 'giao' : 'thu'}:${time.millisecondsSinceEpoch}',
            isDelivery ? 'Sắp tới giờ GIAO loa · ${_hm(time)}' : 'Sắp tới giờ THU HỒI loa · ${_hm(time)}',
            _body(b).replaceAll('\n', ' · '),
          ));
        }
      }
    }
    return out;
  }
}

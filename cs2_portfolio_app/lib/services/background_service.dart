import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class BackgroundService {
  static Future<void> initializeService() async {
    final service = FlutterBackgroundService();

    // Notification Channel
    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      'cs2_portfolio_service', // id
      'CS2 Portfolio Service', // title
      description: 'This channel is used for important notifications.', // description
      importance: Importance.low, // Low importance to avoid sound/vibration
    );

    final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
        FlutterLocalNotificationsPlugin();

    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    await service.configure(
      androidConfiguration: AndroidConfiguration(
        // This will be executed when app is in foreground or background in separated isolate
        onStart: onStart,

        // auto start service
        autoStart: false,
        isForegroundMode: true,

        notificationChannelId: 'cs2_portfolio_service',
        initialNotificationTitle: 'CS2 Portfolio',
        initialNotificationContent: 'Ready to update prices',
        foregroundServiceNotificationId: 888,
      ),
      iosConfiguration: IosConfiguration(
        autoStart: false,
        onForeground: onStart,
        onBackground: onIosBackground,
      ),
    );
  }

  @pragma('vm:entry-point')
  static Future<bool> onIosBackground(ServiceInstance service) async {
    return true;
  }

  @pragma('vm:entry-point')
  static void onStart(ServiceInstance service) async {
    // Only available for flutter 3.0.0 and later
    DartPluginRegistrant.ensureInitialized();

    // Listen for events from the UI
    service.on('stopService').listen((event) {
      service.stopSelf();
    });

    service.on('updateNotification').listen((event) {
      if (event != null) {
        String content = event['content'] ?? 'Updating...';
        
        // Update the notification
        FlutterLocalNotificationsPlugin().show(
          888,
          'CS2 Portfolio',
          content,
          const NotificationDetails(
            android: AndroidNotificationDetails(
              'cs2_portfolio_service',
              'CS2 Portfolio Service',
              icon: 'ic_bg_service_small',
              ongoing: true,
            ),
          ),
        );
      }
    });
  }
}

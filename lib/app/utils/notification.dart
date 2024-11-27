import 'package:todark/main.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:cloud_firestore/cloud_firestore.dart';

class NotificationShow {
  final FirebaseFirestore firestore = FirebaseFirestore.instance;

  Future<void> showNotification(
    int id,
    String title,
    String body,
    DateTime? date,
  ) async {
    await requestNotificationPermission();
    AndroidNotificationDetails androidNotificationDetails =
        const AndroidNotificationDetails(
      'ToDark',
      'DARK NIGHT',
      priority: Priority.high,
      importance: Importance.max,
    );
    NotificationDetails notificationDetails =
        NotificationDetails(android: androidNotificationDetails);

    var scheduledTime = tz.TZDateTime.from(date!, tz.local);
    await flutterLocalNotificationsPlugin.zonedSchedule(
      id,
      title,
      body,
      scheduledTime,
      notificationDetails,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      payload: 'notification-payload',
    );

    // Sync to Firestore
    await firestore.collection('notifications').doc(id.toString()).set({
      'title': title,
      'body': body,
      'scheduledTime': scheduledTime.toIso8601String(),
      'createdAt': FieldValue.serverTimestamp(),
      'id': id,
    });
  }

  Future<void> requestNotificationPermission() async {
    final platform =
        flutterLocalNotificationsPlugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    if (platform != null) {
      await platform.requestExactAlarmsPermission();
      await platform.requestNotificationsPermission();
    }
  }

  // Cancel Notification in both Firestore and locally
  Future<void> cancelNotification(int id) async {
    await flutterLocalNotificationsPlugin.cancel(id);

    // Remove from Firestore as well
    await firestore.collection('notifications').doc(id.toString()).delete();
  }

  // Update Notification with a new date and sync to Firestore
  Future<void> updateNotification(
      int id, String title, String body, DateTime newDate) async {
    await cancelNotification(id);
    await showNotification(id, title, body, newDate);
  }
}

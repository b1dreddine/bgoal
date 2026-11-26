import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'push_links.dart';

enum PushPermission { notDetermined, granted, denied }

class PushMessage {
  const PushMessage({required this.data, this.title, this.body, this.messageId});

  final Map<String, dynamic> data;
  final String? title;
  final String? body;
  final String? messageId;

  int? get matchId => matchIdFromData(data);

  /// Same message delivered twice -> same id -> replaces instead of stacking.
  int get notificationId => (messageId ?? jsonEncode(data)).hashCode & 0x7fffffff;
}

/// Push notifications as the rest of the app sees them. [FirebasePushService] in the
/// app, fakes in tests, and [NoPushService] when Firebase isn't configured.
abstract class PushService {
  /// False when Firebase isn't set up (no google-services files): the app works, minus pushes.
  bool get available;

  Future<void> init();
  Future<PushPermission> permission();
  Future<PushPermission> requestPermission();

  /// FCM token, or null if not available yet (iOS gets it once APNs answers).
  Future<String?> token();
  Stream<String> get onTokenRefresh;

  /// Pushes received while the app is open.
  Stream<PushMessage> get onForegroundMessage;

  /// Taps on a notification while the app is running in the background.
  Stream<PushMessage> get onOpened;

  /// The notification tap that launched the app, if any (returned once).
  Future<PushMessage?> initialMessage();

  /// Shows a push that arrived while the app is open (Android only: iOS shows it itself).
  Future<void> showForeground(PushMessage message);
}

class NoPushService implements PushService {
  @override
  bool get available => false;
  @override
  Future<void> init() async {}
  @override
  Future<PushPermission> permission() async => PushPermission.denied;
  @override
  Future<PushPermission> requestPermission() async => PushPermission.denied;
  @override
  Future<String?> token() async => null;
  @override
  Stream<String> get onTokenRefresh => const Stream.empty();
  @override
  Stream<PushMessage> get onForegroundMessage => const Stream.empty();
  @override
  Stream<PushMessage> get onOpened => const Stream.empty();
  @override
  Future<PushMessage?> initialMessage() async => null;
  @override
  Future<void> showForeground(PushMessage message) async {}
}

class FirebasePushService implements PushService {
  /// Must match the backend's `AndroidNotification(channel_id=...)`.
  static const channel = AndroidNotificationChannel(
    'match_events',
    'Match events',
    description: 'Goals, kick-off, cards and results for the teams you follow',
    importance: Importance.high,
  );

  final _local = FlutterLocalNotificationsPlugin();
  final _openedLocal = StreamController<PushMessage>.broadcast();
  PushMessage? _launchedFromLocal;
  bool _available = false;

  @override
  bool get available => _available;

  FirebaseMessaging get _fcm => FirebaseMessaging.instance;

  @override
  Future<void> init() async {
    try {
      // Reads google-services.json / GoogleService-Info.plist from the native projects.
      await Firebase.initializeApp();
    } catch (e) {
      debugPrint('Push notifications disabled, Firebase is not configured: $e');
      return;
    }
    _available = true;

    // iOS: show pushes as banners even when the app is open (Android uses _local below).
    await _fcm.setForegroundNotificationPresentationOptions(alert: true, badge: true, sound: true);

    await _local.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@drawable/ic_notification'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
      onDidReceiveNotificationResponse: (r) {
        final m = _fromPayload(r.payload);
        if (m != null) _openedLocal.add(m);
      },
    );
    // Created up front so background pushes (shown by the OS) land in it too.
    await _local
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
    final launch = await _local.getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp ?? false) {
      _launchedFromLocal = _fromPayload(launch!.notificationResponse?.payload);
    }
  }

  static PushPermission _map(AuthorizationStatus s) => switch (s) {
        AuthorizationStatus.authorized || AuthorizationStatus.provisional => PushPermission.granted,
        AuthorizationStatus.denied => PushPermission.denied,
        AuthorizationStatus.notDetermined => PushPermission.notDetermined,
      };

  @override
  Future<PushPermission> permission() async =>
      _available ? _map((await _fcm.getNotificationSettings()).authorizationStatus) : PushPermission.denied;

  @override
  Future<PushPermission> requestPermission() async =>
      _available ? _map((await _fcm.requestPermission()).authorizationStatus) : PushPermission.denied;

  @override
  Future<String?> token() async {
    if (!_available) return null;
    try {
      // On iOS the FCM token needs the APNs token first; until then, try again later.
      if (Platform.isIOS && await _fcm.getAPNSToken() == null) return null;
      return await _fcm.getToken();
    } catch (e) {
      debugPrint('FCM token not available yet: $e');
      return null;
    }
  }

  @override
  Stream<String> get onTokenRefresh => _available ? _fcm.onTokenRefresh : const Stream.empty();

  @override
  Stream<PushMessage> get onForegroundMessage =>
      _available ? FirebaseMessaging.onMessage.map(_fromRemote) : const Stream.empty();

  @override
  Stream<PushMessage> get onOpened => _available
      ? _merge([FirebaseMessaging.onMessageOpenedApp.map(_fromRemote), _openedLocal.stream])
      : const Stream.empty();

  @override
  Future<PushMessage?> initialMessage() async {
    if (!_available) return null;
    final remote = await _fcm.getInitialMessage();
    if (remote != null) return _fromRemote(remote);
    final local = _launchedFromLocal;
    _launchedFromLocal = null;
    return local;
  }

  @override
  Future<void> showForeground(PushMessage message) async {
    if (!_available || !Platform.isAndroid) return;
    final matchId = message.matchId;
    await _local.show(
      message.notificationId,
      message.title,
      message.body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          channel.id,
          channel.name,
          channelDescription: channel.description,
          importance: Importance.high,
          priority: Priority.high,
          groupKey: matchId == null ? null : 'match_$matchId',
        ),
      ),
      payload: jsonEncode(message.data),
    );
  }

  static PushMessage _fromRemote(RemoteMessage m) => PushMessage(
        data: Map<String, dynamic>.from(m.data),
        title: m.notification?.title,
        body: m.notification?.body,
        messageId: m.messageId,
      );

  static PushMessage? _fromPayload(String? payload) {
    if (payload == null) return null;
    try {
      return PushMessage(data: jsonDecode(payload) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }
}

/// Merges broadcast streams (avoids depending on package:async for one helper).
Stream<T> _merge<T>(List<Stream<T>> streams) {
  final subs = <StreamSubscription<T>>[];
  late final StreamController<T> controller;
  controller = StreamController<T>.broadcast(
    onListen: () {
      for (final s in streams) {
        subs.add(s.listen(controller.add, onError: controller.addError));
      }
    },
    onCancel: () async {
      for (final s in subs) {
        await s.cancel();
      }
      subs.clear();
    },
  );
  return controller.stream;
}
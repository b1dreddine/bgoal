import 'dart:async';

import 'package:livescores/notifications/push_service.dart';

/// Controllable stand-in for Firebase in tests.
class FakePush implements PushService {
  FakePush({this.status = PushPermission.notDetermined, this.tokenValue = 'token-1'});

  PushPermission status;
  PushPermission answerToRequest = PushPermission.granted;
  String? tokenValue;
  PushMessage? initial;
  int permissionRequests = 0;
  final shown = <PushMessage>[];

  final tokenRefresh = StreamController<String>.broadcast();
  final foreground = StreamController<PushMessage>.broadcast();
  final opened = StreamController<PushMessage>.broadcast();

  @override
  bool get available => true;

  @override
  Future<void> init() async {}

  @override
  Future<PushPermission> permission() async => status;

  @override
  Future<PushPermission> requestPermission() async {
    permissionRequests++;
    return status = answerToRequest;
  }

  @override
  Future<String?> token() async => tokenValue;

  @override
  Stream<String> get onTokenRefresh => tokenRefresh.stream;

  @override
  Stream<PushMessage> get onForegroundMessage => foreground.stream;

  @override
  Stream<PushMessage> get onOpened => opened.stream;

  @override
  Future<PushMessage?> initialMessage() async {
    final m = initial;
    initial = null;
    return m;
  }

  @override
  Future<void> showForeground(PushMessage message) async => shown.add(message);
}

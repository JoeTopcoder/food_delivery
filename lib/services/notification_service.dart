import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/chat_model.dart';
import '../utils/app_logger.dart';

/// Tracks call IDs already shown to prevent duplicate call notifications
final Set<String> _shownCallIds = {};

/// Top-level handler for background FCM messages (must be top-level function)
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();

  final type = message.data['type'];
  if (type == 'incoming_call') {
    final callId = message.data['call_id'] ?? DateTime.now().millisecondsSinceEpoch.toString();
    if (_shownCallIds.contains(callId)) return;
    _shownCallIds.add(callId);
    final callerName = message.data['caller_name'] ?? 'Incoming Call';
    final channelName = message.data['channel_name'] ?? '';

    final params = CallKitParams(
      id: callId,
      nameCaller: callerName,
      appName: 'MealHub',
      type: 0, // 0 = audio call
      duration: 60000,
      textAccept: 'Answer',
      textDecline: 'Decline',
      extra: {
        'call_id': callId,
        'caller_id': message.data['caller_id'] ?? '',
        'caller_name': callerName,
        'order_id': message.data['order_id'] ?? '',
        'channel_name': channelName,
        'user_id': message.data['user_id'] ?? '',
      },
      android: const AndroidParams(
        isCustomNotification: true,
        isShowLogo: false,
        ringtonePath: 'system_ringtone_default',
        backgroundColor: '#1B1B2F',
        actionColor: '#7C3AED',
        incomingCallNotificationChannelName: 'Incoming Calls',
        missedCallNotificationChannelName: 'Missed Calls',
      ),
    );

    await FlutterCallkitIncoming.showCallkitIncoming(params);
  }
}

/// Handles Firebase Cloud Messaging and local notifications
class NotificationService {
  static final NotificationService _instance = NotificationService._internal();

  factory NotificationService() {
    return _instance;
  }

  NotificationService._internal();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  /// Global navigator key — set from main.dart so notifications can navigate
  static GlobalKey<NavigatorState>? navigatorKey;

  /// FCM message that launched the app from terminated state.
  /// Stored during initialize() and processed later once the main navigator is ready.
  static RemoteMessage? _pendingLaunchMessage;

  /// Callback fired when a new_order notification arrives while app is in foreground
  static VoidCallback? onNewOrderReceived;
  static VoidCallback? onNewOrderForRestaurant;
  static VoidCallback? onNewOrderForAdmin;

  /// Callback fired for order lifecycle notifications (order placed, preparing,
  /// rider assigned, delivered, etc.) — used by the notifications screen to
  /// immediately add the notification to the in-memory list while in foreground.
  static void Function(
    String type,
    String title,
    String body,
    Map<String, dynamic> data,
  )?
  onOrderNotificationReceived;

  /// Android notification channel with custom long sound
  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    'food_hub_notifications_v3',
    'FoodHub Order Alerts',
    description: 'Notifications for orders, deliveries, and updates',
    importance: Importance.max,
    playSound: true,
    enableVibration: true,
    sound: RawResourceAndroidNotificationSound('order_alert'),
  );

  /// Dedicated call notification channel with ringtone sound
  static const AndroidNotificationChannel _callChannel =
      AndroidNotificationChannel(
        'food_hub_calls_v3',
        'Incoming Calls',
        description: 'Incoming voice call alerts',
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
        sound: RawResourceAndroidNotificationSound('call_ringtone'),
      );

  /// Initialize notification service
  Future<void> initialize() async {
    if (_initialized) return;
    try {
      // Check existing permission before requesting to avoid re-prompting
      // every time the app opens (once the user has responded, don't ask again)
      final existingSettings = await _messaging.getNotificationSettings();
      final NotificationSettings settings;
      if (existingSettings.authorizationStatus ==
          AuthorizationStatus.notDetermined) {
        settings = await _messaging.requestPermission(
          alert: true,
          badge: true,
          sound: true,
          provisional: false,
        );
      } else {
        settings = existingSettings;
      }
      AppLogger.info(
        'Notification permission: ${settings.authorizationStatus}',
      );

      // Create Android notification channel
      await _localNotifications
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.createNotificationChannel(_channel);

      // Create call notification channel
      await _localNotifications
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.createNotificationChannel(_callChannel);

      // Initialize local notifications
      const androidSettings = AndroidInitializationSettings(
        '@mipmap/ic_launcher',
      );
      const iosSettings = DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      );
      const initSettings = InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      );
      await _localNotifications.initialize(
        settings: initSettings,
        onDidReceiveNotificationResponse: _onNotificationTapped,
      );

      // Set up FCM message handlers
      FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
      FirebaseMessaging.onMessageOpenedApp.listen(_handleMessageOpenedApp);
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

      // Suppress system notification display in foreground — we handle it
      // ourselves so incoming calls get custom Answer/Decline buttons
      await _messaging.setForegroundNotificationPresentationOptions(
        alert: false,
        badge: false,
        sound: false,
      );

      // Handle notification that launched the app from terminated state.
      // Store it and let processPendingLaunchMessage() be called by the
      // splash screen AFTER it has navigated to the main screen.
      final initialMessage = await _messaging.getInitialMessage();
      if (initialMessage != null) {
        _pendingLaunchMessage = initialMessage;
      }

      // Save FCM token to Supabase user profile
      await _saveFCMToken();

      // Listen for token refresh
      _messaging.onTokenRefresh.listen((newToken) {
        _saveTokenToSupabase(newToken);
      });

      // Listen for CallKit answer/decline events
      FlutterCallkitIncoming.onEvent.listen((event) {
        if (event == null) return;
        switch (event.event) {
          case Event.actionCallAccept:
            final extra = event.body['extra'] as Map<dynamic, dynamic>? ?? {};
            final data = extra.map((k, v) => MapEntry(k.toString(), v));
            handleNotificationByType('incoming_call', '', '', data, navigate: true);
            break;
          case Event.actionCallDecline:
          case Event.actionCallEnded:
            FlutterCallkitIncoming.endAllCalls();
            break;
          default:
            break;
        }
      });

      _initialized = true;
      AppLogger.info('Notification service initialized with FCM');
    } catch (e) {
      AppLogger.error('Error initializing notification service: $e');
    }
  }

  /// Call this after the splash screen has navigated to the main screen.
  /// Processes any FCM notification that cold-launched the app so the user
  /// is taken to the correct screen (e.g. /notifications) instead of home.
  void processPendingLaunchMessage() {
    final msg = _pendingLaunchMessage;
    if (msg == null) return;
    _pendingLaunchMessage = null;
    _handleMessageOpenedApp(msg);
  }

  /// Get current FCM token
  Future<String?> getFCMToken() async {
    try {
      return await _messaging.getToken();
    } catch (e) {
      AppLogger.error('Error getting FCM token: $e');
      return null;
    }
  }

  /// Save FCM token to Supabase
  Future<void> _saveFCMToken() async {
    final token = await getFCMToken();
    if (token != null) {
      await _saveTokenToSupabase(token);
    }
  }

  /// Store token in the user's profile row
  Future<void> _saveTokenToSupabase(String token) async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user != null) {
        await Supabase.instance.client
            .from('users')
            .update({'fcm_token': token})
            .eq('id', user.id);
        AppLogger.info('FCM token saved to Supabase');
      }
    } catch (e) {
      AppLogger.error('Error saving FCM token: $e');
    }
  }

  /// Handle foreground messages — show local notification
  void _handleForegroundMessage(RemoteMessage message) {
    final notification = message.notification;
    final type = message.data['type'] as String?;

    // Incoming call — always show our custom call notification with
    // Answer/Decline buttons (whether data-only or notification+data)
    if (type == 'incoming_call') {
      final title =
          message.data['title'] ?? notification?.title ?? 'Incoming Call';
      final body =
          message.data['body'] ??
          notification?.body ??
          'Someone is calling you';
      showCallNotification(title: title, body: body, data: message.data);
      handleNotificationByType(type, title, body, message.data);
      return;
    }

    if (notification != null) {
      showNotification(
        title: notification.title ?? 'Food Driver',
        body: notification.body ?? '',
        data: message.data,
      );
    }
    handleNotificationByType(
      type,
      notification?.title ?? '',
      notification?.body ?? '',
      message.data,
    );
  }

  /// Handle when a notification opens the app
  void _handleMessageOpenedApp(RemoteMessage message) {
    AppLogger.info('Notification opened app: ${message.data}');
    handleNotificationByType(
      message.data['type'],
      message.notification?.title ?? '',
      message.notification?.body ?? '',
      message.data,
      navigate: true,
    );
  }

  /// Handle local notification tap
  void _onNotificationTapped(NotificationResponse response) {
    // Handle Answer/Decline action buttons
    if (response.actionId == 'answer_call') {
      AppLogger.info('Call answered via notification action');
      cancelCallNotification();
      if (response.payload != null) {
        try {
          final data = jsonDecode(response.payload!) as Map<String, dynamic>;
          handleNotificationByType(
            data['type'] as String?,
            '',
            '',
            data,
            navigate: true,
          );
        } catch (e) {
          AppLogger.error('Error parsing answer payload: $e');
        }
      }
      return;
    }
    if (response.actionId == 'decline_call') {
      AppLogger.info('Call declined via notification action');
      cancelCallNotification();
      return;
    }

    if (response.payload != null) {
      try {
        final data = jsonDecode(response.payload!) as Map<String, dynamic>;
        handleNotificationByType(
          data['type'] as String?,
          '',
          '',
          data,
          navigate: true,
        );
      } catch (e) {
        AppLogger.error('Error parsing notification payload: $e');
      }
    }
  }

  /// Show local notification
  Future<void> showNotification({
    required String title,
    required String body,
    Map<String, dynamic>? data,
  }) async {
    try {
      await _localNotifications.show(
        id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        title: title,
        body: body,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            _channel.id,
            _channel.name,
            channelDescription: _channel.description,
            importance: Importance.max,
            priority: Priority.high,
            playSound: true,
            sound: const RawResourceAndroidNotificationSound('order_alert'),
            enableVibration: true,
            icon: '@mipmap/ic_launcher',
          ),
          iOS: const DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
          ),
        ),
        payload: data != null ? jsonEncode(data) : null,
      );
    } catch (e) {
      AppLogger.error('Error showing notification: $e');
    }
  }

  /// Show a high-priority call notification with full-screen intent
  Future<void> showCallNotification({
    required String title,
    required String body,
    Map<String, dynamic>? data,
  }) async {
    try {
      final callId = data?['call_id'] as String? ?? DateTime.now().millisecondsSinceEpoch.toString();
      if (_shownCallIds.contains(callId)) return;
      _shownCallIds.add(callId);
      final callerName = data?['caller_name'] as String? ?? title;

      final params = CallKitParams(
        id: callId,
        nameCaller: callerName,
        appName: 'MealHub',
        type: 0,
        duration: 60000,
        textAccept: 'Answer',
        textDecline: 'Decline',
        extra: data ?? {},
        android: const AndroidParams(
          isCustomNotification: true,
          isShowLogo: false,
          ringtonePath: 'system_ringtone_default',
          backgroundColor: '#1B1B2F',
          actionColor: '#7C3AED',
          incomingCallNotificationChannelName: 'Incoming Calls',
          missedCallNotificationChannelName: 'Missed Calls',
        ),
      );

      await FlutterCallkitIncoming.showCallkitIncoming(params);
    } catch (e) {
      AppLogger.error('Error showing call notification: $e');
    }
  }

  /// Cancel the call notification (when call is answered/declined)
  Future<void> cancelCallNotification() async {
    _shownCallIds.clear();
    await FlutterCallkitIncoming.endAllCalls();
  }

  /// Handle notification by type
  void handleNotificationByType(
    String? type,
    String title,
    String body,
    Map<String, dynamic> data, {
    bool navigate = false,
  }) {
    switch (type) {
      case 'new_order':
        AppLogger.info('New order notification: $title');
        // Trigger in-app refresh callback
        onNewOrderReceived?.call();
        if (navigate) {
          navigatorKey?.currentState?.pushNamed('/available-orders');
        }
        break;
      case 'new_restaurant_order':
        AppLogger.info('New restaurant order notification: $title');
        onNewOrderForRestaurant?.call();
        if (navigate) {
          navigatorKey?.currentState?.pushNamed('/restaurant-orders');
        }
        break;
      case 'new_order_admin':
        AppLogger.info('New order for admin: $title');
        onNewOrderForAdmin?.call();
        break;
      case 'order_placed':
      case 'order_confirmed':
      case 'preparing':
      case 'out_for_delivery':
      case 'delivered':
      case 'order_cancelled':
        AppLogger.info('Order lifecycle notification [$type]: $title');
        onOrderNotificationReceived?.call(type ?? '', title, body, data);
        if (navigate) {
          navigatorKey?.currentState?.pushNamed('/notifications');
        }
        break;
      case 'order_status_update':
        AppLogger.info('Order status update: $body');
        onOrderNotificationReceived?.call(
          type ?? 'order_status_update',
          title,
          body,
          data,
        );
        if (navigate) {
          navigatorKey?.currentState?.pushNamed('/notifications');
        }
        break;
      case 'delivery_update':
        AppLogger.info('Delivery update: $body');
        if (navigate) {
          navigatorKey?.currentState?.pushNamed('/active-deliveries');
        }
        break;
      case 'incoming_call':
        AppLogger.info('Incoming call notification: $title');
        // Navigate to call screen if user taps the notification
        if (navigate) {
          final callId = data['call_id'] as String?;
          final callerId = data['caller_id'] as String?;
          final callerName = data['caller_name'] as String?;
          final orderId = data['order_id'] as String?;
          final channelName = data['channel_name'] as String?;
          final receiverId = data['user_id'] as String?;
          if (callId != null &&
              callerId != null &&
              orderId != null &&
              channelName != null) {
            navigatorKey?.currentState?.pushNamed(
              '/call',
              arguments: {
                'call': CallRecord(
                  id: callId,
                  orderId: orderId,
                  callerId: callerId,
                  receiverId: receiverId ?? '',
                  channelName: channelName,
                  status: CallStatus.ringing,
                  createdAt: DateTime.now(),
                ),
                'isCaller': false,
                'otherPartyName': callerName,
              },
            );
          }
        }
        break;
      case 'promo':
        AppLogger.info('Promo notification: $title');
        break;
      case 'new_message':
        AppLogger.info('New message notification: $title');
        if (navigate) {
          final orderId = data['order_id'] as String?;
          final senderName = data['sender_name'] as String? ?? 'Chat';
          if (orderId != null) {
            navigatorKey?.currentState?.pushNamed(
              '/chat',
              arguments: {'orderId': orderId, 'otherPartyName': senderName},
            );
          }
        }
        break;
      default:
        AppLogger.info('Notification: $title - $body');
    }
  }

  /// Subscribe to notification topic
  Future<void> subscribeToTopic(String topic) async {
    try {
      await _messaging.subscribeToTopic(topic);
      AppLogger.info('Subscribed to topic: $topic');
    } catch (e) {
      AppLogger.error('Error subscribing to topic: $e');
    }
  }

  /// Unsubscribe from notification topic
  Future<void> unsubscribeFromTopic(String topic) async {
    try {
      await _messaging.unsubscribeFromTopic(topic);
      AppLogger.info('Unsubscribed from topic: $topic');
    } catch (e) {
      AppLogger.error('Error unsubscribing from topic: $e');
    }
  }
}

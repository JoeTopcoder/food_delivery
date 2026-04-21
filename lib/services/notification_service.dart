import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/chat_model.dart';
import '../utils/app_logger.dart';

/// Top-level handler for background FCM messages (must be top-level function)
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Firebase must be initialized in the background isolate
  await Firebase.initializeApp();

  AppLogger.info('Background message received: ${message.messageId}');

  // For incoming calls, show a high-priority local notification that rings
  // This fires for both data-only AND notification+data messages when in background
  final type = message.data['type'];
  if (type == 'incoming_call') {
    final plugin = FlutterLocalNotificationsPlugin();

    // Create call channel with ringtone sound
    await plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(
          const AndroidNotificationChannel(
            'food_hub_calls_v3',
            'Incoming Calls',
            description: 'Incoming voice call alerts',
            importance: Importance.max,
            playSound: true,
            enableVibration: true,
            sound: RawResourceAndroidNotificationSound('call_ringtone'),
          ),
        );

    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    const initSettings = InitializationSettings(android: androidSettings);
    await plugin.initialize(settings: initSettings);

    final title =
        message.data['title'] ?? message.notification?.title ?? 'Incoming Call';
    final body =
        message.data['body'] ??
        message.notification?.body ??
        'Someone is calling you';

    await plugin.show(
      id: 9999, // fixed ID so we can cancel it when the call is answered/declined
      title: title,
      body: body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          'food_hub_calls_v3',
          'Incoming Calls',
          channelDescription: 'Incoming voice call alerts',
          importance: Importance.max,
          priority: Priority.high,
          category: AndroidNotificationCategory.call,
          fullScreenIntent: true,
          ongoing: true,
          autoCancel: false,
          playSound: true,
          sound: const RawResourceAndroidNotificationSound('call_ringtone'),
          enableVibration: true,
          icon: '@mipmap/ic_launcher',
          visibility: NotificationVisibility.public,
          timeoutAfter: 60000, // auto-dismiss after 60s
          additionalFlags: Int32List.fromList(<int>[
            4,
          ]), // FLAG_INSISTENT — loops the ringtone
          actions: <AndroidNotificationAction>[
            const AndroidNotificationAction(
              'answer_call',
              'Answer',
              icon: DrawableResourceAndroidBitmap('@mipmap/ic_launcher'),
              showsUserInterface: true,
            ),
            const AndroidNotificationAction(
              'decline_call',
              'Decline',
              icon: DrawableResourceAndroidBitmap('@mipmap/ic_launcher'),
              cancelNotification: true,
            ),
          ],
        ),
      ),
      payload: jsonEncode(message.data),
    );
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

  /// Callback fired when a new_order notification arrives while app is in foreground
  static VoidCallback? onNewOrderReceived;
  static VoidCallback? onNewOrderForRestaurant;
  static VoidCallback? onNewOrderForAdmin;

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

      // Handle notification that launched the app
      final initialMessage = await _messaging.getInitialMessage();
      if (initialMessage != null) {
        _handleMessageOpenedApp(initialMessage);
      }

      // Save FCM token to Supabase user profile
      await _saveFCMToken();

      // Listen for token refresh
      _messaging.onTokenRefresh.listen((newToken) {
        _saveTokenToSupabase(newToken);
      });

      _initialized = true;
      AppLogger.info('Notification service initialized with FCM');
    } catch (e) {
      AppLogger.error('Error initializing notification service: $e');
    }
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
      await _localNotifications.show(
        id: 9999, // fixed ID to cancel when answered
        title: title,
        body: body,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            _callChannel.id,
            _callChannel.name,
            channelDescription: _callChannel.description,
            importance: Importance.max,
            priority: Priority.high,
            category: AndroidNotificationCategory.call,
            fullScreenIntent: true,
            ongoing: true,
            autoCancel: false,
            playSound: true,
            sound: const RawResourceAndroidNotificationSound('call_ringtone'),
            enableVibration: true,
            icon: '@mipmap/ic_launcher',
            visibility: NotificationVisibility.public,
            timeoutAfter: 60000, // auto-dismiss after 60s
            additionalFlags: Int32List.fromList(<int>[
              4,
            ]), // FLAG_INSISTENT — loops the ringtone
            actions: <AndroidNotificationAction>[
              const AndroidNotificationAction(
                'answer_call',
                'Answer',
                icon: DrawableResourceAndroidBitmap('@mipmap/ic_launcher'),
                showsUserInterface: true,
              ),
              const AndroidNotificationAction(
                'decline_call',
                'Decline',
                icon: DrawableResourceAndroidBitmap('@mipmap/ic_launcher'),
                cancelNotification: true,
              ),
            ],
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
      AppLogger.error('Error showing call notification: $e');
    }
  }

  /// Cancel the call notification (when call is answered/declined)
  Future<void> cancelCallNotification() async {
    await _localNotifications.cancel(id: 9999);
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
      case 'order_status_update':
        AppLogger.info('Order status update: $body');
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

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) return web;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      default:
        // iOS/macOS/desktop: firebase reads from GoogleService-Info.plist / google-services.json
        throw UnsupportedError(
          'DefaultFirebaseOptions not configured for $defaultTargetPlatform. '
          'Use Firebase.initializeApp() without options on this platform.',
        );
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyD8svg1_8R2kganNpZXx32wSUBFSkqZudg',
    appId: '1:379314267431:web:6a49aa76f603f8cc3a7502',
    messagingSenderId: '379314267431',
    projectId: 'fooddelivery-bebe2',
    authDomain: 'fooddelivery-bebe2.firebaseapp.com',
    storageBucket: 'fooddelivery-bebe2.firebasestorage.app',
    measurementId: 'G-D9ZR6NY91C',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyA64J8qMpK3s_YPjGP_t1pWfoaPs9To2do',
    appId: '1:379314267431:android:a19ddafcfbe762213a7502',
    messagingSenderId: '379314267431',
    projectId: 'fooddelivery-bebe2',
    storageBucket: 'fooddelivery-bebe2.firebasestorage.app',
  );
}

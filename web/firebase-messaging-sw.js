// Firebase Messaging Service Worker
// Required for background push notifications on web.

importScripts("https://www.gstatic.com/firebasejs/11.0.0/firebase-app-compat.js");
importScripts("https://www.gstatic.com/firebasejs/11.0.0/firebase-messaging-compat.js");

firebase.initializeApp({
  apiKey:            "AIzaSyD8svg1_8R2kganNpZXx32wSUBFSkqZudg",
  authDomain:        "fooddelivery-bebe2.firebaseapp.com",
  projectId:         "fooddelivery-bebe2",
  storageBucket:     "fooddelivery-bebe2.firebasestorage.app",
  messagingSenderId: "379314267431",
  appId:             "1:379314267431:web:6a49aa76f603f8cc3a7502",
  measurementId:     "G-D9ZR6NY91C"
});

const messaging = firebase.messaging();

// Handle background messages
messaging.onBackgroundMessage((payload) => {
  const { title, body } = payload.notification ?? {};
  if (title) {
    self.registration.showNotification(title, {
      body: body ?? "",
      icon: "/icons/Icon-192.png",
    });
  }
});

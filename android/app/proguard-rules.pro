# Flutter / Dart
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Firebase
-keep class com.google.firebase.** { *; }
-dontwarn com.google.firebase.**

# Stripe
-keep class com.stripe.android.** { *; }
-dontwarn com.stripe.android.**

# Agora RTC Engine
-keep class io.agora.** { *; }
-dontwarn io.agora.**

# Gson (used by various plugins)
-keepattributes Signature
-keepattributes *Annotation*
-keep class com.google.gson.** { *; }
-keep class sun.misc.Unsafe { *; }

# Geolocator
-keep class com.baseflow.geolocator.** { *; }

# OkHttp / Retrofit (common transitive dependency)
-dontwarn okhttp3.**
-dontwarn okio.**
-dontwarn javax.annotation.**

# Keep native methods
-keepclasseswithmembernames class * {
    native <methods>;
}

# Google Play Core (required by Flutter deferred components)
-dontwarn com.google.android.play.core.**

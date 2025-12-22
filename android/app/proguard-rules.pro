## Flutter Wrapper & Plugins
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

## Firebase & Google Services (Crucial for your app)
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.firebase.**
-dontwarn com.google.android.gms.**

## Geolocator & Location
-keep class com.baseflow.geolocator.** { *; }
-keep class com.lyokone.location.** { *; }

## Async/Future Handling
-dontwarn java.util.concurrent.**

## Common Networking (OkHttp/Retrofit usually used by plugins)
-dontwarn okhttp3.**
-dontwarn okio.**
-dontwarn javax.annotation.**
-keepattributes Signature
-keepattributes *Annotation*
-keepattributes EnclosingMethod

## Prevent Crashes from "Missing" Classes
# If the build fails saying "can't find referenced class", 
# this tells R8 to ignore the warning and proceed.
-ignorewarnings
# Flutter
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-keep class com.google.android.play.core.** { *; }
# Keep BuildConfig for native API URL
-keep class com.drafting.app.BuildConfig { *; }

# Gson / JSON used in CaptureService
-keepattributes Signature
-keepattributes *Annotation*

-dontwarn com.google.android.play.core.**

# Flutter
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-keep class com.google.android.play.core.** { *; }

# Keep BuildConfig and Application classes
-keep class com.drafting.app.** { *; }

# Gson / JSON & Reflection attributes
-keepattributes Signature
-keepattributes *Annotation*
-keepattributes EnclosingMethod
-keepattributes InnerClasses

# Dart JNI (usado por path_provider_android y google_fonts)
-keep class com.github.dart_lang.jni.** { *; }

# Google Sign-In, Credential Manager & Play Services
-keep class androidx.credentials.** { *; }
-keep class com.google.android.libraries.identity.** { *; }
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.android.gms.**
-dontwarn com.google.android.play.core.**

# Google Play Billing (in_app_purchase)
-keep class com.android.vending.billing.** { *; }
-keep class com.android.billingclient.** { *; }

# Google Mobile Ads (AdMob)
-keep public class com.google.android.gms.ads.** {
   public *;
}
-keep class com.google.ads.** {
   public *;
}
-dontwarn com.google.android.gms.ads.**

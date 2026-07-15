# --- Flutter engine ---
-keep class io.flutter.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.embedding.** { *; }

# --- AppsFlyer ---
-keep class com.appsflyer.** { *; }
-dontwarn com.appsflyer.**

# --- Firebase / GMS ---
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.firebase.**
-dontwarn com.google.android.gms.**

# --- Play services base (webview crash reporter uses reflection) ---
-keep class com.google.android.play.core.** { *; }
-dontwarn com.google.android.play.core.**

# --- Play Install Referrer (AppsFlyer utm_source chain) ---
-keep class com.android.installreferrer.** { *; }
-dontwarn com.android.installreferrer.**

# --- GAID (com.google.android.gms:play-services-ads-identifier) ---
-keep class com.google.android.gms.ads.identifier.** { *; }
-dontwarn com.google.android.gms.ads.identifier.**

# --- Microsoft Clarity (session replay + custom events) ---
-keep class com.microsoft.clarity.** { *; }
-dontwarn com.microsoft.clarity.**

# --- Parcelable ---
-keep class * implements android.os.Parcelable {
    public static final android.os.Parcelable$Creator *;
}

# --- Native methods (JNI bridge) ---
-keepclasseswithmembernames class * {
    native <methods>;
}

# --- Strip verbose log calls in release ---
-assumenosideeffects class android.util.Log {
    public static int v(...);
    public static int d(...);
    public static int i(...);
}

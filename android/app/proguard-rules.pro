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

# Flutter / Play Core (older Flutter expects deferred-component classes that
# Play Core dropped; ignore the warnings so R8 doesn't fail.)
-dontwarn io.flutter.embedding.**
-dontwarn com.google.android.play.core.**

# ───────── AMap (高德地图 / 高德定位) ─────────
# AMap 3D map + location SDKs load a native library which uses JNI reflection
# to look up the following classes at startup. Without these keep rules, R8
# strips them in release builds and the app SIGABRTs the moment the map is
# created (java.lang.ClassNotFoundException: com.autonavi.base.amap.mapcore.ClassTools).
-keep class com.amap.api.**            { *; }
-keep class com.autonavi.**             { *; }
-keep class com.loc.**                  { *; }
-keep interface com.amap.api.**         { *; }

# Some AMap classes implement Parcelable; keep the CREATOR fields so
# parcel marshalling still works after minification.
-keepclassmembers class * implements android.os.Parcelable {
    public static final android.os.Parcelable$Creator CREATOR;
}

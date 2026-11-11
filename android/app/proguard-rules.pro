# Flutter Local Notifications & Gson R8 ProGuard Keep Rules
# Bảo toàn generic signatures để Gson TypeToken không bị lỗi khi R8/ProGuard rút gọn code release

-keepattributes Signature
-keepattributes *Annotation*
-keepattributes EnclosingMethod, InnerClasses

# Preserve Gson TypeToken
-keep class com.google.gson.reflect.TypeToken { *; }
-keep class * extends com.google.gson.reflect.TypeToken
-keepclassmembers class * extends com.google.gson.reflect.TypeToken {
    <init>(...);
}

# Preserve Flutter Local Notifications receivers & classes
-keep class com.dexterous.flutterlocalnotifications.** { *; }
-keepclassmembers class com.dexterous.flutterlocalnotifications.** { *; }

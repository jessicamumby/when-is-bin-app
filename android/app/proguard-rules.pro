# Release builds are shrunk and obfuscated by R8; debug builds are not. These
# rules keep what flutter_local_notifications needs at runtime and would
# otherwise only break in a production build.
#
# The plugin persists scheduled reminders as JSON through Gson, reading them
# back with `new TypeToken<ArrayList<NotificationDetails>>() {}`. R8 strips the
# generic signature from that anonymous subclass, so every zonedSchedule call
# failed in release with "java.lang.RuntimeException: Missing type parameter"
# and no reminder was ever saved. Rules follow the plugin's README and Gson's
# own android-proguard-example.

# Gson reads generic types and annotations through reflection.
-keepattributes Signature
-keepattributes *Annotation*
-keepattributes EnclosingMethod,InnerClasses
-dontwarn sun.misc.**

-keep class * extends com.google.gson.TypeAdapter
-keep class * implements com.google.gson.TypeAdapterFactory
-keep class * implements com.google.gson.JsonSerializer
-keep class * implements com.google.gson.JsonDeserializer
-keepclassmembers,allowobfuscation class * {
  @com.google.gson.annotations.SerializedName <fields>;
}

# TypeToken and its anonymous subclasses must keep their generic signature.
-keep,allowobfuscation,allowshrinking class com.google.gson.reflect.TypeToken
-keep,allowobfuscation,allowshrinking class * extends com.google.gson.reflect.TypeToken

# The plugin's models are serialized field-by-field. Obfuscated field names
# would differ between app versions, so reminders saved by one release could
# not be read back by the next (the boot/update receiver re-arms them).
-keep class com.dexterous.** { *; }

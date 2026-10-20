# kotlinx.serialization: keep generated serializers for Rodwave's @Serializable models.
-keepattributes *Annotation*, InnerClasses
-dontnote kotlinx.serialization.**
-keepclassmembers class kotlinx.serialization.json.** { *** Companion; }
-keepclasseswithmembers class kotlinx.serialization.json.** { kotlinx.serialization.KSerializer serializer(...); }
-keep,includedescriptorclasses class com.rodwave.**$$serializer { *; }
-keepclassmembers class com.rodwave.** { *** Companion; }
-keepclasseswithmembers class com.rodwave.** { kotlinx.serialization.KSerializer serializer(...); }

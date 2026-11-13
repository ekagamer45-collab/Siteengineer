# Flutter Wrapper
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Camera & CameraX (Android Jetpack)
-keep class androidx.camera.core.** { *; }
-keep class androidx.camera.camera2.** { *; }
-keep class androidx.camera.lifecycle.** { *; }
-keep class androidx.camera.view.** { *; }
-keep class androidx.camera.video.** { *; }
-keep class androidx.concurrent.futures.** { *; }
-keep class io.flutter.plugins.camerax.** { *; }
-dontwarn androidx.camera.**
-dontwarn io.flutter.plugins.camerax.**

# File Picker
-keep class com.mr.flutter.plugin.filepicker.** { *; }
-dontwarn com.mr.flutter.plugin.filepicker.**

# Image Picker
-keep class io.flutter.plugins.imagepicker.** { *; }
-dontwarn io.flutter.plugins.imagepicker.**

# Gal (Gallery Saver)
-keep class com.natsuk4ze.gal.** { *; }
-dontwarn com.natsuk4ze.gal.**

# Geolocator & Geocoding
-keep class com.baseflow.geolocator.** { *; }
-keep class com.baseflow.geocoding.** { *; }
-dontwarn com.baseflow.**

# AndroidX Lifecycle components
-keep class androidx.lifecycle.** { *; }
-keep class * extends androidx.lifecycle.LifecycleObserver { *; }
-keepattributes *Annotation*,Signature,InnerClasses,EnclosingMethod

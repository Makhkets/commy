# gomobile generates JNI bindings that are reached only from native code, so R8
# sees no Java caller and strips them. The result is a release build that works
# in debug and crashes with NoSuchMethodError the moment the tunnel starts.
-keep class go.** { *; }
-keep class io.nekohasekai.libbox.** { *; }

# Our PlatformInterface implementation is instantiated from Go through JNI.
-keep class dev.commy.app.tunnel.** { *; }

# Flutter's embedding is already covered by its own consumer rules; this keeps
# the plugin registrant safe when tree shaking is aggressive.
-keep class io.flutter.plugin.** { *; }

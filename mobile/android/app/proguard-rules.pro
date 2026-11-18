# Keep WebRTC (voice / video calls) classes in release builds
-keep class org.webrtc.** { *; }
-keep class com.cloudwebrtc.webrtc.** { *; }
-dontwarn org.webrtc.**

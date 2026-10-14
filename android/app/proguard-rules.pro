# Flutter
-keep class io.flutter.** { *; }
-keep class io.flutter.embedding.** { *; }
-keep class io.flutter.plugins.** { *; }

# sqflite
-keep class com.tekartik.sqflite.** { *; }

# url_launcher
-keep class io.flutter.plugins.urllauncher.** { *; }

# Dart/Flutter reflection
-keepattributes *Annotation*
-keepattributes SourceFile,LineNumberTable

# Firebase (auth/firestore/core) — evita o R8 remover classe usada só via
# reflexão/serialização interna do SDK
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }

# mobile_scanner (usa o ML Kit de leitura de código de barras)
-keep class com.google.mlkit.** { *; }

# in_app_purchase (Play Billing)
-keep class com.android.billingclient.** { *; }

# O Flutter engine referencia opcionalmente o Play Core (componentes
# adiáveis/Play Feature Delivery), que este app não usa como dependência —
# sem isso o R8 trata essas classes ausentes como erro fatal de compilação.
-dontwarn com.google.android.play.core.**

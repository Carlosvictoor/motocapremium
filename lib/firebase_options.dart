import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;

/// Opções de conexão com o projeto Firebase (gerado a partir do
/// `android/app/google-services.json`). Só Android está configurado por
/// enquanto — se for adicionar iOS/web depois, rode `flutterfire configure`
/// ou registre um novo app no console e adicione o bloco correspondente aqui.
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions não configurado para esta plataforma (${defaultTargetPlatform.name}).',
        );
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyBt7tXHmxBQdGGXr2vLJInapUcWcwSuz2A',
    appId: '1:561424361982:android:cbd233fd4317b41a0db8af',
    messagingSenderId: '561424361982',
    projectId: 'filmeon-a0783',
    storageBucket: 'filmeon-a0783.firebasestorage.app',
  );
  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyDjDN40bmpjQcdXriV0jSszYzx51Y57WIY',
    appId: '1:561424361982:web:72113e8a999d88b10db8af',
    messagingSenderId: '561424361982',
    projectId: 'filmeon-a0783',
    authDomain: 'filmeon-a0783.firebaseapp.com',
    storageBucket: 'filmeon-a0783.firebasestorage.app',
    measurementId: 'G-DRPKL3733G',
  );
}

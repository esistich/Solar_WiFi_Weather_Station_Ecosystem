import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
	show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
	if (kIsWeb) throw UnsupportedError('Web wird nicht unterstützt.');
	switch (defaultTargetPlatform) {
	  case TargetPlatform.android:
		return android;
	  default:
		throw UnsupportedError(
		  'Nicht unterstützte Plattform: $defaultTargetPlatform',
		);
	}
  }

  static const FirebaseOptions android = FirebaseOptions(
	apiKey: 'AIzaSyDRxo5QFer0qk8Ctfemy2qZica4YImjEWo',
	appId: '1:89293864335:android:1ca2905a8e572599121ffa',
	messagingSenderId: '89293864335',
	projectId: 'swsfb-11c77',
	storageBucket: 'swsfb-11c77.firebasestorage.app',
  );
}

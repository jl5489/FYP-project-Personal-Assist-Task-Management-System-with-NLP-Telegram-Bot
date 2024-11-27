// File generated by FlutterFire CLI.
// ignore_for_file: type=lint
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

/// Default [FirebaseOptions] for use with your Firebase apps.
///
/// Example:
/// ```dart
/// import 'firebase_options.dart';
/// // ...
/// await Firebase.initializeApp(
///   options: DefaultFirebaseOptions.currentPlatform,
/// );
/// ```
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        return macos;
      case TargetPlatform.windows:
        return windows;
      case TargetPlatform.linux:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for linux - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyBRlVc59OlCFgSVxTQISTPhbC0i7m2RKcw',
    appId: '1:1015831907465:web:9334e3660d1445a2664a58',
    messagingSenderId: '1015831907465',
    projectId: 'todolist-f6c6d',
    authDomain: 'todolist-f6c6d.firebaseapp.com',
    storageBucket: 'todolist-f6c6d.appspot.com',
    measurementId: 'G-H1Q9GCP9H1',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyCgqPR4duE7DecNtPpaIKEmglwVW3cX_ts',
    appId: '1:1015831907465:android:6a7e693e2f1684f8664a58',
    messagingSenderId: '1015831907465',
    projectId: 'todolist-f6c6d',
    storageBucket: 'todolist-f6c6d.appspot.com',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyCROe8J8Rn9GkVdE7vtmoc_GJRVBeo9bZM',
    appId: '1:1015831907465:ios:dd5942b9df3f7182664a58',
    messagingSenderId: '1015831907465',
    projectId: 'todolist-f6c6d',
    storageBucket: 'todolist-f6c6d.appspot.com',
    iosBundleId: 'com.yoshi.todark',
  );

  static const FirebaseOptions macos = FirebaseOptions(
    apiKey: 'AIzaSyCROe8J8Rn9GkVdE7vtmoc_GJRVBeo9bZM',
    appId: '1:1015831907465:ios:58b9878c0dded2ec664a58',
    messagingSenderId: '1015831907465',
    projectId: 'todolist-f6c6d',
    storageBucket: 'todolist-f6c6d.appspot.com',
    iosBundleId: 'com.example.darkTodo',
  );

  static const FirebaseOptions windows = FirebaseOptions(
    apiKey: 'AIzaSyBRlVc59OlCFgSVxTQISTPhbC0i7m2RKcw',
    appId: '1:1015831907465:web:93549baaca71a825664a58',
    messagingSenderId: '1015831907465',
    projectId: 'todolist-f6c6d',
    authDomain: 'todolist-f6c6d.firebaseapp.com',
    storageBucket: 'todolist-f6c6d.appspot.com',
    measurementId: 'G-Y2ND0EDY08',
  );
}

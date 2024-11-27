import 'dart:io';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/services.dart';
import 'package:flutter_displaymode/flutter_displaymode.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:time_machine/time_machine.dart';
import 'package:todark/app/controller/isar_contoller.dart';
import 'package:todark/app/ui/home.dart';
import 'package:todark/app/ui/onboarding.dart';
import 'package:todark/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:get/get.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:isar/isar.dart';
import 'package:todark/theme/theme_controller.dart';
import 'package:todark/app/utils/device_info.dart';
import 'app/data/db.dart';
import 'translation/translation.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'package:firebase_auth/firebase_auth.dart'; // Added for Firebase Authentication
import 'package:todark/app/ui/login_screen.dart'; // Added import for login screen
import 'package:todark/app/ui/signup_screen.dart'; // Added import for signup screen
import 'package:todark/app/controller/auth_controller.dart';
import 'package:todark/app/controller/todo_controller.dart';

FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

late Isar isar;
late Settings settings;

bool amoledTheme = false;
bool materialColor = false;
bool isImage = true;
String timeformat = '24';
String firstDay = 'monday';
Locale locale = const Locale('en', 'US');

final List appLanguages = [
  {'name': 'العربية', 'locale': const Locale('ar', 'AR')},
  {'name': 'Deutsch', 'locale': const Locale('de', 'DE')},
  {'name': 'English', 'locale': const Locale('en', 'US')},
  {'name': 'Español', 'locale': const Locale('es', 'ES')},
  {'name': 'Français', 'locale': const Locale('fr', 'FR')},
  {'name': 'Italiano', 'locale': const Locale('it', 'IT')},
  {'name': '한국어', 'locale': const Locale('ko', 'KR')},
  {'name': 'فارسی', 'locale': const Locale('fa', 'IR')},
  {'name': 'Русский', 'locale': const Locale('ru', 'RU')},
  {'name': 'Tiếng việt', 'locale': const Locale('vi', 'VN')},
  {'name': 'Türkçe', 'locale': const Locale('tr', 'TR')},
  {'name': '中文(简体)', 'locale': const Locale('zh', 'CN')},
  {'name': '中文(繁體)', 'locale': const Locale('zh', 'TW')},
];

Widget _determineInitialRoute() {
  final User? user = FirebaseAuth.instance.currentUser;
  if (user != null) {
    return settings.onboard ? const HomePage() : const OnBording();
  }
  return const LoginScreen();
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  String timeZoneName;

  try {
    // Initialize Firebase first
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    // Initialize IsarController and open database
    final isarController = IsarController();
    isar = await isarController.openDB(); // Set the global isar instance
    Get.put(isarController, permanent: true); // Register controller with GetX

    // Now that Isar is initialized, we can register other controllers
    Get.put(AuthController());
    Get.put(ThemeController());
    Get.lazyPut(() => TodoController());

    // Initialize settings now that Isar is available
    settings = isar.settings.where().findFirstSync() ?? Settings();
    await initSettings();

    print("Initialization completed successfully. Starting app...");
  } catch (error) {
    print("Initialization failed: $error");
    runApp(MaterialApp(
      home: Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 16),
              Text(
                "Failed to initialize: $error",
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16),
              ),
            ],
          ),
        ),
      ),
    ));
    return;
  }

  // Continue with other initializations
  DeviceFeature().init();

  if (Platform.isAndroid) {
    await setOptimalDisplayMode();
  }

  if (Platform.isAndroid || Platform.isIOS) {
    timeZoneName = await FlutterTimezone.getLocalTimezone();
  } else {
    timeZoneName = '${DateTimeZone.local}';
  }

  tz.initializeTimeZones();
  tz.setLocalLocation(tz.getLocation(timeZoneName));

  const initializationSettingsIos = DarwinInitializationSettings();
  const initializationSettingsAndroid =
      AndroidInitializationSettings('@mipmap/ic_launcher');
  const initializationSettingsLinux =
      LinuxInitializationSettings(defaultActionName: 'ToDark');

  const initializationSettings = InitializationSettings(
    android: initializationSettingsAndroid,
    linux: initializationSettingsLinux,
    iOS: initializationSettingsIos,
  );

  await flutterLocalNotificationsPlugin.initialize(initializationSettings);

  runApp(MyApp(_determineInitialRoute()));
}

Future<void> setOptimalDisplayMode() async {
  final List<DisplayMode> supported = await FlutterDisplayMode.supported;
  final DisplayMode active = await FlutterDisplayMode.active;
  final List<DisplayMode> sameResolution = supported
      .where((DisplayMode m) =>
          m.width == active.width && m.height == active.height)
      .toList()
    ..sort((DisplayMode a, DisplayMode b) =>
        b.refreshRate.compareTo(a.refreshRate));
  final DisplayMode mostOptimalMode =
      sameResolution.isNotEmpty ? sameResolution.first : active;
  await FlutterDisplayMode.setPreferredMode(mostOptimalMode);
}

Future<void> initSettings() async {
  if (settings.language == null) {
    settings.language = '${Get.deviceLocale}';
    await isar.writeTxn(() => isar.settings.put(settings));
  }

  if (settings.theme == null) {
    settings.theme = 'system';
    await isar.writeTxn(() => isar.settings.put(settings));
  }

  if (settings.isImage == null) {
    settings.isImage = true;
    await isar.writeTxn(() => isar.settings.put(settings));
  }
}

class MyApp extends StatefulWidget {
  final Widget initialRoute;

  const MyApp(this.initialRoute, {super.key});

  static Future<void> updateAppState(
    BuildContext context, {
    bool? newAmoledTheme,
    bool? newMaterialColor,
    bool? newIsImage,
    String? newTimeformat,
    String? newFirstDay,
    Locale? newLocale,
  }) async {
    final state = context.findAncestorStateOfType<_MyAppState>()!;

    if (newAmoledTheme != null) {
      state.changeAmoledTheme(newAmoledTheme);
    }
    if (newMaterialColor != null) {
      state.changeMarerialTheme(newMaterialColor);
    }
    if (newTimeformat != null) {
      state.changeTimeFormat(newTimeformat);
    }
    if (newFirstDay != null) {
      state.changeFirstDay(newFirstDay);
    }
    if (newLocale != null) {
      state.changeLocale(newLocale);
    }
    if (newIsImage != null) {
      state.changeIsImage(newIsImage);
    }
  }

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final themeController = Get.put(ThemeController());

  void changeAmoledTheme(bool newAmoledTheme) {
    setState(() {
      amoledTheme = newAmoledTheme;
    });
  }

  void changeMarerialTheme(bool newMaterialColor) {
    setState(() {
      materialColor = newMaterialColor;
    });
  }

  void changeIsImage(bool newIsImage) {
    setState(() {
      isImage = newIsImage;
    });
  }

  void changeTimeFormat(String newTimeformat) {
    setState(() {
      timeformat = newTimeformat;
    });
  }

  void changeFirstDay(String newFirstDay) {
    setState(() {
      firstDay = newFirstDay;
    });
  }

  void changeLocale(Locale newLocale) {
    setState(() {
      locale = newLocale;
    });
  }

  @override
  void initState() {
    amoledTheme = settings.amoledTheme;
    materialColor = settings.materialColor;
    timeformat = settings.timeformat;
    firstDay = settings.firstDay;
    isImage = settings.isImage!;
    locale = Locale(
        settings.language!.substring(0, 2), settings.language!.substring(3));
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    final edgeToEdgeAvailable = DeviceFeature().isEdgeToEdgeAvailable();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

    return GestureDetector(
      onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
      child: DynamicColorBuilder(
        builder: (lightColorScheme, darkColorScheme) {
          final lightMaterialTheme = lightTheme(
              lightColorScheme?.surface, lightColorScheme, edgeToEdgeAvailable);
          final darkMaterialTheme = darkTheme(
              darkColorScheme?.surface, darkColorScheme, edgeToEdgeAvailable);
          final darkMaterialThemeOled =
              darkTheme(oledColor, darkColorScheme, edgeToEdgeAvailable);
          return GetMaterialApp(
            theme: materialColor
                ? lightColorScheme != null
                    ? lightMaterialTheme
                    : lightTheme(
                        lightColor, colorSchemeLight, edgeToEdgeAvailable)
                : lightTheme(lightColor, colorSchemeLight, edgeToEdgeAvailable),
            darkTheme: amoledTheme
                ? materialColor
                    ? darkColorScheme != null
                        ? darkMaterialThemeOled
                        : darkTheme(
                            oledColor, colorSchemeDark, edgeToEdgeAvailable)
                    : darkTheme(oledColor, colorSchemeDark, edgeToEdgeAvailable)
                : materialColor
                    ? darkColorScheme != null
                        ? darkMaterialTheme
                        : darkTheme(
                            darkColor, colorSchemeDark, edgeToEdgeAvailable)
                    : darkTheme(
                        darkColor, colorSchemeDark, edgeToEdgeAvailable),
            themeMode: themeController.theme,
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            translations: Translation(),
            locale: locale,
            fallbackLocale: const Locale('en', 'US'),
            supportedLocales:
                appLanguages.map((e) => e['locale'] as Locale).toList(),
            debugShowCheckedModeBanner: false,
            builder: EasyLoading.init(),
            title: 'ToDark',
            initialRoute: '/', // Keep this to handle the root route
            routes: {
              '/': (context) =>
                  const AuthWrapper(), // Define the root route here
              '/login': (context) => const LoginScreen(),
              '/signup': (context) => const SignupScreen(),
              '/home': (context) => const HomePage(),
              '/onboarding': (context) => const OnBording(),
            },
          );
        },
      ),
    );
  }

  Widget _buildHome() {
    final User? user =
        FirebaseAuth.instance.currentUser; // Get the current Firebase user
    if (user != null) {
      // If user is logged in, show HomePage or Onboarding
      return settings.onboard ? const HomePage() : const OnBording();
    } else {
      // If user is not logged in, show LoginScreen
      return const LoginScreen();
    }
  }
}

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasData) {
          return settings.onboard ? const HomePage() : const OnBording();
        }

        return const LoginScreen();
      },
    );
  }
}

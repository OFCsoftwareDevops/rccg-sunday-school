import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart' as provider;
import 'package:rccg_sunday_school/l10n/fallback_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'UI/app_linear_progress_bar.dart';
import 'UI/app_theme.dart';
import 'backend_data/database/constants.dart';
import 'auth/login/auth_service.dart';
import 'auth/login/login_page.dart';
import 'backend_data/service/ads/ads_consent.dart';
import 'backend_data/service/firestore/assignment_dates_provider.dart';
import 'backend_data/service/firestore/firestore_service.dart';
import 'backend_data/service/hive/hive_service.dart';
import 'backend_data/service/notification/notification_service.dart';
import 'backend_data/service/firestore/submitted_dates_provider.dart';
import 'utils/settings_provider.dart';
import 'widgets/bible_app/bible_actions/highlight_manager.dart';
import 'backend_data/service/analytics/firebase_options.dart';
import 'l10n/app_localizations.dart';
import 'widgets/bible_app/bible.dart';
import 'widgets/church/church_selection.dart';
import 'widgets/helpers/intro_page.dart';
import 'widgets/helpers/main_screen.dart';

Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);  // Required in v15.1.3+
  if (kDebugMode) {
    debugPrint("Background: ${message.notification?.title}");
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  debugPrint('STEP 1');

  await initializeAdsAndConsent();
  await HiveHelper.init();
  debugPrint('STEP 2');

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  debugPrint('STEP 3');
  FirebaseMessaging.onMessage.listen((RemoteMessage message) {
    if (kDebugMode) {
      debugPrint('Foreground message: ${message.notification?.title}');
    }
    // Optional: show local notification yourself if you want custom UI
    // Manually show as local notification
    NotificationService().showNotification(
      id: 0,  // Unique ID
      title: message.notification?.title ?? 'Notification',
      body: message.notification?.body ?? 'Tap to view',
      payload: message.data['date'],  // For deep linking
    );
  });
  debugPrint('STEP 4');

  // When app is opened from notification (terminated / background)
  FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
    if (kDebugMode) {
      debugPrint('Opened from notification! Payload: ${message.data}');
    }
    
    final date = message.data['date']; // "2025-12-7"
    if (date != null) {
      // Navigate to lesson screen
      // Example with Navigator or Riverpod/GoRouter:
      // context.go('/lesson/$date');
      // or use a global navigator key
    }
  });
  debugPrint('STEP 5');

  final initialMessage = await FirebaseMessaging.instance.getInitialMessage();
  if (initialMessage != null) {
    // Handle it (same logic as onMessageOpenedApp)
  }

  debugPrint('STEP 6');

  // Notification caller
  tz.initializeTimeZones();
  tz.setLocalLocation(tz.getLocation('America/New_York'));
  await NotificationService().initialize();

  //Workmanager().initialize(callbackDispatcher, isInDebugMode: true);
  debugPrint('STEP 7');

  // Request notification permission (Android 13+)
  if (Platform.isAndroid) {
    final status = await Permission.notification.request();
    if (kDebugMode) {
      debugPrint('Notification permission: $status');
    }
  } else if (Platform.isIOS) {
    // iOS permission requested below in setupFCM
  }

  debugPrint('STEP 8');

  // Initialize Firebase Messaging topics and get token
  /*final fcm = FirebaseMessaging.instance;
  await fcm.subscribeToTopic('all_users');
  final token = await fcm.getToken();
  if (kDebugMode) {
    debugPrint('FCM Token: $token');
  }*/

  // Consolidated FCM setup
  await setupFCM();

  debugPrint('STEP 9');

  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  
  // Initialize Google Mobile Ads SDK
  MobileAds.instance.initialize();

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  debugPrint('STEP 10');

  // ✅ Fit the entire screen
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: true,
    cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
  );

  /*/ // ==================== FCM SETUP ====================
  if (!kIsWeb /*&& (Platform.isAndroid || Platform.isIOS)*/) {
    await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    await FirebaseMessaging.instance.subscribeToTopic("all_users");
    final token = await FirebaseMessaging.instance.getToken();
    if (kDebugMode) {
      debugPrint("FCM Token: $token");
    }
  }*/
  debugPrint('STEP 11');

  // 3. Now safely read SharedPreferences (already loaded above)
  final prefs = await SharedPreferences.getInstance();
  final String savedLang = prefs.getString('language_code') ?? 'en';
  // Load highlights early
  await HighlightManager().loadFromPrefs();
  debugPrint('STEP 12');

  final currentUser = FirebaseAuth.instance.currentUser;
  if (currentUser != null && ownerEmails.contains(currentUser.email)) {
    try {
      await FirebaseMessaging.instance.subscribeToTopic("owner_notifications");
    } catch (e) {
      debugPrint("Owner topic subscription failed: $e");
    }
  }

  debugPrint('STEP 13');

  // ←←←← NEW: Initialize the AuthService sync ←←←←
  await AuthService.instance.init();

  // 4. Run the app with ALL providers
  runApp(
    ProviderScope(
      child: provider.MultiProvider(
        providers: [
          provider.ChangeNotifierProvider(create: (_) => SettingsProvider()),
          provider.ChangeNotifierProvider(create: (_) => BibleVersionManager()),
          provider.ChangeNotifierProvider(create: (_) => HighlightManager()), // Already loaded!
          // AuthService now provides church + roles + loading state
          provider.ChangeNotifierProvider<AuthService>(create: (_) => AuthService.instance),
          // Load Firestore
          provider.Provider<FirestoreService>(create: (_) => FirestoreService(churchId: null)),
          // Add more providers here later (ThemeManager, UserManager, etc.)
          provider.ChangeNotifierProvider(create: (_) => AssignmentDatesProvider()),
          provider.ChangeNotifierProvider(create: (_) => SubmittedDatesProvider()),
        ],
        child: MyApp(
          initialLocale: Locale(savedLang),
        ),
      ),
    ),
  );
}

/// Safe FCM initialization + subscription (handles simulator gracefully)
Future<void> setupFCM() async {
  final messaging = FirebaseMessaging.instance;

  // Request permission (triggers APNs registration on iOS)
  final settings = await messaging.requestPermission(
    alert: true,
    badge: true,
    sound: true,
  );
  debugPrint('User granted permission: ${settings.authorizationStatus}');

  // Subscribe to common topic safely
  try {
    String? apnsToken;
    if (Platform.isIOS) {
      // Retry getting APNs token (simulator will always be null)
      for (int i = 0; i < 8; i++) {
        apnsToken = await messaging.getAPNSToken();
        if (apnsToken != null) break;
        await Future.delayed(const Duration(milliseconds: 600));
      }

      if (apnsToken == null) {
        debugPrint("APNs token unavailable (normal on simulator or permission denied)");
        // You can still get FCM token on real device later, but skip topic on sim
        if (kDebugMode && !Platform.environment.containsKey('FLUTTER_TEST')) {
          return; // Skip subscription on simulator to avoid error
        }
      }
    }

    // Safe subscribe
    await messaging.subscribeToTopic('all_users');
    debugPrint("Subscribed to 'all_users' topic");

    final token = await messaging.getToken();
    if (kDebugMode) debugPrint('FCM Token: $token');
  } catch (e) {
    debugPrint("FCM setup/subscription error (safe to ignore on simulator): $e");
  }
}


// =============== NEW: Language-aware MyApp ===============
class MyApp extends StatefulWidget {
  //final bool hasSeenIntro;
  final Locale initialLocale;

  const MyApp({super.key, /*required this.hasSeenIntro,*/ required this.initialLocale});

  // Allow changing language from anywhere in the app
  static void setLocale(BuildContext context, Locale newLocale) {
    final state = context.findAncestorStateOfType<MyAppState>();
    state?.changeLanguage(newLocale);
  }

  @override
  State<MyApp> createState() => MyAppState();
}

class MyAppState extends State<MyApp> with WidgetsBindingObserver{
  late Locale _locale;
  bool _showIntro = true;
  bool _isPreloading = false;
  bool soundEnabled = Hive.box('settings').get('sound_enabled', defaultValue: true) as bool;
  bool preloadDone = false;
  int preloadProgress = 0; // 0 to 4
  static const int totalPreloadSteps = 4;

  @override
  void initState() {
    super.initState();
    _locale = widget.initialLocale;
    _startPreload();
    WidgetsBinding.instance.addObserver(this); // Listen for app close
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Detect full app close to reset intro
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached) {
      _showIntro = true;
    }
  }

  Future<void> _startPreload() async {
    setState(() {
      _isPreloading = true;
      preloadProgress = 0; // reset just in case
    });

    try {
      // Wait for Firebase Auth to restore state
      await FirebaseAuth.instance.authStateChanges().firstWhere(
        (user) => user != null,
        orElse: () => null, // anonymous or timeout
      ).timeout(const Duration(seconds: 6), onTimeout: () {
        debugPrint("Auth state timeout during preload start");
        return;
      });

      // Step 1
      await HighlightManager().loadFromPrefs();
      setState(() => preloadProgress = 1);

      // Step 2 - only preload Firestore if we have church
      final auth = provider.Provider.of<AuthService>(context, listen: false);
      if (auth.hasChurch && auth.churchId != null) {
        final service = context.read<FirestoreService>();
        await service.preload(context, loadAll: false);
        setState(() => preloadProgress = 2);

        await provider.Provider.of<AssignmentDatesProvider>(context, listen: false)
            .load(null, service);
        setState(() => preloadProgress = 3);
      } else {
        debugPrint("Skipping Firestore/Assignments preload — no church yet");
        setState(() {
          preloadProgress = 2;
          preloadProgress = 3;
          // jump to 3 if you want
        });
      }

      /*/ Step 2: preload returns submitted-date sets (adult/teen)
      await context.read<FirestoreService>().preload(context, loadAll: false);
      setState(() => preloadProgress = 2);

      final service = context.read<FirestoreService>();
      await provider.Provider.of<AssignmentDatesProvider>(context, listen: false).load(null, service);
      setState(() => preloadProgress = 3);*/

      // Step 3: Load Bible
      await context.read<BibleVersionManager>().loadInitialBible();
      setState(() => preloadProgress = 4);

      if (mounted) {
      setState(() {
        _isPreloading = false;
        preloadDone = true;
      });
    }

      /*if (!mounted) return;
      setState(() {
        _isPreloading = false;
        preloadDone = true;
      });*/
  } catch (e, st) {
    debugPrint("Preload step failed: $e\n$st");
    // Still allow app to continue
    if (mounted) {
      setState(() {
        _isPreloading = false;
        preloadDone = true;
      });
    }
  }
  }

  void changeLanguage(Locale locale) async {
    if (_locale.languageCode == locale.languageCode) return;

    // 1. Update UI / provider state
    setState(() => _locale = locale);

    // 2. Save preference (you already do this)
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('language_code', locale.languageCode);

    // 3. ← NEW: Clear language-sensitive caches
    await HiveBoxes.lessons.clear();
    await HiveBoxes.assignments.clear();
  }

  @override
  Widget build(BuildContext context) {
    return ScreenUtilInit(
      designSize: Size(448, 998),  // Your design mockup size (e.g., common phone)
      minTextAdapt: true,
      splitScreenMode: true,
      builder: (context, child) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          locale: _locale,
        
          // THIS IS THE ONLY LIST THAT WORKS FOR en + fr + yo
          localizationsDelegates: const [
            AppLocalizations.delegate,     
            GlobalMaterialLocalizations.delegate, // ← supports en + fr fully
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            FallbackMaterialLocalizationsDelegate(),
            FallbackCupertinoLocalizationsDelegate(),
          ],
          supportedLocales: AppLocalizations.supportedLocales, // en, fr, yo
          theme: AppTheme.lightTheme(soundEnabled: soundEnabled),
          darkTheme: AppTheme.darkTheme(soundEnabled: soundEnabled),
          themeMode: ThemeMode.system,
          home: provider.Consumer<AuthService>(
            builder: (context, auth, child) {  
              // Show intro only on very first app open ever
              if (_showIntro) {
                return IntroPage(
                  preloadDone: preloadDone,
                  isLoading: !preloadDone,
                  preloadProgress: preloadProgress,
                  totalPreloadSteps: totalPreloadSteps,
                  onFinish: preloadDone
                      ? () => setState(() => _showIntro = false)
                      : null, 
                );
              }
        
              // Still loading auth state / church / roles
              if (auth.isLoading) {
                return const Scaffold(
                  body: Center(child: LinearProgressBar()),
                );
              }
              
              // No user signed in → go to your login / signup flow
              if (auth.currentUser == null) {
                return const AuthScreen();
              }
              // User signed in but no church selected yet
              // Skip church selection if user is anonymous (guest mode)
              final user = auth.currentUser!;
              if (!auth.hasChurch && !user.isAnonymous) {
                return const ChurchOnboardingScreen();
              }
              // Everything ready → go to main app
              return MainScreen();
            },
          ),
        );
      }
    );
  }
}
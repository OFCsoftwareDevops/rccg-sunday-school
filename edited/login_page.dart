// lib/screens/auth_screen.dart

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import '../../UI/app_buttons.dart';
import '../../UI/app_colors.dart';
import '../../UI/app_sound.dart';
import '../../backend_data/service/analytics/analytics_service.dart';
import '../../l10n/app_localizations.dart';
import '../../widgets/helpers/snackbar.dart';
import 'auth_service.dart';
import '../../UI/app_loading_overlay.dart';

// lib/screens/auth_screen.dart
class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  bool _isLoading = false;
  int _selectedTab = 0; // 0 = Google, 1 = Guest
  int get _guestTabIndex => Platform.isIOS ? 2 : 1;

  @override
  void initState() {
    super.initState();
    lifecycleListener; // Activate the listener (just by referencing it)
  }

  @override
  void dispose() {
    lifecycleListener.dispose();
    super.dispose();
  }

  late final AppLifecycleListener lifecycleListener = AppLifecycleListener(  // ← No underscore!
    onResume: () {
      // Optional: Force notify if needed (usually not required)
      AuthService.instance.notifyListeners();
    },
  );

  void debugAppleToken(String token) {
    final parts = token.split('.');
    final payload = utf8.decode(
      base64Url.decode(base64Url.normalize(parts[1])),
    );
    debugPrint("APPLE TOKEN PAYLOAD:");
    debugPrint(payload);
  }

  Future<void> _handleGoogleSignIn() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);

    try {
      final GoogleSignInAccount? googleUser = await GoogleSignIn().signIn();
      if (googleUser == null) {
        setState(() => _isLoading = false);
        LoadingOverlay.hide();
        return; // User cancelled
      }

      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      await FirebaseAuth.instance.signInWithCredential(credential);

      if (!mounted) return;
      
    } catch (e) {
      LoadingOverlay.hide();
      if (mounted) {
        showTopToast(
          context,
          AppLocalizations.of(context)?.signInFailed ?? "Sign-in failed",
          backgroundColor: AppColors.error,
          textColor: AppColors.onError,
          duration: const Duration(seconds: 5),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
      LoadingOverlay.hide();
    }
  }

  Future<void> _handleAppleSignIn() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);

    try {
      final rawNonce = _generateNonce();
      final hashedNonce = sha256.convert(utf8.encode(rawNonce)).toString();

      final appleCredential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        nonce: hashedNonce,
      );

      if (appleCredential.identityToken == null) {
        throw Exception("Missing Apple identity token");
      }

      debugPrint("identityToken null? ${appleCredential.identityToken == null}");
      debugPrint("identityToken length: ${appleCredential.identityToken?.length}");
      debugAppleToken(appleCredential.identityToken!);


      final oauthCredential = OAuthProvider("apple.com").credential(
        idToken: appleCredential.identityToken,
        rawNonce: rawNonce,
        accessToken: appleCredential.authorizationCode,
      );

      await FirebaseAuth.instance.signInWithCredential(oauthCredential);

    } on SignInWithAppleAuthorizationException catch (e) {
      debugPrint("🍎 Apple Sign-in error code: ${e.code}");
      debugPrint("🍎 Apple Sign-in error message: ${e.message}");
      if (e.code == AuthorizationErrorCode.canceled) {
        return;
      }

      if (mounted) {
        showTopToast(
          context,
          AppLocalizations.of(context)?.applSignInFailed ??
              "Apple sign-in failed",
          backgroundColor: AppColors.error,
          textColor: AppColors.onError,
          duration: const Duration(seconds: 5),
        );
      }
    } catch (e, stack) {
      debugPrint("🔥 Apple Sign-in general error: $e");
      debugPrint("🔥 Stack trace:\n$stack");
      
      if (mounted) {
        showTopToast(
          context,
          AppLocalizations.of(context)?.signInFailed ??
              "Sign-in failed",
          backgroundColor: AppColors.error,
          textColor: AppColors.onError,
          duration: const Duration(seconds: 5),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
      LoadingOverlay.hide();
    }
  }


  // Helper function to generate secure nonce
  String _generateNonce([int length = 32]) {
    const charset = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._';
    final random = Random.secure();
    return List.generate(length, (_) => charset[random.nextInt(charset.length)]).join();
  }

  Future<void> _handleAnonymousLogin() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);
    LoadingOverlay.hide();

    try {
      await FirebaseAuth.instance.signInAnonymously();

    } catch (e) {
      LoadingOverlay.hide();
      if (mounted) {
        showTopToast(
          context,
          AppLocalizations.of(context)?.guestModeFailed ?? "Guest mode failed",
          backgroundColor: AppColors.error,
          textColor: AppColors.onError,
          duration: const Duration(seconds: 5),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
      LoadingOverlay.hide();
    }
  }

  Widget _buildTabContainer(
    int index, 
    String label, {
    String? image, 
    IconData? icon, 
    bool isTextOnly = false
  }) {
    final isSelected = _selectedTab == index;
    return Expanded(
      child: InkWell(
        onTap: () {
          // analytics + setState
          setState(() => _selectedTab = index);
        },
        child: Container(
          decoration: BoxDecoration(
            color: isSelected ? Colors.white : Colors.transparent,
            // Important: only apply border radius to outer edges
            borderRadius: _getEdgeBorderRadius(index),
          ),
          child: Center(
            child: isTextOnly
                ? Text(
                    label,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16.sp,
                      color: isSelected ? Theme.of(context).colorScheme.primary : Colors.white70,
                    ),
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (image != null) Image.asset(image, height: 20.sp, color: isSelected ? Theme.of(context).colorScheme.primary : Colors.white70),
                      if (icon != null) Icon(icon, size: 20.sp, color: isSelected ? Theme.of(context).colorScheme.primary : Colors.white70),
                      if (image != null || icon != null) SizedBox(width: 8.sp),
                      Text(
                        label,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16.sp,
                          color: isSelected ? Theme.of(context).colorScheme.primary : Colors.white70,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  BorderRadius _getEdgeBorderRadius(int index) {
    final isFirst = index == 0;
    final isLast = (Platform.isIOS && index == 2) || (!Platform.isIOS && index == 1);

    if (isFirst) {
      return BorderRadius.only(
        topLeft: Radius.circular(30.sp),
        bottomLeft: Radius.circular(30.sp),
      );
    } else if (isLast) {
      return BorderRadius.only(
        topRight: Radius.circular(30.sp),
        bottomRight: Radius.circular(30.sp),
      );
    }
    return BorderRadius.zero;
  }

  @override
  Widget build(BuildContext context) {
    //return Container(
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.background,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [ Color.fromARGB(255, 255, 255, 255),AppColors.secondary, AppColors.darkSurface],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: EdgeInsets.all(20.sp),
            child: Column(
              children: [
                SizedBox(height: 40.sp),
                // Logo
                Center(
                  child: Container(
                    padding: EdgeInsets.all(0),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white, 
                        width: 3.sp,
                      ),
                    ),
                    child: ClipOval(
                      child: Image.asset(
                        'assets/images/rccg_logo.png',
                        height: 120.sp,
                        width: 120.sp,
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => Icon(Icons.church, size: 70.sp, color: Colors.white),
                      ),
                    ),
                  ),
                ),
                SizedBox(height: 20.sp),

                Text(
                  AppLocalizations.of(context)?.login ?? "Login",
                  textAlign: TextAlign.center,
                    style: TextStyle(
                    fontSize: 28.sp,
                    fontWeight: FontWeight.w700,
                    color: AppColors.onSecondary,
                    letterSpacing: 0.5,
                  ),
                ),
                SizedBox(height: 8.sp),
                Text(
                  AppLocalizations.of(context)?.signInToCreateOrJoin ?? "Sign in to create or join your church",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16.sp,
                    color: AppColors.onSecondary,
                    height: 1.4,
                  ),
                ),

                const Spacer(),

                // Build method
                Column(
                  children: [
                    // Segmented Toggle: Google | Apple (iOS only) | Guest
                    IntrinsicHeight(
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.3),
                          borderRadius: BorderRadius.circular(30.sp),
                        ),
                        child: Row(
                          children: [
                            // Google tab
                            Expanded(
                              child: InkWell(
                                onTap: () async {
                                  await AnalyticsService.logButtonClick('google_login');
                                  setState(() => _selectedTab = 0);
                                },
                                enableFeedback: AppSounds.soundEnabled,
                                child: Container(
                                  padding: EdgeInsets.symmetric(vertical: 16.sp),
                                  decoration: BoxDecoration(
                                    color: _selectedTab == 0 ? Colors.white : Colors.transparent,
                                    borderRadius: BorderRadius.circular(30.sp),
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Image.asset('assets/images/google_logo.png', 
                                        height: 20.sp,
                                        color: _selectedTab == 0 
                                          ? Theme.of(context).colorScheme.primary 
                                          : Theme.of(context).colorScheme.onPrimary.withOpacity(0.5),
                                      ),
                                      SizedBox(width: 8.sp),
                                      Text(
                                        "Google", 
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16.sp,
                                          color: _selectedTab == 0 
                                            ? Theme.of(context).colorScheme.primary 
                                            : Theme.of(context).colorScheme.onPrimary.withOpacity(0.5),
                                        )
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),

                            // Vertical divider after Google (only if next tab exists)
                            VerticalDivider(
                              color: (Platform.isIOS && _selectedTab == 2) 
                                ? Colors.white.withOpacity(0.4) 
                                : Colors.transparent, // lightly transparent white
                              thickness: 1.sp,
                              width: 1.sp,
                              indent: 8.sp,     // optional: shortens line a bit from top
                              endIndent: 8.sp,  // optional: shortens from bottom
                            ),
                              
                            // Apple tab – only show on iOS
                            if (Platform.isIOS)...[
                              Expanded(
                                child: InkWell(
                                  onTap: () async {
                                    await AnalyticsService.logButtonClick('iOS_login');
                                    setState(() => _selectedTab = 1);
                                  },
                                  enableFeedback: AppSounds.soundEnabled,
                      
                                  child: Container(
                                    padding: EdgeInsets.symmetric(vertical: 16.sp),
                                    decoration: BoxDecoration(
                                      color: _selectedTab == 1 ? Colors.white : Colors.transparent,
                                      borderRadius: BorderRadius.circular(30.sp),
                                    ),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          Icons.apple, 
                                          size: 20.sp,
                                          color: _selectedTab == 1 
                                            ? Theme.of(context).colorScheme.primary 
                                            : Theme.of(context).colorScheme.onPrimary.withOpacity(0.5),
                                        ),
                                        SizedBox(width: 8.sp),
                                        Text(
                                          "Apple", 
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 16.sp,
                                            color: _selectedTab == 1 
                                              ? Theme.of(context).colorScheme.primary 
                                              : Theme.of(context).colorScheme.onPrimary.withOpacity(0.5),
                                          )
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              // Vertical divider after Apple (before Guest)
                              VerticalDivider(
                                color: (Platform.isIOS && _selectedTab == 0) 
                                  ? Colors.white.withOpacity(0.4)
                                  : const Color.fromARGB(0, 255, 255, 255).withOpacity(0.0),
                                thickness: 1.sp,
                                width: 1.sp,
                                indent: 8.sp,
                                endIndent: 8.sp,
                              ),
                            ],
                            // Guest tab
                            Expanded(
                              child: InkWell(
                                onTap: () async {
                                  final tabName = Platform.isIOS ? 'ios_device': 'android_device';
                                  await AnalyticsService.logButtonClick('Anonymous_login_$tabName');
                      
                                  setState(() => _selectedTab = Platform.isIOS ? 2 : 1);
                                },// adjust index if no Apple
                                enableFeedback: AppSounds.soundEnabled,
                                child: Container(
                                  padding: EdgeInsets.symmetric(vertical: 16.sp),
                                  decoration: BoxDecoration(
                                    color: _selectedTab == (Platform.isIOS ? 2 : 1) ? Colors.white : Colors.transparent,
                                    borderRadius: BorderRadius.circular(30.sp),
                                  ),
                                  child: Text(
                                    AppLocalizations.of(context)?.guest ?? "Guest",
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16.sp,
                                      color: _selectedTab == (Platform.isIOS ? 2 : 1) 
                                        ? Theme.of(context).colorScheme.primary 
                                        : Theme.of(context).colorScheme.onPrimary.withOpacity(0.5),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    SizedBox(height: 60.sp),

                    // Large Action Button
                    LoginButtons(
                      text: "",
                      context: context,
                      topColor: (Platform.isIOS && _selectedTab == 1) ? const Color.fromARGB(255, 41, 41, 41) : Colors.white, // Apple gets black button
                      borderColor: Colors.transparent,
                      onPressed: _isLoading
                          ? () {}
                          : () {
                              if (_selectedTab == 0) {
                                _handleGoogleSignIn();
                              } else if (_selectedTab == 1 && Platform.isIOS) {
                                _handleAppleSignIn();
                              } else {
                                _handleAnonymousLogin();
                              }
                            },
                      child: _isLoading
                          ? SizedBox(
                              height: 24.sp,
                              width: 24.sp,
                              child: CircularProgressIndicator(
                                color: Color.fromARGB(221, 188, 22, 22),
                                strokeWidth: 3.sp,
                              ),
                            )
                          : Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // Google
                                if (_selectedTab == 0) ...[
                                  Image.asset('assets/images/google_logo.png', height: 20.sp),
                                  SizedBox(width: 12.sp),
                                  Text(
                                    AppLocalizations.of(context)?.continueWithGoogle ?? "Continue with Google",
                                    style: TextStyle(color: Colors.black87, fontSize: 16.sp, fontWeight: FontWeight.bold),
                                  ),
                                ]
                                // Apple
                                else if (_selectedTab == 1 && Platform.isIOS) ...[
                                  Icon(Icons.apple, size: 20.sp, color: Colors.white),
                                  SizedBox(width: 12.sp),
                                  Text(
                                    AppLocalizations.of(context)?.signInWithApple ?? "Sign in with Apple",
                                    style: TextStyle(color: Colors.white, fontSize: 16.sp, fontWeight: FontWeight.bold),
                                  ),
                                ]
                                // Guest
                                else ...[
                                  Icon(Icons.person_outline, size: 20.sp, color: Colors.black87),
                                  SizedBox(width: 12.sp),
                                  Text(
                                    AppLocalizations.of(context)?.continueAsGuest ?? "Continue as Guest",
                                    style: TextStyle(color: Colors.black87, fontSize: 16.sp, fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ],
                            ),
                    ),
                  ],
                ),
                SizedBox(height: 15.sp),
                Text(
                  _selectedTab == _guestTabIndex
                      ? AppLocalizations.of(context)?.guestDataWarning ?? "All data are temporarily saved and lost after logout."
                      : "",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.onPrimary, fontSize: 14.sp),
                ),

                const Spacer(),

                // Subtle info text
                Text(
                  _selectedTab == _guestTabIndex
                      ? AppLocalizations.of(context)?.limitedAccessDescription ?? "Limited access: use general mode only"
                      : AppLocalizations.of(context)?.fullAccessDescription ?? "Full access: create or join your church",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.onPrimary, fontSize: 14.sp),
                ),
                SizedBox(height: 40.sp),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
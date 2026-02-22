// lib/screens/user_profile_screen.dart

import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:provider/provider.dart';
import '../../UI/app_bar.dart';
import '../../UI/app_buttons.dart';
import '../../UI/app_colors.dart';
import '../../UI/app_sound.dart';
import '../../backend_data/service/hive/hive_service.dart';
import '../../l10n/app_localizations.dart';
import '../../auth/login/auth_service.dart';
import '../../backend_data/service/analytics/analytics_service.dart';
import '../../backend_data/service/firestore/current_church_service.dart';
import '../../utils/share_app.dart';
import '../SundaySchool_app/assignment/assignment_home_admin.dart';
import '../SundaySchool_app/assignment/assignment_home_user.dart';
import '../church/church_admin_tools_screen.dart';
import '../helpers/color_palette_page.dart';
import 'user_feedback.dart';
import 'user_leaderboard.dart';
import 'user_saved_items.dart';
import 'user_settings.dart';
import 'user_streak.dart';

class UserProfileScreen extends StatelessWidget {
  const UserProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final loc = AppLocalizations.of(context);

    // Fallback to Firebase if cache missing (and user is logged in)
    String? photoUrl;
    String displayName = loc?.guestUser ?? "Guest User";
    String email = loc?.guestMode ?? "Guest Mode";

    if (user != null) {
      final uid = user.uid;

      // Read user-specific cached values
      photoUrl = HiveBoxes.userBox.get(UserCacheKeys.photo(uid)) as String?;
      displayName = HiveBoxes.userBox.get(UserCacheKeys.displayName(uid)) as String? 
          ?? user.displayName 
          ?? displayName;

      email = HiveBoxes.userBox.get(UserCacheKeys.email(uid)) as String? 
          ?? user.email 
          ?? email;
      
      final cachedUid = HiveBoxes.userBox.get(UserCacheKeys.uidCheck(uid)) as String?;
      if (cachedUid != uid) {
        debugPrint("Profile cache mismatch for uid $uid — falling back");
        photoUrl = null;
        displayName = user.displayName ?? displayName;
        email = user.email ?? email;
      }
    }

    String _getFriendlyEmailDisplay(User? user, String cachedEmail) {
      if (user?.isAnonymous == true) {
        return "Guest Mode";  // or "Anonymous" as you have
      }

      final String? currentEmail = user?.email ?? cachedEmail;

      if (currentEmail == null || currentEmail.isEmpty) {
        return "No email linked";
      }

      // Detect Apple's private relay email
      if (currentEmail.toLowerCase().contains('@privaterelay.appleid.com')) {
        return "Signed in with Apple ID";  // ← clean & Gmail-like (no ugly address)
      }

      // For Google, email/password, etc. → show real email
      return currentEmail;
    }

    // Use CachedNetworkImage instead of plain NetworkImage
    Widget profileImage;
    if (photoUrl != null && photoUrl.isNotEmpty) {
      profileImage = CachedNetworkImage(
        imageUrl: photoUrl,
        imageBuilder: (context, imageProvider) => CircleAvatar(
          radius: 55.sp,
          backgroundImage: imageProvider,
        ),
        placeholder: (context, url) => CircleAvatar(
          radius: 55.sp,
          backgroundColor: AppColors.secondaryContainer,
          child: const CircularProgressIndicator(),
        ),
        errorWidget: (context, url, error) => CircleAvatar(
          radius: 55.sp,
          backgroundColor: AppColors.secondaryContainer,
          backgroundImage: const AssetImage('assets/images/anonymous_user.png'),
        ),
        fit: BoxFit.cover,
      );
    } else {
      profileImage = CircleAvatar(
        radius: 55.sp,
        backgroundColor: AppColors.secondaryContainer,
        backgroundImage: const AssetImage('assets/images/anonymous_user.png'),
      );
    }

    final auth = context.read<AuthService>();
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppAppBar(
        title: AppLocalizations.of(context)?.navAccount ?? "Profile",
        showBack: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () async {
              await AnalyticsService.logButtonClick('settings');
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              );
            },
            enableFeedback: AppSounds.soundEnabled,
          ),
          SizedBox(width: 8.sp),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(0),
          // Optional subtle inner glow in dark mode
        ),
        child: Column(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(20.sp, 10.sp, 20.sp, 10.sp),
              child: Column(
                children: [
                    // Profile Photo
                    Center(
                      child: Stack(
                        children: [
                          profileImage,
                        ],
                      ),
                    ),
                    SizedBox(height: 10.sp),
                    // Name
                    Text(
                      //displayName,
                      user?.isAnonymous == true ? "Anonymous" : displayName,
                      style: TextStyle(
                        fontSize: 20.sp,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onBackground,
                      ),
                    ),
                    SizedBox(height: 3.sp),
                    // Email / Mode
                    Text(
                      //email,
                      _getFriendlyEmailDisplay(user, email),
                      style: TextStyle(
                        fontSize: 12.sp,
                        color: colorScheme.onBackground,
                      ),
                    ),
                ],
              ), 
            ),
            Divider(
              thickness: 0.8.sp,
              height: 10.sp,
              indent: 16.sp,
              endIndent: 16.sp,
              color: AppColors.grey600.withOpacity(0.6),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.only(bottom: 0),
                  child: Column(
                    children: [  
                      const CurrentChurchCard(),
                      if (user?.isAnonymous != true) ...[
                        Divider(
                          thickness: 0.8.sp,
                          height: 10.sp,
                          indent: 16.sp,
                          endIndent: 16.sp,
                          color: AppColors.grey600.withOpacity(0.6),
                        ),
                      ], 
                      SizedBox(height: 10.sp),      
                      // NEW: 2x2 Button Grid (2 rows, 2 buttons each)
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 16.sp),
                        child: GridView.count(
                          crossAxisCount: 2,
                          crossAxisSpacing: 10.sp,
                          mainAxisSpacing: 10.sp,
                          childAspectRatio: 4,
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          children: [
                            // Item 1: Bookmarks
                            _profileGridButton(
                              context: context,
                              icon: Icons.bookmark_border,
                              title: AppLocalizations.of(context)?.bookmarks ?? "Bookmarks",
                              onPressed: () async {
                                await AnalyticsService.logButtonClick('profile_bookmarks');
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(builder: (_) => const SavedItemsPage()),
                                );
                              },
                            ),
              
                            // Item 2: Streaks
                            _profileGridButton(
                              context: context,
                              icon: Icons.local_fire_department,
                              title: AppLocalizations.of(context)?.streaks ?? "Streaks",
                              onPressed: () async {
                                await AnalyticsService.logButtonClick('profile_streaks');
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(builder: (_) => const StreakPage()),
                                );
                              },
                            ),
                            /*if (auth.isGlobalAdmin || user!.isAnonymous)
                              _profileGridButton(
                                context: context,
                                icon: Icons.admin_panel_settings,
                                title: "Admin Board",
                                onPressed: () async {
                                  await AnalyticsService.logButtonClick('admin_tools_open');
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(builder: (_) => const AdminDashboardScreen()),
                                    //MaterialPageRoute(builder: (_) => const AdminToolsScreen()),
                                  );
                                },
                              ),*/
              
                            // Conditional items (only if not anonymous)
                            if (user?.isAnonymous != true) ...[
                              // Item 3: Leaderboard
                              _profileGridButton(
                                context: context,
                                icon: Icons.leaderboard,
                                title: AppLocalizations.of(context)?.leaderboard ?? "Leaderboard",
                                onPressed: () async {
                                  await AnalyticsService.logButtonClick('profile_leaderboard');
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(builder: (_) => const LeaderboardPage()),
                                  );
                                },
                              ),
              
                              // Item 4: Assignments / Teachers (with Consumer)
                              Consumer<AuthService>(
                                builder: (context, auth, child) {
                                  final bool isAdmin = auth.isGlobalAdmin || auth.isGroupAdminFor("Sunday School");
              
                                  return _profileGridButton(
                                    context: context,
                                    icon: isAdmin ? Icons.grading : Icons.assignment,
                                    title: isAdmin ? (AppLocalizations.of(context)?.teachers ?? "Teachers") : (AppLocalizations.of(context)?.assignments ?? "Assignments"),
                                    onPressed: () async {
                                      if (isAdmin) {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(builder: (_) => AdminResponsesGradingPage()),
                                        );
                                      } else {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(builder: (_) => const UserAssignmentsPage()),
                                        );
                                      }
                                    },
                                  );
                                },
                              ),
                            ],
                          ],
                        ),
                      ),
              
                      Divider(
                        thickness: 0.8,
                        height: 20.sp,
                        indent: 20.sp,
                        endIndent: 20.sp,
                        color: Colors.grey.shade400.withOpacity(0.6),
                      ),
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 16.sp),
                        child: GridView.count(
                          crossAxisCount: 1,
                          crossAxisSpacing: 0.sp,                 
                          mainAxisSpacing: 10.sp,                 
                          childAspectRatio: 8.5,                  
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          children: [
                            _profileGridButton(
                              context: context,
                              icon: Icons.feedback_outlined,
                              title: AppLocalizations.of(context)?.appSuggestions ?? "App Suggestions ...",
                              isWide: (auth.isGlobalAdmin || auth.isChurchAdmin ) == true ? false : true,
                              onPressed: () async {
                                await AnalyticsService.logButtonClick('profile_feedback');
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(builder: (_) => const FeedbackScreen()),
                                );
                              },
                            ),              
                            if (auth.isGlobalAdmin || auth.isChurchAdmin )
                              _profileGridButton(
                                context: context,
                                icon: Icons.admin_panel_settings,
                                isWide: true,
                                title: AppLocalizations.of(context)?.adminTools ?? "Admin Tools",
                                onPressed: () async {
                                  await AnalyticsService.logButtonClick('admin_tools_open');
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(builder: (_) => const AdminToolsScreen()),
                                  );
                                },
                              ),
                            // Admin-only full-width Color Palette button (spans both columns)
                            if (auth.isGlobalAdmin)
                              _profileGridButton(
                                context: context,
                                icon: Icons.palette,
                                isWide: true,
                                title: AppLocalizations.of(context)?.colorPalette ?? "Color Palette",
                                onPressed: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(builder: (_) => const ColorPalettePage()),
                                  );
                                },
                              ),
                          ],
                        ),
                      ),
                      Divider(
                        thickness: 0.8,
                        height: 20.sp,
                        indent: 20.sp,
                        endIndent: 20.sp,
                        color: Colors.grey.shade400.withOpacity(0.6),
                      ),
                      // Bottom row: Share + Sign Out
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 24.sp),
                        child: Column(
                          children: [
                            //if (auth.isGlobalAdmin)
                              // Invite Friends (Share)
                            LoginButtons(
                              context: context,
                              topColor: AppColors.primaryContainer,
                              onPressed: () async {
                                await AnalyticsService.logButtonClick('Share_invite_friends');

                                await shareApp(context);
                              },
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.share, color: AppColors.onPrimary, size: 22.sp),
                                  SizedBox(width: 10.sp),
                                  Text(
                                    AppLocalizations.of(context)?.inviteYourFriends ?? "Invite Your Friends",
                                    style: TextStyle(
                                      color: AppColors.onPrimary,
                                      fontSize: 15.sp,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                              text: '',
                            ),
                            SizedBox(height: 10.sp),
                            // Sign Out
                            LoginButtons(
                              context: context,
                              topColor: AppColors.grey800,
                              borderColor: Colors.transparent,
                              backOffset: 4.0,
                              backDarken: 0.5,
                              onPressed: () async {
                                await auth.signOutAndGoToLogin(context);
                              },
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.logout, color: AppColors.surface, size: 22.sp),
                                  SizedBox(width: 10.sp),
                                  Text(
                                    AppLocalizations.of(context)?.signOut ?? "Sign Out",
                                    style: TextStyle(
                                      color: AppColors.surface,
                                      fontSize: 15.sp,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                              text: '',
                            ),
                          ],
                        ),
                      ),
                      SizedBox(height: 40.sp),
                    ],
                  ),
              
              ),
            ),
          ],
        ),
      ),
    );
  }


  // Reusable grid button widget (matches your style)
  Widget _profileGridButton({
    required BuildContext context,
    required IconData icon,
    required String title,
    bool? isWide,
    required VoidCallback onPressed,
  }) {
    final theme = Theme.of(context);

    return PressInButtons(
      context: context,
      text: title,
      icon: icon,
      isWide: isWide,
      onPressed: onPressed,
      textColor: theme.colorScheme.surface,
      topColor: theme.colorScheme.onSurface,
      borderColor: const Color.fromARGB(0, 255, 255, 255),
    );
  }
}
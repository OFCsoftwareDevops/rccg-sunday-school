// NEW: Main screen with bottom navigation bar + banner ad (fixed layout)
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:provider/provider.dart';
import '../../UI/app_sound.dart';
import '../../auth/login/auth_service.dart';
import '../../auth/login/login_page.dart';
import '../../backend_data/service/ads/banner_ads.dart';
import '../../backend_data/service/analytics/analytics_service.dart';
import '../../l10n/app_localizations.dart';
import '../bible_app/bible_entry_point.dart';
import '../church/church_selection.dart';
import '../home.dart';
import '../profile/user_page.dart';


// ===================================================================
// Global Navigator Keys – created once for the entire app lifetime
// This prevents "Duplicate GlobalKeys" errors when MainScreen is replaced/recreated
// ===================================================================
final GlobalKey<NavigatorState> _homeNavigatorKey = GlobalKey<NavigatorState>();
final GlobalKey<NavigatorState> _bibleNavigatorKey = GlobalKey<NavigatorState>();
final GlobalKey<NavigatorState> _profileNavigatorKey = GlobalKey<NavigatorState>();

class MainScreen extends StatefulWidget {
  final int initialTab;
  const MainScreen({super.key, this.initialTab = 0});

  @override
  State<MainScreen> createState() => MainScreenState();
}

class MainScreenState extends State<MainScreen> {
  late int selectedIndex;

  // One navigator key per tab to preserve state
  late final List<GlobalKey<NavigatorState>> _navigatorKeys;

  @override
  void initState() {
    super.initState();
    selectedIndex = widget.initialTab;

    _navigatorKeys = [
      _homeNavigatorKey,
      _bibleNavigatorKey,
      _profileNavigatorKey,
    ];
  }

  // Pop to root of a specific tab
  void _popToRoot(int index) {
    if (selectedIndex != index) {
      setState(() => selectedIndex = index);
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _navigatorKeys[index]
          .currentState
          ?.popUntil((route) => route.isFirst);
    });
  }

  // Resume last Bible position when switching to Bible tab
  Future<void> _resumeBiblePosition() async {
    final bibleContext = _bibleNavigatorKey.currentContext;
    if (bibleContext != null && bibleContext.mounted) {  // ← Add mounted check
      final bibleState = bibleContext.findAncestorStateOfType<BibleEntryPointState>();
      await bibleState?.resumeLastPosition();
    }
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        final currentNavigator = _navigatorKeys[selectedIndex].currentState;

        if (currentNavigator?.canPop() ?? false) {
          currentNavigator!.pop();
          return false;
        }

        if (selectedIndex != 0) {
          setState(() => selectedIndex = 0);
          return false;
        }
        return true;
      },
      child: Consumer<AuthService>(
        builder: (context, auth, child) {
          if (auth.isLoading) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }

          final user = FirebaseAuth.instance.currentUser;
          // Not logged in → go to login
          if (user == null) {
            return const AuthScreen();
          }
          // Logged in but no church selected (and not guest) → onboarding
          if (!auth.hasChurch && !user.isAnonymous) {
            return const ChurchOnboardingScreen();
          }

          // Main layout with banner ad above bottom nav
          return Scaffold(
            body: SafeArea(
              top: true,
              bottom: false, // Let bottom content go under the nav bar + ad
              child: Column(
                children: [
                  // Main tab content (preserves navigation stack per tab)
                  Expanded(
                    child: KeyedSubtree(
                      key: ValueKey(selectedIndex),
                      child: IndexedStack(
                        index: selectedIndex,
                        children: [
                          Navigator(
                            key: _homeNavigatorKey,
                            onGenerateRoute: (_) => MaterialPageRoute(builder: (_) => const Home()),
                          ),
                          Navigator(
                            key: _bibleNavigatorKey,
                            onGenerateRoute: (_) => MaterialPageRoute(builder: (_) => const BibleEntryPoint()),
                          ),
                          Navigator(
                            key: _profileNavigatorKey,
                            onGenerateRoute: (_) => MaterialPageRoute(builder: (_) => const UserProfileScreen()),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // Banner ad (hidden when premium)
                  const BannerAdWidget(),
                ],
              ),
            ),            
            // Bottom Navigation Bar
            bottomNavigationBar: _buildBottomNavBar(context),
          );
        },
      ),
    );
  }

  Widget _buildBottomNavBar(BuildContext context) {
    final loc = AppLocalizations.of(context);
    
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.5),
            blurRadius: 0.5,
            offset: const Offset(0, 0),
          ),
        ],
      ),
      child: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        currentIndex: selectedIndex,
        selectedItemColor: Theme.of(context).colorScheme.primaryContainer,
        unselectedItemColor: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
        selectedFontSize: 12.sp,
        unselectedFontSize: 10.sp,
        iconSize: 25.sp,
        selectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600),
        unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500),
        backgroundColor: Theme.of(context).colorScheme.surface,
        elevation: 0,
        onTap: (index) async {
          if (index != selectedIndex) {
            setState(() => selectedIndex = index);
          }
          // Analytics
          switch (index) {
            case 0: 
              await AnalyticsService.logButtonClick('home_tab'); 
              break;
            case 1: 
              await AnalyticsService.logButtonClick('bible_tab');
              await _resumeBiblePosition();
              break;
            case 2: 
              await AnalyticsService.logButtonClick('profile_tab'); 
              break;
          }
        },
        enableFeedback: AppSounds.soundEnabled,
        items: [
          _navItem(
            context: context,
            icon: Icons.home,
            label: loc?.navHome ?? "Home",
            index: 0,
            analyticsKey: 'home_tab',
          ),
          _navItem(
            context: context,
            icon: Icons.book,
            label: loc?.navBible ?? "Bible",
            index: 1,
            analyticsKey: 'bible_tab',
          ),
          _navItem(
            context: context,
            icon: Icons.verified_user,
            label: loc?.navAccount ?? "Account",
            index: 2,
            analyticsKey: 'profile_tab',
          ),
        ],
      ),
    );
  }

  BottomNavigationBarItem _navItem({
    required BuildContext context,
    required IconData icon,
    required String label,
    required int index,
    required String analyticsKey,
  }) {
    return BottomNavigationBarItem(
      label: label,
      icon: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onLongPress: () {
          HapticFeedback.mediumImpact();
          AnalyticsService.logButtonClick('${analyticsKey}_long_press_reset');
          _popToRoot(index);
        },
        child: SizedBox(
          width: double.infinity,
          child: Icon(icon),
        ),
      ),
    );
  }
}

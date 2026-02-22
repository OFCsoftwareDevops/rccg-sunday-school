// lib/widgets/intro_page.dart
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../UI/app_colors.dart';
import '../../UI/app_timed_button.dart';
//import '../../backend_data/service/shorebird/shorebird_push.dart';
import '../../l10n/app_localizations.dart';
import '../../utils/media_query.dart';

class IntroPage extends StatelessWidget {
  final VoidCallback? onFinish;
  final bool preloadDone;
  final bool isLoading;
  final int preloadProgress;
  final int totalPreloadSteps;

  const IntroPage({
    super.key, 
    required this.onFinish,
    required this.isLoading, 
    required this.preloadDone, 
    required this.preloadProgress,
    required this.totalPreloadSteps,
  });

  @override
  Widget build(BuildContext context) {
    final double scale = introScale(context);
    
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.background,
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.all(32.sp * scale),
          child: Column(
            children: [
              const Spacer(),
              // LOGO — scaled dynamically
              Center(
                child: Container(
                  padding: const EdgeInsets.all(0),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 3.sp),
                    color: Colors.white.withOpacity(0.2),
                  ),
                  child: ClipOval(
                    //child: Icon(Icons.church, size: 120.sp, color: Colors.white),
                    child: Image.asset(
                      'assets/images/rccg_logo.png',
                      height: 120.sp,
                      width: 120.sp,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => Icon(Icons.church, size: 70.sp * scale, color: Colors.white),
                    ),
                  ),
                ),
              ),
              SizedBox(height: 40.sp),
              Text(
                AppLocalizations.of(context)?.sundaySchoolManual ?? "Sunday School Manual",
                style: Theme.of(context).textTheme.headlineMedium!.copyWith(
                      fontWeight: FontWeight.bold,
                      fontSize: (Theme.of(context).textTheme.headlineMedium!.fontSize ?? 24.sp) * scale,
                    ),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 20.sp),
              Text(
                AppLocalizations.of(context)?.accessWeeklyLessonsOffline ?? "Access your weekly Teen and Adult Bible study lessons anytime, anywhere — even offline!",
                style: Theme.of(context).textTheme.bodyLarge!.copyWith(
                  fontSize: (Theme.of(context).textTheme.bodyLarge!.fontSize ?? 16.sp) * (scale * 0.8),
                ),
                textAlign: TextAlign.center,
              ),
              Divider(
                thickness: 0.8.sp,
                height: 15.sp,
                indent: 50.sp * scale,
                endIndent: 50.sp * scale,
                color: AppColors.grey600.withOpacity(0.6),
              ),
              Text(
                AppLocalizations.of(context)?.builtForRccg ?? "Built for Redeemed Christian Church of God!",
                style: Theme.of(context).textTheme.bodySmall!.copyWith(
                  fontSize: (Theme.of(context).textTheme.bodySmall!.fontSize ?? 16.sp) * (scale * 0.8),
                ),
                textAlign: TextAlign.center,
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: PreloadProgressButton(
                  context: context,
                  text: AppLocalizations.of(context)?.getStarted ?? "Get Started",
                  preloadDone: preloadDone,
                  progress: preloadProgress,
                  totalSteps: totalPreloadSteps,
                  activeColor: Theme.of(context).colorScheme.onSurface,
                  onPressed: isLoading || !preloadDone
                    ? null  // Keep disabled if still loading/preloading
                    : () async {
                        // First, check for Shorebird patch
                        // await checkAndApplyShorebirdUpdate(context);

                        // Then run your original finish logic (navigate to home, etc.)
                        onFinish?.call();
                      },
                ),
              ),
              SizedBox(height: 30.sp),
            ],
          ),
        ),
      ),
    );
  }
}
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart'; // Add this
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:text_scroll/text_scroll.dart';
import '../../../l10n/app_localizations.dart';
import 'premium_provider.dart';

class BannerAdWidget extends ConsumerStatefulWidget {
  const BannerAdWidget({super.key});

  @override
  ConsumerState<BannerAdWidget> createState() => _BannerAdWidgetState();
}

class _BannerAdWidgetState extends ConsumerState<BannerAdWidget> {
  BannerAd? _bannerAd;
  bool _isLoaded = false;

  @override
  void dispose() {
    _disposeAd();
    super.dispose();
  }

  void _disposeAd() {
    _bannerAd?.dispose();
    _bannerAd = null;
    _isLoaded = false;
  }

  void _loadAd() {
    final adUnitId = Platform.isAndroid
        ? 'ca-app-pub-9863376634060421/6609219843' // Real ads ID
        : 'ca-app-pub-9863376634060421/3967401172'; // Real ads ID

    _bannerAd = BannerAd(
      adUnitId: adUnitId,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) {
          if (mounted) {
            setState(() => _isLoaded = true);
          }
        },
        onAdFailedToLoad: (ad, _) {
          ad.dispose();
          _disposeAd();
        },
      ),
    )..load();
  }

  @override
  Widget build(BuildContext context) {
    final asyncPremium = ref.watch(isPremiumProvider);

    return asyncPremium.when(
      data: (isPremium) {
        // Premium: no ads, ever
        if (isPremium) {
          if (_bannerAd != null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _disposeAd();
            });
          }
          return const SizedBox.shrink();
        }

        // Non-premium: ensure ad is loaded
        if (_bannerAd == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _bannerAd == null) {
              _loadAd();
            }
          });
        }
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: double.infinity,
              padding: EdgeInsets.symmetric(vertical: 2),
              color: Theme.of(context).colorScheme.onBackground,
              child: TextScroll(
                AppLocalizations.of(context)?.advertsDisclosure ??
                    "Adverts fund the app and server maintenance, for your pleasure.",
                velocity: Velocity(pixelsPerSecond: Offset(50, 0)), // similar to your speed: 50
                intervalSpaces: 80,         // ≈ your gap: 80
                mode: TextScrollMode.endless, // loops forever (default is .endless)
                delayBefore: const Duration(milliseconds: 500),   // optional: pause before starting
                pauseBetween: const Duration(milliseconds: 800),  // optional: pause after each cycle
                textAlign: TextAlign.center,               // you had it commented – now available
                style: TextStyle(
                  fontSize: 8.sp,
                  color: Theme.of(context).colorScheme.background.withOpacity(1),
                ),
              ),

            ),
            if (_isLoaded && _bannerAd != null)
              _adContainer(context)
            else
              _placeholder(context),
          ],
        );
      },
      loading: () => _placeholder(context),
      error: (_, __) => const SizedBox.shrink(),
    );
  }

  Widget _placeholder(BuildContext context) {
    return Container(
      height: 50,
      alignment: Alignment.center,
      color: Theme.of(context).colorScheme.surface.withOpacity(0.8),
      child: const _LoadingDots(),
    );
  }

  Widget _adContainer(BuildContext context) {
    return Container(
      height: 50,
      width: double.infinity,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          top: BorderSide(
            color: Theme.of(context)
                .colorScheme
                .onSurface
                .withOpacity(0.1),
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 2,
            offset: const Offset(0, -1),
          ),
        ],
      ),
      child: AdWidget(ad: _bannerAd!),
    );
  }
}

class _LoadingDots extends StatelessWidget {
  const _LoadingDots();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 20.sp,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _Dot(),
          _Dot(delay: 200),
          _Dot(delay: 400),
        ],
      ),
    );
  }
}

class _Dot extends StatefulWidget {
  final int delay;
  const _Dot({this.delay = 0});

  @override
  State<_Dot> createState() => _DotState();
}

class _DotState extends State<_Dot> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();

    Future.delayed(Duration(milliseconds: widget.delay), () {
      if (mounted) _controller.repeat();
    });

    _animation = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 4.sp),
      child: FadeTransition(
        opacity: _animation,
        child: Container(
          width: 8.sp,
          height: 8.sp,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primary,
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }
}
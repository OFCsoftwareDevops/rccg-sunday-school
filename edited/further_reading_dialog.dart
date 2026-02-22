// lib/widgets/further_reading_dialog.dart
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../UI/app_colors.dart';
import '../../../UI/app_sound.dart';
import '../../../auth/login/auth_service.dart';
import '../../../backend_data/service/analytics/analytics_service.dart';
import '../../../backend_data/service/firestore/saved_items_service.dart';
import '../../../backend_data/service/firestore/streak_service.dart';
import '../../../UI/app_linear_progress_bar.dart';
import '../../../UI/app_timed_button.dart';
import '../../../l10n/app_localizations.dart';
import '../../bible_app/bible.dart';
import '../../bible_app/bible_actions/highlight_manager.dart';
import '../../helpers/main_screen.dart';
import '../../helpers/snackbar.dart';
import '../../bible_app/bible_ref_verse_popup.dart';


/// Opens the Further Reading as a centered dialog (not bottom sheet)
void showFurtherReadingDialog({
  required BuildContext context,
  required String todayReading, // e.g. "Esther 4:16 (KJV)" or "Luke 4:5."
}) {
  final bool hasReading = todayReading.trim().isNotEmpty;
  if (!hasReading) return;

  // Show loading first
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => const Center(child: LinearProgressBar()),
  );

  // Clean the reference
  final String ref = todayReading
      .replaceAll(RegExp(r'\s*\(KJV\)\.?$'), '')
      .replaceAll(RegExp(r'\.+$'), '')
      .trim();

  // Fetch the verse exactly like your other working places
  final manager = context.read<BibleVersionManager>();
  final raw = manager.getVerseText(ref) ?? "Verse temporarily unavailable";

  final lines = raw
    .split('\n')
    .map((l) => l.trim())
    .where((l) => l.isNotEmpty)
    .toList();

  final highlightMgr = context.read<HighlightManager>();
  final bookKey = ref.split(' ').first.toLowerCase().replaceAll(' ', '');
  final chapter = int.tryParse(RegExp(r'\d+').firstMatch(ref)?.group(0) ?? '1') ?? 1;

  final List<Map<String, dynamic>> verses = [];

  for (final line in lines) {
    final parts = line.split(RegExp(r'\s+'));
    final verseNum = int.tryParse(parts.first);
    if (verseNum == null || verseNum == 0) continue;

    final verseText = parts.skip(1).join(' ');
    final highlighted = highlightMgr.isHighlighted(bookKey, chapter, verseNum);

    verses.add({
      'verse': verseNum,
      'text': verseText,
      'highlighted': highlighted,
    });
  }

  // Close loading
  if (Navigator.canPop(context)) Navigator.pop(context);

  // TIMER CALCULATED BASED ON TEXT
  final wordCount = raw.split(RegExp(r'\s+')).length;
  int readingSeconds = (wordCount / 3).ceil(); // ~200 wpm
  readingSeconds = ((readingSeconds + 4) ~/ 5) * 5; // Round up to next multiple of 5
  if (readingSeconds < 10) readingSeconds = 10; // minimum 5s

  // Show the beautiful centered dialog
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (context) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20.sp)),
      backgroundColor: Theme.of(context).colorScheme.background,
      insetPadding: EdgeInsets.all(20.sp),
      contentPadding: EdgeInsets.zero,
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // The verse popup
            SizedBox(
              height: MediaQuery.of(context).size.height * 0.72,
              child: VersePopup(
                reference: ref,
                verses: verses,
                rawText: raw,
                heightFraction: 0.85.sp,
                showCloseButton: true,
              ),
            ),
          ],
        ),
      ),
      actions: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 16.sp, vertical: 8.sp),
          child: SizedBox(
            width: double.infinity, // full width in actions
              child: TimedFeedbackButtonStateful(
              text: AppLocalizations.of(context)?.completeReading ?? "Complete Reading",
              topColor: AppColors.success,
              seconds: readingSeconds, // time to wait before enabling
              onPressed: () async {
                await SoundService.playSuccess();

                await AnalyticsService.logButtonClick('further_reading_completed!');
                final user = FirebaseAuth.instance.currentUser;
                await StreakService().updateReadingStreak(user!.uid);

                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(builder: (_) => MainScreen()),
                ); // close the dialog
              },
              borderColor: AppColors.success,
              borderWidth: 2.sp,
              backOffset: 4.sp,
              backDarken: 0.45,
            ),
          ),
        ),
      ],
      actionsPadding: EdgeInsets.zero,
    ),
  );
}

// Smart Save Button — uses your existing isFurtherReadingSaved()
class SmartSaveReadingButton extends StatefulWidget {
  final String ref;
  final String todayReading;

  const SmartSaveReadingButton({
    required this.ref, 
    required this.todayReading,
  });

  @override
  State<SmartSaveReadingButton> createState() => SmartSaveReadingButtonState();
}

class SmartSaveReadingButtonState extends State<SmartSaveReadingButton> {
  bool _isSaved = false;
  bool _isChecking = true;

  @override
  void initState() {
    super.initState();
    _checkIfSaved();
  }

  Future<void> _checkIfSaved() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() => _isChecking = false);
      return;
    }

    final auth = context.read<AuthService>();
    if (auth.churchId == null) {
      setState(() => _isChecking = false);
      return;
    }

    final saved = await SavedItemsService().isFurtherReadingSaved(user.uid, widget.ref);

    if (mounted) {
      setState(() {
        _isSaved = saved;
        _isChecking = false;
      });
    }
  }

  Future<void> _toggleSave() async {
    final user = FirebaseAuth.instance.currentUser;
    final service = SavedItemsService();
    final userId = user?.uid;
    final isAnonymous = user?.isAnonymous;

    try {
      if (_isSaved) {
        // ── REMOVE ────────────────────────────────────────
        final current = service.getCachedItems(userId!, 'further_readings');
        final updated = current.where((item) => item['title'] != widget.ref).toList();
        await service.cacheItems(userId, 'further_readings', updated);

        if (isAnonymous!) {
          await service.removeFurtherReading(userId, widget.ref);
        }

        setState(() => _isSaved = false);
        showTopToast(context, 'Reading removed');
      } else {
        // ── ADD ───────────────────────────────────────────
        final now = DateTime.now().toUtc();

        final newItem = <String, dynamic>{
          'title': widget.ref,
          'reading': widget.todayReading,
          'savedAt': now.toIso8601String(),
        };

        if (isAnonymous!) {
          // Anonymous: only local cache + fake ID
          final fakeId = 'local_${now.millisecondsSinceEpoch}';
          newItem['id'] = fakeId;

          final current = service.getCachedItems(userId!, 'further_readings');
          final updated = [newItem, ...current];
          await service.cacheItems(userId, 'further_readings', updated);
        } else {
          // Real user: Firestore + cache
          final docRef = await service.addFurtherReading(
            userId,
            title: widget.ref,
            reading: widget.todayReading,
          );

          newItem['id'] = docRef;

          final current = service.getCachedItems(userId!, 'further_readings');
          final updated = [newItem, ...current];
          await service.cacheItems(userId, 'further_readings', updated);
        }

        setState(() => _isSaved = true);
        showTopToast(
          context, 
          'Reading saved! 📖',
        );
      }
    } catch (e, stack) {
      debugPrint("Toggle save failed: $e\n$stack");
      showTopToast(context, 'Operation failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return IconButton(
      tooltip: _isSaved ? 'Remove from saved readings' : 'Save this reading',
      onPressed: _isChecking ? null : _toggleSave,
      enableFeedback: AppSounds.soundEnabled,
      icon: _isChecking
        ? SizedBox(
          width: 24.sp,
          height: 24.sp,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: Color.fromARGB(255, 100, 13, 74),
          ),
        )
      : Icon(
          _isSaved ? Icons.bookmark : Icons.bookmark_add,
          color: _isSaved ? AppColors.success : theme.colorScheme.onBackground,
        ),
    );
  }
}
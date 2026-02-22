
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:provider/provider.dart';
import '../../../UI/app_bar.dart';
import '../../../UI/app_colors.dart';
import '../../../UI/app_segment_sliding.dart';
import '../../../UI/app_sound.dart';
import '../../../auth/login/auth_service.dart';
import '../../../backend_data/database/constants.dart';
import '../../../backend_data/service/firestore/assignment_dates_provider.dart';
import '../../../backend_data/service/firestore/firestore_service.dart';
import '../../../utils/media_query.dart';
import '../../../l10n/app_localizations.dart';
import '../../helpers/snackbar.dart';
import 'assignment_response_page_admin.dart';


class AdminResponsesGradingPage extends StatefulWidget {
  const AdminResponsesGradingPage({super.key});

  @override
  State<AdminResponsesGradingPage> createState() => _AdminResponsesGradingPageState();
}

class _AdminResponsesGradingPageState extends State<AdminResponsesGradingPage> {
  int _selectedAgeGroup = 0; // 0 = Adult, 1 = Teen
  // Add a getter instead
  bool get _isTeen => _selectedAgeGroup == 1;

  int _selectedQuarter = 0;

  // Cache for submission info to avoid repeated queries
  StreamSubscription<QuerySnapshot>? _summarySubscription;
  final Map<String, Map<String, int>> _liveData = {}; // live values override cache
  final Map<String, Map<String, int>> _submissionCache = {};

  List<String> _ageGroups = ["Adult", "Teen"];

  String _formatDateId(DateTime date) =>
    "${date.year}-${date.month.toString().padLeft(2,'0')}-${date.day.toString().padLeft(2,'0')}";


  @override
  void initState() {
    super.initState();

    final now = DateTime.now();
    final currentMonth = now.month;

    if (currentMonth == 12 || currentMonth <= 2) {
      _selectedQuarter = 0; // Q1
    } else if (currentMonth <= 5) {
      _selectedQuarter = 1; // Q2
    } else if (currentMonth <= 8) {
      _selectedQuarter = 2; // Q3
    } else {
      _selectedQuarter = 3; // Q4
    }

    // Initialize localized age groups after frame is built
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _ageGroups = [
          AppLocalizations.of(context)?.adult ?? "Adult",
          AppLocalizations.of(context)?.teen ?? "Teen",
        ];
      });
      _listenToQuarterSummaries();
    });
  }

  @override
  void didUpdateWidget(covariant AdminResponsesGradingPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Re-subscribe if quarter or teen/adult changed
    _listenToQuarterSummaries();
  }

  @override
  void dispose() {
    _summarySubscription?.cancel();
    super.dispose();
  }

  void _listenToQuarterSummaries() {
    _summarySubscription?.cancel();

    final auth = context.read<AuthService>();
    if (auth.churchId == null) return;

    final service = FirestoreService(churchId: auth.churchId);
    final type = _isTeen ? "teen" : "adult";

    // Get all expected summary doc IDs for current quarter
    final quarterMonths = AppConstants.quarterMonths[_selectedQuarter];
    final now = DateTime.now();
    final year = now.year; // simplify (handle cross-year if needed later)

    final sundayIds = <String>[];
    final allDates = Provider.of<AssignmentDatesProvider>(context, listen: false).dates;

    for (final month in quarterMonths) {
      final sundays = allDates
          .where((d) => d.year == year && d.month == month && d.weekday == DateTime.sunday)
          .toList();

      for (final sunday in sundays) {
        final dateStr = _formatDateId(sunday);
        sundayIds.add('${type}_$dateStr');
      }
    }

    if (sundayIds.isEmpty) return;

    // Listen to summaries where document ID is in the quarter's list
    final query = service.submissionSummariesCollection.where(
      FieldPath.documentId,
      whereIn: sundayIds.length <= 30 ? sundayIds : sundayIds.sublist(0, 30), // Firestore whereIn limit = 30
    );

    _summarySubscription = query.snapshots().listen((snapshot) {
      if (!mounted) return;

      final updated = <String, Map<String, int>>{};

      for (final change in snapshot.docChanges) {
        final doc = change.doc;
        final data = doc.data() as Map<String, dynamic>? ?? {};
        final total = (data['totalSubmissions'] as int?) ?? 0;
        final graded = (data['gradedCount'] as int?) ?? 0;

        updated[doc.id] = {'total': total, 'graded': graded};
      }

      setState(() {
        _liveData.addAll(updated);
        // Optional: clear old cache entries not in new data
        _submissionCache.removeWhere((key, _) => !updated.containsKey(key.split('_').last));
      });

      // ── ADD THE CHECK HERE ────────────────────────────────────────
      if (snapshot.metadata.hasPendingWrites == false && mounted) { // only remote changes
        // Optional: show "Updated from grading" toast
        if (mounted) {
          showTopToast(
            context,
            "Grading updates received — view refreshed",
            duration: const Duration(seconds: 2),
          );
        }
      }
    }, onError: (e) {
      debugPrint("Summary listener error: $e");
    });
  }

  Future<Map<String,int>> _getSubmissionInfo(DateTime date, String type) async {
    final cacheKey = "${_formatDateId(date)}_$type";

    // 1. Use real-time listener data if available (instant)
    if (_liveData.containsKey(cacheKey)) {
      return _liveData[cacheKey]!;
    }

    // 2. Fall back to existing cache
    if (_submissionCache.containsKey(cacheKey)) {
      return _submissionCache[cacheKey]!;
    }

    final service = FirestoreService(churchId: context.read<AuthService>().churchId);
    final total = await service.getSubmissionCount(date: date, type: type);
    final graded = await service.getGradedCount(date: date, type: type);

    _submissionCache[cacheKey] = {"total": total, "graded": graded};
    return _submissionCache[cacheKey]!;
  }


  @override
  Widget build(BuildContext context) {
    final datesProvider = Provider.of<AssignmentDatesProvider>(context, listen: false);
    final auth = context.read<AuthService>();
    final parishName = auth.parishName ?? "Global";
    final style = CalendarDayStyle.fromContainer(context, 50);

    if (datesProvider.isLoading) {
      return Scaffold(
        appBar: AppAppBar(
          title: "${AppLocalizations.of(context)?.adminTools ?? 'Admin'} — $parishName",
          showBack: true,
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              iconSize: style.monthFontSize.sp,
              tooltip: AppLocalizations.of(context)?.refreshAssignments ?? "Refresh assignments",
              enableFeedback: AppSounds.soundEnabled,
              onPressed: () {
                final service = FirestoreService(churchId: auth.churchId);
                datesProvider.refresh(context, service);
                _submissionCache.clear();
                setState(() {});
              },
            ),
          ],
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppAppBar(
        title: "${AppLocalizations.of(context)?.adminTools ?? 'Admin'} — $parishName",
        showBack: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            iconSize: style.monthFontSize.sp, // Same size as in Bible app bar
            tooltip: AppLocalizations.of(context)?.refreshAssignments ?? "Refresh assignments",
            enableFeedback: AppSounds.soundEnabled,
            onPressed: () {
              final service = FirestoreService(churchId: auth.churchId);
              datesProvider.refresh(context, service);
              _submissionCache.clear();
              setState(() {});
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.sp),
            child: segmentedControl(
              selectedIndex: _selectedAgeGroup,
              items: _ageGroups.map((e) => SegmentItem(e)).toList(),
              //onChanged: (i) => setState(() => _selectedAgeGroup = i),
              onChanged: (i) {
                setState(() {
                  _selectedAgeGroup = i;
                });
                _listenToQuarterSummaries(); // refresh listener
              },
            ),
          ),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.sp, vertical: 8.sp),
            child: segmentedControl(
              selectedIndex: _selectedQuarter,
              items: AppConstants.quarterLabels.map((l) => SegmentItem(l)).toList(),
              //onChanged: (i) => setState(() => _selectedQuarter = i),
              onChanged: (i) {
                setState(() {
                  _selectedQuarter = i;
                });
                _listenToQuarterSummaries(); // refresh listener
              },
            ),
          ),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              key: ValueKey('$_selectedQuarter-$_isTeen'),
              child: _buildQuarterContent(_selectedQuarter, datesProvider.dates),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuarterContent(int quarterIndex, Set<DateTime> allDates) {
    final months = AppConstants.quarterMonths[quarterIndex];
    final List<Widget> monthWidgets = [];

    for (final month in months) {
      final sundays = _getAllSundaysInMonth(month, allDates);
      if (sundays.isEmpty) continue;

      final Map<int, List<DateTime>> byYear = {};
      for (final s in sundays) {
        byYear.putIfAbsent(s.year, () => []).add(s);
      }

      final sortedYears = byYear.keys.toList()..sort();

      for (final year in sortedYears) {
        final yearSundays = byYear[year]!..sort();

        monthWidgets.add(
          Padding(
            padding: EdgeInsets.symmetric(vertical: 12.sp),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "${_getMonthName(month, context)} $year",
                  style: TextStyle(fontSize: 18.sp, 
                    fontWeight: FontWeight.bold, 
                    color: Theme.of(context).colorScheme.secondary,
                  ),
                ),
                SizedBox(height: 12.sp),
                Wrap(
                  spacing: 12.sp,
                  runSpacing: 12.sp,
                  children: yearSundays.map((sunday) {
                    final type = _isTeen ? "teen" : "adult";

                    return FutureBuilder<Map<String, int>>(
                      future: _getSubmissionInfo(sunday, type),
                      builder: (context, snapshot) {
                        if (!snapshot.hasData) {
                          return SizedBox(
                            width: 100.sp, 
                            height: 140.sp,
                            child: Center(child: CircularProgressIndicator()),
                          );
                        }

                        final total = snapshot.data!['total'] ?? 0;
                        final graded = snapshot.data!['graded'] ?? 0;

                        final label = total == 0 ? (AppLocalizations.of(context)?.empty ?? "Empty!") : "$graded / $total \n ${AppLocalizations.of(context)?.graded ?? 'Graded'}";

                        final bool hasSubmissions = total > 0;
                        final bool isFullyGraded = hasSubmissions && graded == total;

                        final Color cardColor = isFullyGraded
                            ? Colors.green.shade100          // fully graded → nice green background
                            : hasSubmissions
                                ? const Color.fromARGB(255, 218, 194, 140)     // has submissions but not fully graded → amber
                                : AppColors.grey200;         // no submissions → grey

                        final Color textAndIconColor = isFullyGraded
                            ? Colors.green.shade800
                            : hasSubmissions
                                ? const Color.fromARGB(255, 69, 46, 15)      // amber text/icon for partial grading
                                : Colors.grey.shade700;

                        final IconData icon = isFullyGraded
                            ? Icons.check_circle
                            : hasSubmissions
                                ? Icons.hourglass_bottom     // or Icons.warning_amber — indicates "in progress"
                                : Icons.pending;

                        return Material(
                          color: cardColor,
                          borderRadius: BorderRadius.circular(16.sp),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(16.sp),
                            onTap: !hasSubmissions ? null : () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => AssignmentResponseDetailPage(
                                    date: sunday,
                                    isTeen: _isTeen,
                                  ),
                                ),
                              );
                            },
                            enableFeedback: AppSounds.soundEnabled,
                            child: SizedBox(
                              width: 100.sp,
                              height: 140.sp,
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Text(
                                    "${sunday.day}",
                                    style: TextStyle(
                                      fontSize: 28.sp,
                                      fontWeight: FontWeight.bold,
                                      color: textAndIconColor,
                                    ),
                                  ),
                                  SizedBox(height: 5.sp),
                                  Icon(
                                    icon,
                                    size: 20.sp,
                                    color: textAndIconColor,
                                  ),
                                  SizedBox(height: 5.sp),
                                  Text(
                                    label,
                                    style: TextStyle(
                                      fontSize: 11.sp,
                                      color: textAndIconColor,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );

                        /*return Material(
                          color: total > 0 ? AppColors.divineAccent : AppColors.grey200,
                          borderRadius: BorderRadius.circular(16.sp),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(16.sp),
                            onTap: total == 0 ? null : () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => AssignmentResponseDetailPage(
                                    date: sunday,
                                    isTeen: _isTeen,
                                  ),
                                ),
                              );
                            },
                            enableFeedback: AppSounds.soundEnabled,
                            child: SizedBox(
                              width: 100.sp,
                              height: 140.sp,
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Text(
                                    "${sunday.day}",
                                    style: TextStyle(
                                      fontSize: 28.sp,
                                      fontWeight: FontWeight.bold,
                                      color: total > 0 ? Colors.green.shade800 : Colors.grey.shade700,
                                    ),
                                  ),
                                  SizedBox(height: 5.sp),
                                  Icon(
                                    total > 0 ? Icons.check_circle : Icons.pending,
                                    size: 20.sp,
                                    color: total > 0 ? Colors.green.shade800 : Colors.grey.shade700,
                                  ),
                                  SizedBox(height: 5.sp),
                                  Text(
                                    label,
                                    style: TextStyle(
                                      fontSize: 11.sp,
                                      color: total > 0 ? Colors.green.shade800 : Colors.grey.shade700,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );*/
                      },
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
        );
      }
    }

    if (monthWidgets.isEmpty) {
      return Center(
        child: Text(
          AppLocalizations.of(context)?.noAssignmentsInQuarter ?? "No assignments in this quarter.",
          style: TextStyle(fontSize: 18.sp, color: Colors.grey),
        ),
      );
    }

    return ListView(
      padding: EdgeInsets.symmetric(horizontal: 16.sp),
      children: monthWidgets,
    );
  }

  List<DateTime> _getAllSundaysInMonth(int month, Set<DateTime> allDates) {
    return allDates
        .where((d) => d.month == month && d.weekday == DateTime.sunday)
        .toList()
      ..sort();
  }

  String _getMonthName(int m, BuildContext context) {
    final loc = AppLocalizations.of(context);
    return [
      loc?.january ?? 'January',
      loc?.february ?? 'February',
      loc?.march ?? 'March',
      loc?.april ?? 'April',
      loc?.may ?? 'May',
      loc?.june ?? 'June',
      loc?.july ?? 'July',
      loc?.august ?? 'August',
      loc?.september ?? 'September',
      loc?.october ?? 'October',
      loc?.november ?? 'November',
      loc?.december ?? 'December'
    ][m - 1];
  }
}
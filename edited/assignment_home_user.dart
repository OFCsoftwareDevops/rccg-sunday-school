// lib/screens/user_assignments_page.dart

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:provider/provider.dart';
import '../../../UI/app_bar.dart';
import '../../../UI/app_segment_sliding.dart';
import '../../../UI/app_sound.dart';
import '../../../auth/login/auth_service.dart';
import '../../../backend_data/database/constants.dart';
import '../../../backend_data/service/firestore/assignment_dates_provider.dart';
import '../../../backend_data/service/firestore/firestore_service.dart';
import '../../../backend_data/service/firestore/submitted_dates_provider.dart';
import '../../../l10n/app_localizations.dart';
import 'assignment_response_page_user.dart';


class UserAssignmentsPage extends StatefulWidget {
  const UserAssignmentsPage({super.key});

  @override
  State<UserAssignmentsPage> createState() => _UserAssignmentsPageState();
}

class _UserAssignmentsPageState extends State<UserAssignmentsPage> {
  int _selectedAgeGroup = 0; // 0 = Adult, 1 = Teen
  // Add a getter instead
  bool get _isTeen => _selectedAgeGroup == 1;
  int _selectedQuarter = 0;
  bool _ensuredSubmittedDatesLoaded = false;

  late final List<String> _ageGroups;

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

      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final auth = context.read<AuthService>();
      final service = FirestoreService(churchId: auth.churchId ?? '');

      // Load submitted dates (once on page open)
      final submittedProvider = Provider.of<SubmittedDatesProvider>(context, listen: false);
      submittedProvider.load(service, user.uid).catchError((e) {
        if (kDebugMode) {
          debugPrint('Error loading submitted dates on page open: $e');
        }
      });

      // Ensure assignment dates are loaded (if still loading)
      final datesProvider = Provider.of<AssignmentDatesProvider>(context, listen: false);
      if (datesProvider.isLoading || datesProvider.dates.isEmpty) {
        datesProvider.refresh(context, service);
      }

      // Initialize localized age groups
      setState(() {
        _ageGroups = [
          AppLocalizations.of(context)?.adult ?? "Adult",
          AppLocalizations.of(context)?.teen ?? "Teen",
        ];
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final datesProvider = Provider.of<AssignmentDatesProvider>(context);
    final submittedProvider = Provider.of<SubmittedDatesProvider>(context);
    final auth = context.read<AuthService>();
    final user = FirebaseAuth.instance.currentUser;
    final parishName = auth.parishName ?? "Your Church";

    if (!_ensuredSubmittedDatesLoaded && user != null) {
      _ensuredSubmittedDatesLoaded = true;

      // Use the same churchId from AuthService
      final service = FirestoreService(churchId: auth.churchId ?? '');

      submittedProvider.load(service, user.uid).catchError((e) {
        if (kDebugMode) {
          debugPrint('Error loading submitted dates on page open: $e');
        }
      });
    }

    // Show loading spinner only if critical data isn't ready yet
    if (datesProvider.isLoading || 
        (user != null && submittedProvider.isLoading && !_ensuredSubmittedDatesLoaded)) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    // If no user, show a friendly message (optional fallback)
    if (user == null) {
      return Scaffold(
        appBar: AppAppBar(
          title: AppLocalizations.of(context)?.myAssignments ?? "My Assignments",
          showBack: true,
        ),
        body: const Center(
          child: Text("Please log in to view your assignments."),
        ),
      );
    }

    // No loading state needed — data is preloaded!
    return Scaffold(
      appBar: AppAppBar(
        title: "${AppLocalizations.of(context)?.assignments ?? 'Assignments'} — $parishName",
        showBack: true,
      ),

      body: Column(
        children: [
          Padding(
            padding: EdgeInsets.all(10.sp),
            child: segmentedControl(
              selectedIndex: _selectedAgeGroup,
              items: _ageGroups.map((e) => SegmentItem(e)).toList(),
              onChanged: (i) => setState(() => _selectedAgeGroup = i),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(10.sp, 0, 10.sp, 0),
            child: segmentedControl(
              selectedIndex: _selectedQuarter,
              items: AppConstants.quarterLabels
                .map((label) => SegmentItem(label))
                .toList(),
              onChanged: (i) => setState(() => _selectedQuarter = i),
            ),
          ),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              key: ValueKey('$_selectedQuarter-$_isTeen'),
              child: _buildQuarterContent(
                _selectedQuarter,
                datesProvider.dates,
                submittedProvider,
                _isTeen,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuarterContent(
    int quarterIndex,
    Set<DateTime> allDates,
    SubmittedDatesProvider submittedProvider,
    bool isTeen,
  ) {
    final months = AppConstants.quarterMonths[quarterIndex];

    // Group Sundays by month and year for display
    final Map<String, List<DateTime>> sundaysByMonthYear = {};

    for (final date in allDates) {
      if (months.contains(date.month)) {
        final key = "${date.month}-${date.year}";
        sundaysByMonthYear.putIfAbsent(key, () => []).add(date);
      }
    }

    if (sundaysByMonthYear.isEmpty) {
      return Center(
        child: Text(
          AppLocalizations.of(context)?.noAssignmentsInQuarter ?? "No assignments in this quarter.",
          style: TextStyle(
            fontSize: 18.sp, 
            color: Colors.grey,
          ),
        ),
      );
    }

    List<Widget> monthWidgets = [];

    // Sort by year then month
    final sortedKeys = sundaysByMonthYear.keys.toList()
      ..sort((a, b) {
        final partsA = a.split('-').map(int.parse).toList();
        final partsB = b.split('-').map(int.parse).toList();
        final yearCompare = partsA[1].compareTo(partsB[1]);
        if (yearCompare == 0) return partsA[0].compareTo(partsB[0]);
        return yearCompare;
      });

    for (final key in sortedKeys) {
      final parts = key.split('-');
      final month = int.parse(parts[0]);
      final year = int.parse(parts[1]);

      final sundays = sundaysByMonthYear[key]!..sort(); // oldest first

      monthWidgets.add(
        Padding(
          padding: EdgeInsets.symmetric(vertical: 12.sp),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "${_getMonthName(month, context)} $year",
                style: TextStyle(
                  fontSize: 18.sp,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.secondary,
                ),
              ),
              SizedBox(height: 12.sp),
              Wrap(
                spacing: 12.sp,
                runSpacing: 12.sp,
                children: sundays.map((sunday) {
                  final normalized = DateTime(sunday.year, sunday.month, sunday.day);

                  final isSubmitted = isTeen
                      ? submittedProvider.teenSubmitted.contains(normalized)
                      : submittedProvider.adultSubmitted.contains(normalized);

                  final isGraded = isTeen
                      ? submittedProvider.teenGraded.contains(normalized)
                      : submittedProvider.adultGraded.contains(normalized);

                  Color cardColor;
                  Color textColor;
                  IconData icon;

                  if (isGraded) {
                    cardColor = Colors.blue.shade200;
                    textColor = Colors.blue.shade800;
                    icon = Icons.verified;
                  } else if (isSubmitted) {
                    cardColor = Colors.green.shade100;
                    textColor = Colors.green.shade800;
                    icon = Icons.check_circle;
                  } else {
                    cardColor = const Color.fromARGB(255, 226, 226, 226);
                    textColor = Colors.grey.shade700;
                    icon = Icons.pending;
                  }

                  return Material(
                    color: cardColor,
                    borderRadius: BorderRadius.circular(16.sp),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16.sp),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => AssignmentResponsePage(
                              date: sunday,
                              isTeen: _isTeen,
                            ),
                          ),
                        );
                      },
                      enableFeedback: AppSounds.soundEnabled,
                      child: Padding(
                        padding: EdgeInsets.all(16.sp),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Text(
                              "${sunday.day}",
                              style: TextStyle(
                                fontSize: 22.sp,
                                fontWeight: FontWeight.bold,
                                color: textColor,
                              ),
                            ),
                            SizedBox(height: 8.sp),
                            Icon(
                              icon,
                              color: textColor,
                              size: 24.sp,
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      children: monthWidgets,
    );
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
// lib/widgets/assignment_response_detail_page.dart

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:provider/provider.dart';
import '../../../UI/app_bar.dart';
import '../../../UI/app_buttons.dart';
import '../../../UI/app_colors.dart';
import '../../../UI/app_sound.dart';
import '../../../auth/login/auth_service.dart';
import '../../../backend_data/service/firestore/firestore_service.dart';
import '../../../backend_data/database/lesson_data.dart';
import '../../../l10n/app_localizations.dart';

class AssignmentResponseDetailPage extends StatefulWidget {
  final DateTime date;
  final bool isTeen;
  

  const AssignmentResponseDetailPage({
    super.key,
    required this.date,
    required this.isTeen,
  });

  @override
  State<AssignmentResponseDetailPage> createState() => _AssignmentResponseDetailPageState();
}

class _AssignmentResponseDetailPageState extends State<AssignmentResponseDetailPage> {
  late final FirestoreService _service;
  String _question = "";
  bool _loading = true;
  Map<String, bool> _userGradedStatus = {}; // userId → feedback
  Map<String, List<int>> userScores = {}; // userId → list of scores
  Map<String, String> userFeedback = {};

  @override
  void initState() {
    super.initState();
    final churchId = context.read<AuthService>().churchId;
    _service = FirestoreService(churchId: churchId);
    
    // Wait until after first frame — context is fully ready
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadQuestion();
    });
  }

  Future<void> _loadQuestion() async {
    final assignmentDay = await _service.loadAssignment(context, widget.date);
    String extracted = AppLocalizations.of(context)?.noQuestionAvailableForThisDay ?? "No question available for this day.";

    if (assignmentDay != null) {
      final SectionNotes? sectionNotes = widget.isTeen
          ? assignmentDay.teenNotes
          : assignmentDay.adultNotes;

      if (sectionNotes != null) {
        extracted = _extractSingleQuestion(sectionNotes.toMap());
      }
    }

    if (mounted) {
      setState(() {
        _question = extracted;
        _loading = false;
      });
    }
  }

  // Reused exactly from your AssignmentResponsePage — no duplication!
  String _extractSingleQuestion(Map<String, dynamic>? sectionMap) {
    if (sectionMap == null) return AppLocalizations.of(context)?.noQuestionAvailable ?? "No question available.";
    final List<dynamic>? blocks = sectionMap['blocks'] as List<dynamic>?;
    if (blocks == null || blocks.isEmpty) return AppLocalizations.of(context)?.noQuestionAvailable ?? "No question available.";

    for (final block in blocks) {
      final map = block as Map<String, dynamic>;
      final String? text = map['text'] as String?;

      if (text != null) {
        final trimmed = text.trim();
        if (trimmed.isNotEmpty) {
          if (trimmed.endsWith('?') ||
              trimmed.contains(RegExp(r'\(\d+\s*marks?\)', caseSensitive: false)) ||
              trimmed.contains('List') ||
              trimmed.contains('Explain') ||
              trimmed.contains('Discuss') ||
              trimmed.contains('Question')) {
            return trimmed;
          }
        }
      }

      if (map['type'] == 'numbered_list') {
        final List<dynamic>? items = map['items'] as List<dynamic>?;
        if (items != null && items.isNotEmpty) {
          final first = items.first as String;
          final trimmed = first.trim();
          if (trimmed.endsWith('?') || trimmed.contains(RegExp(r'\(\d+\s*marks?\)')))
            return trimmed;
        }
      }
    }

    // Fallback: first text or heading block
    for (final block in blocks) {
      final map = block as Map<String, dynamic>;
      if ((map['type'] == 'heading' || map['type'] == 'text') && map['text'] != null) {
        return (map['text'] as String).trim();
      }
    }

    return AppLocalizations.of(context)?.noQuestionAvailable ?? "No question available.";
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthService>();
    final churchId = auth.churchId;
    final isGlobalAdmin = auth.isGlobalAdmin;
    final isGroupAdmin = auth.isGroupAdmin;

    final String type = widget.isTeen ? "teen" : "adult";
    final String dateStr = "${widget.date.year}-${widget.date.month.toString().padLeft(2, '0')}-${widget.date.day.toString().padLeft(2, '0')}";

    // If no church, show message
    if ((!isGlobalAdmin || !isGroupAdmin) && churchId == null) {
      return Scaffold(
        appBar: AppAppBar(
          title: AppLocalizations.of(context)?.teenOrAdultResponses ?? "Responses",
          showBack: true,
        ),
        body: Center(child: Text(AppLocalizations.of(context)?.globalAdminsOnlyNoChurch ?? "Global admins only — no church selected.")),
      );
    }

    return Scaffold(
      appBar: AppAppBar(
        title: "${widget.isTeen ? AppLocalizations.of(context)?.teen ?? 'Teen' : AppLocalizations.of(context)?.adult ?? 'Adult'} ${AppLocalizations.of(context)?.teenOrAdultResponses ?? "Responses"}",
        showBack: true,
      ),

      body: _loading
          ? const Center(child: LinearProgressIndicator())
          : Padding(
              padding: EdgeInsets.all(16.sp),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Question
                  Card(
                    // Use surface color from theme (elevated surface in Material 3)
                    color: Theme.of(context).colorScheme.surface,

                    child: Padding(
                      padding: EdgeInsets.all(20.sp),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            AppLocalizations.of(context)?.question ?? "Question",
                            style: TextStyle(
                              fontSize: 20.sp,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          SizedBox(height: 10.sp),
                          Text(
                            _question,
                            style: TextStyle(
                              fontSize: 15.sp,
                              height: 1.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  SizedBox(height: 20.sp),
                  Text(
                    AppLocalizations.of(context)?.submissions ?? "Submissions",
                    style: TextStyle(fontSize: 22.sp, fontWeight: FontWeight.bold),
                  ),
                  Divider(height: 30.sp),
                  Expanded(
                    child: _buildAdminView(type, dateStr),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildAdminView(String type, String dateStr) {
    return FutureBuilder<List<AssignmentResponse>>(
      future: _service.loadAllResponsesForDate(
        date: widget.date,
        type: type,
      ),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text("Error: ${snapshot.error}"));
        }

        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final responses = snapshot.data!;
        if (responses.isEmpty) {
          return Center(child: Text(AppLocalizations.of(context)?.noSubmissionsYet ?? "No submissions yet."));
        }

        return ListView.builder(
          itemCount: responses.length,
          itemBuilder: (context, index) {
            final response = responses[index];

          // ✅ Use persistent state for scores
          if (!userScores.containsKey(response.userId)) {
            userScores[response.userId] =
                response.scores ?? List.filled(response.responses.length, 0);
          }
          final scores = userScores[response.userId]!;

          final isGraded = response.isGraded ?? false;

          return Card(
            margin: EdgeInsets.only(bottom: 12.sp), // keep some space between cards
            child: Stack(
              children: [
                ExpansionTile(
                  leading: Icon(
                    isGraded ? Icons.check_circle : Icons.pending,
                    size: 16.sp,
                    color: isGraded
                        ? Theme.of(context).colorScheme.onSurface
                        : Theme.of(context).colorScheme.onSurface.withOpacity(0.0),
                  ),
                  title: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      SizedBox(width: 6.sp),
                      Expanded(
                        child: Text(
                          response.userEmail ?? response.userId,
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                fontSize: 15.sp,
                              ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Padding(
                        padding: EdgeInsets.only(right: 8.sp),
                        child: Text(
                          "${scores.fold<int>(0, (a, b) => a + b)} / ${response.responses.length}",
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15.sp,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                      ),
                    ],
                  ),
                  iconColor: Theme.of(context).colorScheme.onSurface,
                  collapsedIconColor: Theme.of(context).colorScheme.onSurface,
                  childrenPadding: EdgeInsets.all(16.sp),
                  children: [
                    // All the answers
                    ...response.responses.asMap().entries.map((entry) {
                      final i = entry.key;
                      final answer = entry.value;

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Text(
                                  AppLocalizations.of(context)?.answerWithIndex(
                                    (i + 1).toString(),
                                    answer,
                                  ) ?? "• Answer ${i + 1}: $answer",
                                  style: Theme.of(context).textTheme.bodyMedium,
                                  softWrap: true,
                                  overflow: TextOverflow.visible,
                                ),
                              ),
                              SizedBox(width: 12.sp), // small gap
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: List.generate(2, (score) {
                                  return InkWell(
                                    onTap: () {
                                      setState(() {
                                        scores[i] = score;
                                      });
                                    },
                                    enableFeedback: AppSounds.soundEnabled,
                                    child: Container(
                                      margin: EdgeInsets.symmetric(horizontal: 4.sp),
                                      width: 40.sp,
                                      height: 30.sp,
                                      alignment: Alignment.center,
                                      decoration: BoxDecoration(
                                        color: scores[i] == score
                                            ? _getColorForScore(score, context)
                                            : _getColorForScore(score, context).withOpacity(0.3),
                                        borderRadius: BorderRadius.circular(2.sp),
                                      ),
                                      child: Text(
                                        "$score",
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 15.sp,
                                        ),
                                      ),
                                    ),
                                  );
                                }),
                              ),
                            ],
                          ),
                          SizedBox(height: 10.sp),
                        ],
                      );
                    }),

                    // Divider and buttons row – placed at the very end, inside the card
                    const Divider(height: 20, thickness: 1),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16.sp, vertical: 12.sp),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          // Reset Button (destructive)
                          GradeButtons(
                            context: context,
                            onPressed: isGraded
                              ? () async {
                                await _service.resetGrading(
                                  userId: response.userId,
                                  date: widget.date,
                                  type: type,
                                );
                                setState(() {});
                              }
                            : null,
                            text: AppLocalizations.of(context)?.reset ?? "Reset",
                            icon: Icons.restore,
                            topColor: Theme.of(context).colorScheme.error,
                            textColor: Theme.of(context).colorScheme.onError,
                            backDarken: 0.5,
                          ),

                          GradeButtons(
                            context: context,
                            onPressed: isGraded
                              ? null
                              : () async {
                                await _service.saveGrading(
                                  userId: response.userId,
                                  date: widget.date,
                                  type: type,
                                  scores: scores,
                                );
                                setState(() {});
                              },
                            text: AppLocalizations.of(context)?.grade ?? "Grade",
                            icon: Icons.check_circle_outline,
                            topColor: Theme.of(context).colorScheme.onSurface,
                            textColor: Theme.of(context).colorScheme.surface,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                // Graded stamp overlay (unchanged)
                if (_userGradedStatus[response.userId] ?? false)
                  Positioned(
                    bottom: 4.sp,
                    right: 4.sp,
                    child: Container(
                      padding: EdgeInsets.symmetric(horizontal: 7.sp, vertical: 3.sp),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary,
                        borderRadius: BorderRadius.circular(12.sp),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.verified, color: Colors.white, size: 12.sp),
                          SizedBox(width: 4.sp),
                          Text(
                            AppLocalizations.of(context)?.graded ?? "Graded",
                            style: TextStyle(
                              fontSize: 10.sp,
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          );
          },
        );
      },
    );
  }

  Color _getColorForScore(int score, BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    switch (score) {
      case 0: return AppColors.error;
      case 1: return AppColors.success;
      default: return colorScheme.onSurface.withOpacity(0.4);
    }
  }
}
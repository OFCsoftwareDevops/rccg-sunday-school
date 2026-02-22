// lib/widgets/leaderboard.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:provider/provider.dart';
import '../../UI/app_bar.dart';
import '../../UI/app_segment_sliding.dart';
import '../../../../auth/login/auth_service.dart';
import '../../l10n/app_localizations.dart';

class LeaderboardPage extends StatefulWidget {
  const LeaderboardPage({super.key});

  @override
  State<LeaderboardPage> createState() => _LeaderboardPageState();
}

class _LeaderboardPageState extends State<LeaderboardPage> {
  int _selectedAgeGroup = 0; // 0 = Adult, 1 = Teen
  int _selectedScope = 0;    // 0 = Church, 1 = Global

// Initialize with fallback values so first build doesn't crash
  List<String> _ageGroups = ['Adult', 'Teen'];
  List<String> _scopes = ['Church', 'Global'];

  @override
  void initState() {
    super.initState();

    // Initialize localized lists in initState after context is available
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      setState(() {
        _ageGroups = [
          AppLocalizations.of(context)?.adult ?? "Adult",
          AppLocalizations.of(context)?.teen ?? "Teen",
        ];
        _scopes = [
          AppLocalizations.of(context)?.church ?? "Church",
          AppLocalizations.of(context)?.global ?? "Global",
        ];
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthService>();
    final churchId = auth.churchId;
    final isAdmin = auth.isGlobalAdmin || (auth.hasChurch && auth.adminStatus.isChurchAdmin);

    return Scaffold(
      appBar: AppAppBar(
        title: AppLocalizations.of(context)?.leaderboard ?? "Leaderboard",
        showBack: true,
      ),
      body: Column(
        children: [
          // Top: Adult / Teen toggle
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.sp),
            child: segmentedControl(
              selectedIndex: _selectedAgeGroup,
              items: _ageGroups.map((e) => SegmentItem(e)).toList(),
              onChanged: (i) => setState(() => _selectedAgeGroup = i),
            ),
          ),
          // Nested: Church / Global toggle
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.sp, vertical: 8.sp),
            child: segmentedControl(
              selectedIndex: _selectedScope,
              items: _scopes.map((e) => SegmentItem(e)).toList(),
              onChanged: (i) => setState(() => _selectedScope = i),
            ),
          ),
          Expanded(
            child: _buildLeaderboard(churchId, isAdmin, _selectedAgeGroup, _selectedScope),
          ),
        ],
      ),
    );
  }

  Widget _buildLeaderboard(String? churchId, bool isAdmin, int ageGroup, int scope) {
    final bool isAdult = ageGroup == 0;
    final String type = isAdult ? "adult" : "teen";
    final bool isChurch = scope == 0;
    final colorScheme = Theme.of(context).colorScheme;
    final userId = FirebaseAuth.instance.currentUser?.uid;

    return FutureBuilder<List<UserRank>>(
      future: _fetchLeaderboard(churchId, isChurch, type),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: Text(
              "${AppLocalizations.of(context)?.errorWithMessage ?? 'Error:'} ${snapshot.error}",
            ),
          );
        }
        final ranks = snapshot.data ?? [];

        if (ranks.isEmpty) {
          return Center(
            child: Text(
              AppLocalizations.of(context)?.noRankingsYet ?? "No rankings yet in this category.",
            ),
          );
        }

        final myRankIndex = ranks.indexWhere((r) => r.userId == userId);
        final myRankText = myRankIndex != -1 ? "#${myRankIndex + 1}" : "Not ranked yet";

        return Column(
          children: [
            if (userId != null)
              Padding(
                padding: EdgeInsets.all(5.sp),
                child: SizedBox(
                  width: double.infinity,
                  height: 70.sp,
                  child: Card(
                    color: colorScheme.onSurface,
                    elevation: 1,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(5.sp.r),
                    ),
                    child: Center(
                      child: Text(
                        "${AppLocalizations.of(context)?.yourRank ?? 'Your Rank:'} $myRankText",
                        style: TextStyle(
                          color: colorScheme.surface,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            Expanded(
              child: ListView.builder(
                itemCount: ranks.length,
                itemBuilder: (context, index) {
                  final rank = ranks[index];
                  final isMe = rank.userId == userId;
                  final displayName = isAdmin || isMe 
                    ? rank.name 
                    : (AppLocalizations.of(context)?.anonymousStudent ?? "Anonymous Student");

                  return ListTile(
                    leading: _buildRankBadge(index + 1),
                    title: Text(
                      displayName,
                      style: TextStyle(
                        color: isMe
                          ? colorScheme.surface      // example: highlight current user
                          : colorScheme.onSurface // normal users
                      ),
                    ),
                    trailing: Text(
                      "${rank.totalScore} ${AppLocalizations.of(context)?.pointsLabel ?? 'pts'}",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: isMe ? colorScheme.surface: colorScheme.onSurface,
                      ),
                    ),
                    tileColor: isMe ? colorScheme.onSurface: null,
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildRankBadge(int rank) {
    if (rank == 1) return Icon(Icons.emoji_events, color: Colors.amber, size: 36.sp);
    if (rank == 2) return Icon(Icons.emoji_events, color: Colors.grey, size: 36.sp);
    if (rank == 3) return Icon(Icons.emoji_events, color: Colors.brown, size: 36.sp);
    return Text(
      "$rank",
      style: TextStyle(
        fontSize: 15.sp,
        color: Theme.of(context).colorScheme.onSurface,
      ),
    );
  }

  Future<List<UserRank>> _fetchLeaderboard(String? churchId, bool isChurch, String type) async {
    final db = FirebaseFirestore.instance;
    final List<UserRank> ranks = [];

    if (isChurch && churchId != null) {
      // Church leaderboard: query from church-specific leaderboard
      final leaderboardSnap = await db
          .collection('churches')
          .doc(churchId)
          .collection('leaderboard')
          .doc(type)
          .collection('members')
          .orderBy('totalScore', descending: true)
          .get();

      for (var doc in leaderboardSnap.docs) {
        final data = doc.data();
        final name = data['userEmail'] as String? ?? 'Unknown';
        final totalScore = data['totalScore'] as int? ?? 0;
        ranks.add(UserRank(userId: doc.id, name: name, totalScore: totalScore));
      }
    } else {
      // Global leaderboard: aggregate from all churches
      final churchesSnap = await db.collection('churches').get();
      final Map<String, int> scoreMap = {};
      final Map<String, String> nameMap = {};

      for (var churchDoc in churchesSnap.docs) {
        final cid = churchDoc.id;

        // Fetch leaderboard for this church
        final leaderboardSnap = await db
            .collection('churches')
            .doc(cid)
            .collection('leaderboard')
            .doc(type)
            .collection('members')
            .get();

        for (var doc in leaderboardSnap.docs) {
          final uid = doc.id;
          final data = doc.data();
          final totalScore = data['totalScore'] as int? ?? 0;
          final name = data['userEmail'] as String? ?? 'Unknown';

          scoreMap[uid] = (scoreMap[uid] ?? 0) + totalScore;
          nameMap[uid] = name;
        }
      }

      // Build final ranks
      for (var entry in scoreMap.entries) {
        ranks.add(UserRank(
          userId: entry.key,
          name: nameMap[entry.key] ?? 'Unknown',
          totalScore: entry.value,
        ));
      }

      ranks.sort((a, b) => b.totalScore.compareTo(a.totalScore));
    }

    return ranks;
  }
}

class UserRank {
  final String userId;
  final String name;
  final int totalScore;

  UserRank({
    required this.userId, 
    required this.name, 
    required this.totalScore,
  });
}
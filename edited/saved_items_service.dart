import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:rxdart/rxdart.dart';
import '../hive/hive_service.dart';

/// Service for managing user's saved items:
/// - Bookmarks (Bible verses/chapters)
/// - Saved Lessons
/// - Further Readings

/// All data is scoped per church and per user:
class SavedItemsService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // ──────────────── HELPERS ────────────────
  bool _isAnonymous(String userId) {
    final user = FirebaseAuth.instance.currentUser;
    return user != null && user.isAnonymous && user.uid == userId;
  }

  CollectionReference _userSubcollection(String userId, String name) {
    return _db.collection('users').doc(userId).collection(name);
  }

  String _cacheKey(String userId, String type) => '${type}_$userId';

  /// Retrieve cached items safely (returns empty list if invalid/no data)
  List<Map<String, dynamic>> getCachedItems(String userId, String type) {
    final raw = HiveBoxes.bookmarks.get(_cacheKey(userId, type));
    if (raw is List) {
      // Safer: map each item to Map<String, dynamic> explicitly
      return raw
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
    return [];
  }

  /*/ Convert Firestore Timestamp → Hive-friendly int (milliseconds)
  int? _timestampToMillis(Timestamp? ts) {
    return ts?.millisecondsSinceEpoch;
  }

  // Convert back when reading from Hive (if needed)
  Timestamp? _millisToTimestamp(int? millis) {
    if (millis == null) return null;
    return Timestamp.fromMillisecondsSinceEpoch(millis);
  }

  // Convert DateTime → millis (for local now)
  int _dateTimeToMillis(DateTime dt) => dt.millisecondsSinceEpoch;*/

  Future<void> cacheItems(String userId, String type, List<Map<String, dynamic>> items) async {
    await HiveBoxes.bookmarks.put(_cacheKey(userId, type), items);
  }

  // ──────────────────────────────────────────────
  //  Generic watcher + cache sync (used by all types)
  // ──────────────────────────────────────────────

  Stream<List<Map<String, dynamic>>> _watchItems({
    required String userId,
    required String collectionName,
    required String orderByField,
    required String cacheType,
  }) {
    final initial = getCachedItems(userId, cacheType);

    if (_isAnonymous(userId)) {
      return Stream.value(initial);
    }

    return _userSubcollection(userId, collectionName)
        .orderBy(orderByField, descending: true)
        .snapshots()
        .map((snap) {
          final fresh = snap.docs.map((doc) {
            final data = doc.data() as Map<String, dynamic>;

            // Convert Timestamps → millis before caching
            final safeData = Map<String, dynamic>.from(data)
              ..['id'] = doc.id;

            if (data['createdAt'] is Timestamp) {
              safeData['createdAtMillis'] = (data['createdAt'] as Timestamp).millisecondsSinceEpoch;
              safeData.remove('createdAt');
            }
            if (data['savedAt'] is Timestamp) {
              safeData['savedAtMillis'] = (data['savedAt'] as Timestamp).millisecondsSinceEpoch;
              safeData.remove('savedAt');
            }
            // Add more timestamp fields here if needed (updatedAt, etc.)

            return safeData;
          }).toList();

          // Update cache on every real update
          cacheItems(userId, cacheType, fresh);
          return fresh;
        })
        .startWith(initial); // emit cached data immediately
  }

  // ──────────────────────────────────────────────
  //  Bookmarks (scripture references)
  // ──────────────────────────────────────────────

  Stream<List<Map<String, dynamic>>> watchBookmarks(String userId) {
    return _watchItems(
      userId: userId,
      collectionName: 'bookmarks',
      orderByField: 'createdAt',
      cacheType: 'bookmarks',
    );
  }

  // ──────────────── BOOKMARKS ────────────────
  /// Add a bookmark (scripture reference)
  Future<String> addBookmark(
    String userId, {
    required String refId,
    required String title,
    String? text,
    String? note,
  }) async {
    final now = DateTime.now().toUtc(); // local timestamp for both cases

    final item = <String, dynamic>{
      'type': 'scripture',
      'refId': refId,
      'title': title,
      'text': text,
      'note': note,
      'createdAtMillis': now.millisecondsSinceEpoch,
    };

    String id;

    if (_isAnonymous(userId)) {
      id = 'local_${now.millisecondsSinceEpoch}';
      item['id'] = id;
    } else {
      final docRef = await _userSubcollection(userId, 'bookmarks').add({
        ...item,
        'createdAt': FieldValue.serverTimestamp(),
      });
      id = docRef.id;
      item['id'] = id;
    }

    // Optimistic cache update
    final current = getCachedItems(userId, 'bookmarks');
    await cacheItems(userId, 'bookmarks', [item, ...current]);

    return id;
  }

  /// Remove a bookmark by ID
  Future<void> removeBookmark(String userId, String bookmarkId) async {
    // Local optimistic remove
    final current = getCachedItems(userId, 'bookmarks');
    final updated = current.where((b) => b['id'] != bookmarkId).toList();
    await cacheItems(userId, 'bookmarks', updated);

    // Firestore only if not anonymous
    if (!_isAnonymous(userId)) {
      await _userSubcollection(userId, 'bookmarks').doc(bookmarkId).delete();
    }
  }

  Future<void> updateBookmarkNote(String userId, String bookmarkId, String note) async {
    // Local update
    final current = getCachedItems(userId, 'bookmarks');
    final updated = current.map((b) {
      if (b['id'] == bookmarkId) return {...b, 'note': note};
      return b;
    }).toList();
    await cacheItems(userId, 'bookmarks', updated);

    // Firestore only if not anonymous
    if (!_isAnonymous(userId)) {
      await _userSubcollection(userId, 'bookmarks').doc(bookmarkId).update({'note': note});
    }
  }

  Future<bool> isBookmarked(String userId, String refId) async {
    final current = getCachedItems(userId, 'bookmarks');
    return current.any((b) => b['refId'] == refId);
  }

  // ──────────────── SAVED LESSONS ────────────────
  Stream<List<Map<String, dynamic>>> watchSavedLessons(String userId) {
    return _watchItems(
      userId: userId,
      collectionName: 'saved_lessons',
      orderByField: 'savedAt',
      cacheType: 'saved_lessons',
    );
  }

  /// Save a lesson
  Future<String> saveLesson(
    String userId, {
    required String lessonId, // e.g. "2026-02-01"
    required String lessonType, // "adult" / "teen"
    required String title,
    String? preview,
    String? note,
  }) async {
    final item = {
      'lessonId': lessonId,
      'lessonType': lessonType,
      'title': title,
      'preview': preview,
      'note': note,
      'savedAt': FieldValue.serverTimestamp(),
    };

    final docRef = await _userSubcollection(userId, 'saved_lessons').add(item);
    return docRef.id;
  }

  /// Remove a saved lesson by its lessonId (e.g. "2025-12-7")
  Future<void> removeSavedLesson(String userId, String lessonId) async {
    final query = await _userSubcollection(userId, 'saved_lessons')
        .where('lessonId', isEqualTo: lessonId)
        .limit(1)
        .get();

    if (query.docs.isNotEmpty) {
      await query.docs.first.reference.delete();
    }
  }

  /// Update a saved lesson's note
  Future<void> updateSavedLessonNote(
    String userId,
    String lessonDocId,
    String note,
  ) async {
    await _userSubcollection(userId, 'saved_lessons')
        .doc(lessonDocId)
        .update({'note': note});
  }

  Future<bool> isLessonSaved(String userId, String lessonId) async {
    final current = getCachedItems(userId, 'saved_lessons');
    return current.any((l) => l['lessonId'] == lessonId);
  }

  // ──────────────── FURTHER READINGS ────────────────
  Stream<List<Map<String, dynamic>>> watchFurtherReadings(String userId) {
    return _watchItems(
      userId: userId,
      collectionName: 'further_readings',
      orderByField: 'savedAt',
      cacheType: 'further_readings',
    );
  }

  /// Add a further reading (external link, PDF reference, etc.)
  Future<String> addFurtherReading(
    String? userId, {
    required String title,
    String? reading,
    String? note,
  }) async {
    final item = {
      'title': title,
      'reading': reading,
      'note': note,
      'savedAt': FieldValue.serverTimestamp(),
    };

    final docRef = await _userSubcollection(userId!, 'further_readings').add(item);
    return docRef.id;
  }

  /// Remove a further reading
  Future<void> removeFurtherReading(String userId, String readingId) async {
    await _userSubcollection(userId, 'further_readings').doc(readingId).delete();
  }

  /// Update a further reading's note
  Future<void> updateFurtherReadingNote(
    String userId,
    String readingId,
    String note,
  ) async {
    // Update cache optimistically
    final current = getCachedItems(userId, 'further_readings');
    final updated = current.map((item) {
      if (item['id'] == readingId) {
        return {...item, 'note': note};
      }
      return item;
    }).toList();
    await cacheItems(userId, 'further_readings', updated);

    // Update Firestore if real user
    if (!_isAnonymous(userId)) {
      await _userSubcollection(userId, 'further_readings')
        .doc(readingId)
        .update({'note': note});
    }
  }

  /// Check if a further reading is already saved (by title or some unique key)
  Future<bool> isFurtherReadingSaved(String userId, String title) async {
    final current = getCachedItems(userId, 'further_readings');
    return current.any((r) => r['title'] == title);
  }
}

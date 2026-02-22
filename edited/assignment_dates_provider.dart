// lib/providers/assignment_dates_provider.dart
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'firestore_service.dart';

class AssignmentDatesProvider with ChangeNotifier {
  Set<DateTime> _allDates = {};
  bool _isLoading = true;

  Set<DateTime> get dates => _allDates;
  bool get isLoading => _isLoading;

  Future<void> load(BuildContext? context, FirestoreService service) async {
    _isLoading = true;
    notifyListeners();

    try {
      _allDates = await service.getAllAssignmentDates(context); // Uses preload cache
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error loading assignment dates: $e');
      }
    }
    
    _isLoading = false;
    notifyListeners();
  }

  Future<void> refresh(BuildContext? context, FirestoreService service) async {
    await load(context, service);
  }
}
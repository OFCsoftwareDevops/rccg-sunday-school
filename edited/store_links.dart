import 'dart:io';

class StoreLinks {
  /// Google Play Store
  static const String android = 'https://play.google.com/store/apps/details?id=com.ofcsoftwareDevops.rccgsundayschoolmanual';

  /// Apple App Store
  static const String ios = 'https://apps.apple.com/app/id6759505007';

  /// Apple direct review link
  static const String iosReview = 'https://apps.apple.com/app/id6759505007?action=write-review';

  static const String webPage = 'https://ofcsoftwaredevops.com/';
  //static const String webPage = 'https://ofcsoftwaredevops.github.io/rccg-sunday-school/';

  /// Returns correct store link for current platform
  static String get current {
    if (Platform.isIOS) return ios;
    return android;
  }

  /// Returns correct review link for current platform
  static String get review {
    if (Platform.isIOS) return iosReview;
    return android;
  }
}

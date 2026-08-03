import '../../core/constants.dart';
import '../../core/utils/doc_x.dart';

/// `users/{uid}.role` wire values (§2.1).
enum UserRole {
  kiter,
  business,
  admin,
  support,
  unknown;

  static UserRole parse(String? raw) => switch (raw) {
        'kiter' => kiter,
        'business' || 'host' || 'trainer' => business, // legacy aliases
        'admin' || 'owner' => admin,
        'support' => support,
        _ => unknown,
      };
}

/// `users/{uid}.status` (§2.2).
enum AccountStatus {
  active,
  pending,
  rejected,
  blocked,
  none;

  static AccountStatus parse(String? raw) => switch (raw) {
        'active' => active,
        'pending' => pending,
        'rejected' => rejected,
        'blocked' => blocked,
        _ => none,
      };
}

class AppUser {
  const AppUser({
    required this.uid,
    required this.name,
    required this.email,
    required this.role,
    required this.status,
    this.level,
    this.homeSpot,
    this.location,
    this.bio,
    this.nationality,
    this.age,
    this.phoneNumber,
    this.languages = const [],
    this.quiver = const [],
    this.gallery = const [],
    this.favorites = const [],
    this.photoUrl,
    this.businessType,
    this.ikoId,
    this.certificateUrl,
    this.mapsLink,
    this.hourlyRate,
    this.blockedUntilRaw,
    this.fcmToken,
    this.travelBufferMinutes,
  });

  final String uid;
  final String name;
  final String email;
  final UserRole role;
  final AccountStatus status;
  final String? level;
  final String? homeSpot;
  final String? location;
  final String? bio;
  final String? nationality;
  final int? age;
  final String? phoneNumber;
  final List<String> languages;
  final List<String> quiver;
  final List<String> gallery;
  final List<String> favorites;
  final String? photoUrl;
  final String? businessType;
  final String? ikoId;
  final String? certificateUrl;
  final String? mapsLink;
  final double? hourlyRate;

  /// ISO date string or the literal `'forever'`.
  final String? blockedUntilRaw;
  final String? fcmToken;

  // `instantBooking` removed: parsed from the profile but no caller ever
  // passed it, so every booking was created `pending` regardless (§14.3).
  // Dead code that read as a feature.
  final int? travelBufferMinutes;

  /// Canonical field names only — the `hostProfile` nested fallbacks,
  /// `businessName`, `profileImage` and the `priceList` string duplicate of
  /// `hourlyRate` all existed to read what a legacy web client wrote (§5.1).
  factory AppUser.fromDoc(String uid, Map<String, dynamic> d) => AppUser(
        uid: uid,
        name: d.str('name') ?? '',
        email: d.str('email') ?? '',
        role: UserRole.parse(d.str('role')),
        status: AccountStatus.parse(d.str('status')),
        level: d.str('level'),
        homeSpot: d.str('homeSpot'),
        location: d.str('location'),
        bio: d.str('bio'),
        nationality: d.str('nationality'),
        age: d.integer('age'),
        phoneNumber: d.str('phoneNumber'),
        languages: d.strList('languages'),
        quiver: d.strList('quiver'),
        gallery: d.strList('gallery'),
        favorites: d.strList('favorites'),
        photoUrl: d.str('photoURL'),
        businessType: d.str('businessType'),
        ikoId: d.str('ikoId'),
        certificateUrl: d.str('certificateUrl'),
        mapsLink: d.str('mapsLink'),
        hourlyRate: d.money('hourlyRate'),
        blockedUntilRaw: d.str('blockedUntil'),
        fcmToken: d.str('fcmToken'),
        travelBufferMinutes: d.integer('travelBuffer'),
      );

  bool get isTrainer => role == UserRole.business;
  bool get isStaff => role == UserRole.admin || role == UserRole.support;
  bool get isStation => businessType == 'Station';
  bool get isSafariOperator =>
      (businessType ?? '').toLowerCase().contains('safari');

  bool get isPermanentlyBlocked => blockedUntilRaw == 'forever';
  DateTime? get blockedUntil => isPermanentlyBlocked
      ? null
      : DateTime.tryParse(blockedUntilRaw ?? '');

  int get bufferMinutes => travelBufferMinutes ?? FlowConst.defaultBufferMinutes;
  double get displayRate => hourlyRate ?? FlowConst.defaultDisplayRate;
  String get initial => name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
}

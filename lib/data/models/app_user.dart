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
    this.reviewNote,
    this.travelBufferMinutes,
    this.instantBook = false,
    this.createdAt,
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

  /// Why staff declined the application, in their words.
  ///
  /// `rejectTrainer` has always written this; nothing ever read it, so a
  /// declined trainer was told to "check your notifications for the reason"
  /// and the reason itself sat unread on their own profile. The rejected
  /// gate shows it, because a decline the applicant cannot act on is a dead
  /// end rather than a decision.
  final String? reviewNote;

  // `instantBooking` removed: parsed from the profile but no caller ever
  // passed it, so every booking was created `pending` regardless (§14.3).
  // Dead code that read as a feature.
  //
  // P5 built the feature for real, under a *new* wire name on purpose: a
  // legacy `instantBooking: true` set years ago against a web client that
  // never honoured it must not silently start auto-confirming sessions now
  // that the whole pipeline (repository, rules, UI) actually obeys it.
  // Trainers opt in fresh, from the profile screen.
  final int? travelBufferMinutes;

  /// The trainer takes bookings without approving each one (P5): a rider's
  /// createBooking is born `confirmed`, and firestore.rules only lets a
  /// rider write that status when this flag is true on the trainer's doc.
  final bool instantBook;

  /// When the account was created. Both onboarding paths have always
  /// written it; the model never read it until the trainer profile needed
  /// "On FLOW since …" (P11) — the tenure line every marketplace prints.
  /// Null on docs from before the writes existed, and nothing invents one.
  final DateTime? createdAt;

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
    reviewNote: d.str('reviewNote'),
    travelBufferMinutes: d.integer('travelBuffer'),
    instantBook: d.boolean('instantBook'),
    createdAt: d.date('createdAt'),
  );

  bool get isTrainer => role == UserRole.business;
  bool get isStaff => role == UserRole.admin || role == UserRole.support;
  bool get isStation => businessType == 'Station';
  bool get isSafariOperator =>
      (businessType ?? '').toLowerCase().contains('safari');

  bool get isPermanentlyBlocked => blockedUntilRaw == 'forever';
  DateTime? get blockedUntil =>
      isPermanentlyBlocked ? null : DateTime.tryParse(blockedUntilRaw ?? '');

  /// Whether a `blocked` status is still in force (§2.4).
  ///
  /// A timed suspension has to lapse on its own: the user cannot rewrite
  /// their own `status` (firestore.rules pins it to staff), so if the gate
  /// only read `status` a 7-day ban would last until someone manually lifted
  /// it. The blocked screen's one-minute ticker invalidates the profile
  /// stream precisely so this getter is re-evaluated.
  ///
  /// Fails **closed**: `'forever'`, a missing date and an unparseable date
  /// all keep the block. A malformed value must never let someone out.
  bool get isBlockInForce {
    if (isPermanentlyBlocked) return true;
    final until = blockedUntil;
    if (until == null) return true;
    return DateTime.now().isBefore(until);
  }

  int get bufferMinutes =>
      travelBufferMinutes ?? FlowConst.defaultBufferMinutes;
  double get displayRate => hourlyRate ?? FlowConst.defaultDisplayRate;
  String get initial =>
      name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
}

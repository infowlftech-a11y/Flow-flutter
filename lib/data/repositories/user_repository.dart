import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/utils/doc_x.dart';
import '../firestore_paths.dart';
import '../models/app_user.dart';
import '../models/catalogue.dart';

class UserRepository {
  UserRepository(this._db);
  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _users =>
      _db.collection(Col.users);

  Stream<AppUser?> watchUser(String uid) =>
      _users.doc(uid).snapshots().map((snap) {
        final data = snap.data();
        if (data == null) return null;
        return AppUser.fromDoc(snap.id, data);
      });

  /// Explore source: every approved trainer/station (§6.2). Sorting stays
  /// client-side — a server-side orderBy would need a composite index.
  Stream<List<AppUser>> watchActiveTrainers() => _users
      .where('role', isEqualTo: 'business')
      .where('status', isEqualTo: 'active')
      .snapshots()
      .map((qs) => [
            for (final doc in qs.docs) AppUser.fromDoc(doc.id, doc.data()),
          ]);

  /// Rider onboarding — one page, `status: 'active'`, straight in (§3.2).
  Future<void> createRiderProfile({
    required String uid,
    required String name,
    required String email,
    required String nationality,
    required int age,
    required String level,
    String? homeSpot,
    required List<String> languages,
    List<String> quiver = const [],
    String? bio,
    String? photoUrl,
  }) {
    return _users.doc(uid).set(compact({
      'name': name,
      'email': email,
      'role': 'kiter',
      'status': 'active',
      'nationality': nationality,
      'age': age,
      'level': level,
      'homeSpot': homeSpot,
      'languages': languages,
      'quiver': quiver,
      'bio': bio,
      'photoURL': photoUrl,
      'favorites': <String>[],
      'createdAt': FieldValue.serverTimestamp(),
    }));
  }

  /// Trainer onboarding — `status: 'pending'` until an admin approves them in
  /// the in-app console (§3.2).
  ///
  /// v2.6 also wrote `priceList` (a string duplicate of `hourlyRate`) and
  /// `trainingSpot` (a duplicate of `location`) for the web client. Dropped:
  /// one field, one name.
  Future<void> createTrainerProfile({
    required String uid,
    required String name,
    required String email,
    required String bio,
    required List<String> languages,
    required String trainingSpot,
    String? mapsLink,
    required int hourlyRate,
    required String ikoId,
    String? certificateUrl,
    required String photoUrl,
    List<String> gallery = const [],
  }) {
    return _users.doc(uid).set(compact({
      'name': name,
      'email': email,
      'role': 'business',
      'status': 'pending',
      'businessType': 'Instructor',
      'bio': bio,
      'languages': languages,
      'location': trainingSpot,
      'mapsLink': mapsLink,
      'hourlyRate': hourlyRate,
      'ikoId': ikoId,
      'certificateUrl': certificateUrl,
      'photoURL': photoUrl,
      'gallery': gallery,
      'favorites': <String>[],
      'createdAt': FieldValue.serverTimestamp(),
    }));
  }

  /// Edit personal details (§3.13). Deliberately does NOT write rate or
  /// training spot — those are onboarding/support-only (§14.3). `compact`
  /// keeps nulls from clobbering web-client fields.
  Future<void> updateProfile(String uid, {
    String? name,
    String? phoneNumber,
    String? nationality,
    int? age,
    String? level,
    String? bio,
    List<String>? languages,
    String? photoUrl,
    List<String>? gallery,
    List<String>? quiver,
    String? homeSpot,
    Set<String> clear = const {},
  }) {
    return _users.doc(uid).update({
      ...compact({
      'name': name,
      'phoneNumber': phoneNumber,
      'nationality': nationality,
      'age': age,
      'level': level,
      'bio': bio,
      'languages': languages,
      'photoURL': photoUrl,
      'gallery': gallery,
        'quiver': quiver,
        'homeSpot': homeSpot,
        'updatedAt': FieldValue.serverTimestamp(),
      }),
      // Fields the user deliberately emptied.
      //
      // `compact` drops nulls, so a null argument means "not editing this
      // field" — that is what stops this form clobbering fields it doesn't
      // show. It also left no way to express "remove my bio": the write
      // silently no-opped while the UI reported success and popped, and the
      // old value reappeared on reopening. Clearing is a separate intent and
      // has to be named.
      for (final field in clear) field: FieldValue.delete(),
    });
  }

  /// Optimistic favourite toggle target.
  Future<void> setFavorite(String uid, String trainerId, bool fav) {
    return _users.doc(uid).update({
      'favorites': fav
          ? FieldValue.arrayUnion([trainerId])
          : FieldValue.arrayRemove([trainerId]),
    });
  }

  Future<void> saveFcmToken(String uid, String token) =>
      _users.doc(uid).update({'fcmToken': token});

  /// Drops this device's token from [uid]'s profile on sign-out.
  ///
  /// Push tokens are per-device, not per-account: left behind, the previous
  /// user's notifications keep arriving on this handset after somebody else
  /// signs in. Must run *before* `signOut()` — once the session is gone the
  /// rules reject the write.
  Future<void> clearFcmToken(String uid) =>
      _users.doc(uid).update({'fcmToken': FieldValue.delete()});

  Future<void> deleteProfile(String uid) => _users.doc(uid).delete();

  // Station catalogue (§5.5).

  Stream<List<StationInstructor>> watchStationInstructors(String stationId) =>
      _users
          .doc(stationId)
          .collection(Col.stationInstructors)
          .snapshots()
          .map((qs) => [
                for (final doc in qs.docs)
                  StationInstructor.fromDoc(doc.id, doc.data()),
              ]);

  Stream<List<StationService>> watchStationServices(String stationId) => _users
      .doc(stationId)
      .collection(Col.stationServices)
      .snapshots()
      .map((qs) => [
            for (final doc in qs.docs)
              StationService.fromDoc(doc.id, doc.data()),
          ]);

  Stream<List<SafariTrip>> watchSafariTrips(String hostId) => _db
      .collection(Col.safariTrips)
      .where('hostId', isEqualTo: hostId)
      .snapshots()
      .map((qs) => [
            for (final doc in qs.docs) SafariTrip.fromDoc(doc.id, doc.data()),
          ]);
}

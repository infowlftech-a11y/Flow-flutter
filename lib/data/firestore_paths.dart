/// Collection & storage names (APP_LOGIC_BLUEPRINT.md §6.1).
///
/// v2.6 froze these names because a web client shared the database. This app
/// is now the sole reader and writer, so the constraint is gone — but they
/// are still the names the Firestore security rules are written against, so
/// a rename means updating `firestore.rules` in the same change.
///
/// `listings` and `broadcasts` were declared but never touched; removed.
abstract final class Col {
  static const users = 'users';
  static const bookings = 'bookings';
  static const availability = 'availability';
  static const vacations = 'vacations';
  static const reviews = 'reviews';
  static const chats = 'chats';
  static const messages = 'messages'; // sub-collection of chats & tickets
  static const notifications = 'notifications';
  static const tickets = 'tickets';
  static const appeals = 'appeals';
  static const reports = 'reports';
  static const leaveReasons = 'leave_reasons';
  static const safariTrips = 'safari_trips';
  // P6: append-only staff accountability trail. Written by the console in
  // the same call as the action it records; immutable by rules.
  static const auditLog = 'audit_log';
  static const stationInstructors = 'station_instructors'; // users/{id}/…
  static const stationServices = 'station_services'; // users/{id}/…
}

abstract final class StorageFolder {
  static const profiles = 'profiles';
  static const galleries = 'galleries';
  static const listings = 'listings';
  static const certificates = 'certificates';
  static const reports = 'reports';
  static const appeals = 'appeals';
}

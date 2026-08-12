// The console directory's filters, as pure functions.
//
// filterUsers/filterBookings are what stand between "every account and every
// session on the platform" and the one the staff member is actually looking
// for. They are deliberately top-level functions so these tests can drive
// them without building a widget — the rendering is covered by
// admin_console_layout_test.dart.
import 'package:flutter_test/flutter_test.dart';

import 'package:flow/data/models/app_user.dart';
import 'package:flow/data/models/booking.dart';
import 'package:flow/features/admin/admin_directory.dart';

AppUser _user(
  String uid, {
  String? name,
  String? email,
  UserRole role = UserRole.kiter,
  AccountStatus status = AccountStatus.active,
}) =>
    AppUser(
      uid: uid,
      name: name ?? uid,
      email: email ?? '$uid@test.dev',
      role: role,
      status: status,
    );

Booking _booking(
  String id, {
  String student = 'Rider One',
  String instructor = 'Anna Bergström',
  BookingStatus status = BookingStatus.pending,
}) =>
    Booking(
      id: id,
      date: '2099-08-29',
      instructorId: 't_$instructor',
      instructorName: instructor,
      kiterId: 'r_$student',
      studentName: student,
      status: status,
    );

void main() {
  group('filterUsers', () {
    final users = [
      _user('u1', name: 'Seif Ahmed', email: 'seif@example.com'),
      _user('u2',
          name: 'Anna Bergström',
          email: 'anna@example.com',
          role: UserRole.business),
      _user('u3',
          name: 'Mostafa El-Sharkawy',
          email: 'mostafa@example.com',
          role: UserRole.business,
          status: AccountStatus.pending),
      _user('u4', name: 'Karim Adel', status: AccountStatus.blocked),
      _user('u5', name: 'Nadia Fouad', role: UserRole.admin),
    ];

    test('All passes everyone, including staff and the suspended', () {
      expect(filterUsers(users, UserFilter.all, '').length, 5);
    });

    test('role and status filters slice, not search', () {
      expect(filterUsers(users, UserFilter.riders, '').map((u) => u.uid),
          ['u1', 'u4'],
          reason: 'a suspended rider is still a rider');
      expect(filterUsers(users, UserFilter.business, '').map((u) => u.uid),
          ['u2', 'u3']);
      expect(filterUsers(users, UserFilter.pending, '').map((u) => u.uid),
          ['u3']);
      expect(filterUsers(users, UserFilter.suspended, '').map((u) => u.uid),
          ['u4']);
    });

    test('search is case-insensitive and matches name or email', () {
      expect(filterUsers(users, UserFilter.all, 'BERGSTRÖM').single.uid, 'u2');
      expect(filterUsers(users, UserFilter.all, 'mostafa@').single.uid, 'u3');
      expect(filterUsers(users, UserFilter.all, '  seif ').single.uid, 'u1',
          reason: 'whitespace around the query is not part of the query');
    });

    test('search composes with the filter rather than replacing it', () {
      // 'a' appears in every name; only two are business accounts.
      expect(filterUsers(users, UserFilter.business, 'a').length, 2);
      expect(filterUsers(users, UserFilter.suspended, 'seif'), isEmpty,
          reason: 'Seif is not suspended, whatever the search says');
    });

    test('no match is an empty list, not a throw', () {
      expect(filterUsers(users, UserFilter.all, 'zzz'), isEmpty);
      expect(filterUsers(const [], UserFilter.all, ''), isEmpty);
    });
  });

  group('filterBookings', () {
    final bookings = [
      _booking('b1', status: BookingStatus.pending),
      _booking('b2', status: BookingStatus.confirmed),
      _booking('b3',
          student: 'Karim Adel',
          instructor: 'Youssef Nabil',
          status: BookingStatus.completed),
      _booking('b4', status: BookingStatus.cancelled),
    ];

    test('null status means every status', () {
      expect(filterBookings(bookings, null, '').length, 4);
    });

    test('status filter is exact', () {
      expect(filterBookings(bookings, BookingStatus.confirmed, '')
          .single.id, 'b2');
      expect(
          filterBookings(bookings, BookingStatus.inProgress, ''), isEmpty);
    });

    test('search matches either side of the booking', () {
      expect(filterBookings(bookings, null, 'karim').single.id, 'b3',
          reason: 'by rider');
      expect(filterBookings(bookings, null, 'youssef').single.id, 'b3',
          reason: 'by trainer');
      expect(filterBookings(bookings, null, 'anna').length, 3);
    });

    test('status and search compose', () {
      expect(filterBookings(bookings, BookingStatus.completed, 'anna'),
          isEmpty,
          reason: "Anna's bookings are not completed");
      expect(
          filterBookings(bookings, BookingStatus.completed, 'karim')
              .single.id,
          'b3');
    });
  });
}

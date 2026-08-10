// friendlyError is the sentence a rider reads when the database refuses them.
// The one behaviour worth pinning: an unrecognised failure gets the *generic*
// line — a wrong specific message ("check your connection" for a permissions
// bug) is what previously sent people to their wifi settings for a rules
// problem.
import 'package:flutter_test/flutter_test.dart';

import 'package:flow/core/utils/error_copy.dart';

void main() {
  test('permission-denied reads as access, not connectivity', () {
    expect(friendlyError(Exception('[cloud_firestore/permission-denied] ...')),
        "You don't have access to this yet.");
  });

  test('unavailable and network failures read as connectivity', () {
    expect(friendlyError(Exception('firebase UNAVAILABLE')),
        'No connection. Check your internet and try again.');
    expect(friendlyError(const FormatException('network dropped')),
        'No connection. Check your internet and try again.');
  });

  test('a missing index names the real problem', () {
    expect(
        friendlyError(Exception('failed-precondition: the query requires an index')),
        "This view needs a database index that hasn't been created yet.");
  });

  test('failed-precondition without an index is NOT the index message', () {
    expect(friendlyError(Exception('failed-precondition: something else')),
        'Something went wrong. Please try again.');
  });

  test('anything unrecognised falls back to the vague truth', () {
    expect(friendlyError(StateError('surprise')),
        'Something went wrong. Please try again.');
  });
}

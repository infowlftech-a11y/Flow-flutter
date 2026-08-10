// The tab bar's index arithmetic, which spans two files and fails silently.
//
// `router.dart` declares six shell branches positionally; `app_shell.dart`
// maps four of them per role onto four destinations. Nothing connects the two
// but the integers, so reordering a branch in the router re-points a
// destination here — and the symptom is a tab that highlights the wrong icon
// or opens the wrong screen, never an exception.
//
// These assertions are cheap and catch exactly that class of mistake.
import 'package:flutter_test/flutter_test.dart';

import 'package:flow/features/shell/app_shell.dart';

void main() {
  // This group is the one that matters. The first version of this file
  // compared the branch constants only against each other, so swapping two of
  // them passed every assertion — a test that could not fail. `router.dart`
  // now builds its branches from `ShellBranch.paths`, so pinning each index to
  // its route is a real statement about where a tab goes.
  test('each branch index owns the route it claims', () {
    expect(ShellBranch.paths[ShellBranch.home], '/home');
    expect(ShellBranch.paths[ShellBranch.sessions], '/sessions');
    expect(ShellBranch.paths[ShellBranch.ticket], '/ticket');
    expect(ShellBranch.paths[ShellBranch.calendar], '/calendar');
    expect(ShellBranch.paths[ShellBranch.earnings], '/earnings');
    expect(ShellBranch.paths[ShellBranch.profile], '/profile');
  });

  test('the path list covers every declared branch', () {
    expect(ShellBranch.paths, hasLength(ShellBranch.count));
    expect(ShellBranch.paths.toSet(), hasLength(ShellBranch.count),
        reason: 'two branches sharing a path would make one unreachable');
  });

  test('the trainer bar goes Dashboard, Calendar, Earnings, Profile', () {
    expect(
      [for (final b in branchesFor(isTrainer: true)) ShellBranch.paths[b]],
      ['/home', '/calendar', '/earnings', '/profile'],
    );
  });

  test('the rider bar goes Discover, Sessions, Ticket, Profile', () {
    expect(
      [for (final b in branchesFor(isTrainer: false)) ShellBranch.paths[b]],
      ['/home', '/sessions', '/ticket', '/profile'],
    );
  });

  test('each role shows exactly four destinations', () {
    // Four is not arbitrary: the destination lists in AppShell are written out
    // literally, and a mapping of a different length would either overflow
    // them or leave one unreachable.
    expect(branchesFor(isTrainer: false), hasLength(4));
    expect(branchesFor(isTrainer: true), hasLength(4));
  });

  test('every mapped branch exists in the router', () {
    for (final isTrainer in [false, true]) {
      for (final branch in branchesFor(isTrainer: isTrainer)) {
        expect(branch, inInclusiveRange(0, ShellBranch.count - 1),
            reason: 'branch $branch is outside the router\'s shell route');
      }
    }
  });

  test('no role shows the same branch twice', () {
    for (final isTrainer in [false, true]) {
      final branches = branchesFor(isTrainer: isTrainer);
      expect(branches.toSet(), hasLength(branches.length),
          reason: 'a duplicated branch makes one destination unreachable and '
              'the other highlight two tabs at once');
    }
  });

  test('both roles start on home and end on profile', () {
    for (final isTrainer in [false, true]) {
      final branches = branchesFor(isTrainer: isTrainer);
      expect(branches.first, ShellBranch.home);
      expect(branches.last, ShellBranch.profile,
          reason: 'Profile is the rightmost tab in both bars — the redesign '
              'moved what sits between, not the anchors');
    }
  });

  test('roles do not share role-specific branches', () {
    final rider = branchesFor(isTrainer: false).toSet();
    final trainer = branchesFor(isTrainer: true).toSet();

    // A rider has no calendar or earnings; a trainer has no ticket, because
    // scanning one is their side of the same transaction. Getting this wrong
    // mounts a branch whose providers the role cannot even read.
    expect(rider, isNot(contains(ShellBranch.calendar)));
    expect(rider, isNot(contains(ShellBranch.earnings)));
    expect(trainer, isNot(contains(ShellBranch.ticket)));
    expect(trainer, isNot(contains(ShellBranch.sessions)),
        reason: 'trainers are redirected away from /sessions by the router, '
            'so showing it as a tab would be a dead destination');
  });
}

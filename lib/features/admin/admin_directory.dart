import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/typography.dart';
import '../../core/utils/date_x.dart';
import '../../core/utils/refs.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/flow_image.dart';
import '../../core/widgets/misc.dart';
import '../../core/widgets/session_card.dart';
import '../../core/widgets/sheets.dart';
import '../../core/widgets/surfaces.dart';
import '../../data/models/app_user.dart';
import '../../data/models/booking.dart';
import '../../providers/providers.dart';
import '../sessions/sessions_screen.dart' show StatusPill, statusColorFor;

/// The console's directory: every account and every session on the platform.
///
/// "Anything a rider or trainer cannot do has to live in the console,
/// otherwise it does not live anywhere" — and until now the console could
/// only see its *queues*. An account that was neither pending, reported,
/// appealing nor suspended was invisible to staff; a booking was visible
/// only through the two people on it. Support conversations routinely start
/// with a name and nothing else, and the person answering needs to find that
/// name, see their sessions, and act.

// ── Filters, as data ─────────────────────────────────────────────────────
//
// Pure and top-level so the tests can drive them without building a widget.

enum UserFilter {
  all('All'),
  riders('Riders'),
  business('Trainers'),
  pending('Pending'),
  suspended('Suspended');

  const UserFilter(this.label);
  final String label;

  bool matches(AppUser u) => switch (this) {
    all => true,
    riders => u.role == UserRole.kiter,
    business => u.role == UserRole.business,
    pending => u.status == AccountStatus.pending,
    suspended => u.status == AccountStatus.blocked,
  };
}

/// Case-insensitive name/email/member-ID search over a role/status filter.
///
/// The ID match is containment, so "FLW-R-7X8K", "7X8K" and a half-typed
/// "7x8" all land on the same row — support reads these off tickets and
/// phone calls, rarely in full.
List<AppUser> filterUsers(
  List<AppUser> users,
  UserFilter filter,
  String query,
) {
  final q = query.trim().toLowerCase();
  return [
    for (final u in users)
      if (filter.matches(u) &&
          (q.isEmpty ||
              u.name.toLowerCase().contains(q) ||
              u.email.toLowerCase().contains(q) ||
              memberRef(
                u.uid,
                coach: u.role == UserRole.business,
              ).toLowerCase().contains(q)))
        u,
  ];
}

/// Status filter + name search over every booking.
List<Booking> filterBookings(
  List<Booking> bookings,
  BookingStatus? status,
  String query,
) {
  final q = query.trim().toLowerCase();
  return [
    for (final b in bookings)
      if ((status == null || b.status == status) &&
          (q.isEmpty ||
              b.studentName.toLowerCase().contains(q) ||
              b.instructorName.toLowerCase().contains(q) ||
              // The `FLW-…` reference tickets and reports carry — pasting
              // one here is how staff get from a complaint to its booking.
              sessionRef(b.id, b.date).toLowerCase().contains(q)))
        b,
  ];
}

// ── USERS ────────────────────────────────────────────────────────────────

class UsersTab extends ConsumerStatefulWidget {
  const UsersTab({super.key});

  @override
  ConsumerState<UsersTab> createState() => _UsersTabState();
}

class _UsersTabState extends ConsumerState<UsersTab> {
  final _search = TextEditingController();
  UserFilter _filter = UserFilter.all;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final users = ref.watch(allUsersProvider);

    return AsyncView<List<AppUser>>(
      value: users,
      onRetry: () => ref.invalidate(allUsersProvider),
      onRefresh: () async {
        ref.invalidate(allUsersProvider);
        await ref.read(allUsersProvider.future);
      },
      skeleton: const SkeletonList(count: 6, itemHeight: 76),
      data: (list) {
        final shown = filterUsers(list, _filter, _search.text);
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
              child: TextField(
                controller: _search,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: 'Search name, email or ID…',
                  prefixIcon: const Icon(Symbols.search_rounded),
                  suffixIcon: _search.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Clear search',
                          onPressed: () => setState(_search.clear),
                          icon: const Icon(Symbols.close_rounded),
                        ),
                ),
              ),
            ),
            SizedBox(
              height: 52,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 6),
                children: [
                  for (final f in UserFilter.values)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FlowChoiceChip(
                        label: f.label,
                        selected: _filter == f,
                        onTap: () => setState(() => _filter = f),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: shown.isEmpty
                  ? const EmptyView.scrollable(
                      icon: Symbols.person_search_rounded,
                      title: 'No accounts match',
                      subtitle: 'Try another name, or clear the filter.',
                    )
                  : ListView.separated(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                      itemCount: shown.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, i) => _UserCard(user: shown[i]),
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _UserCard extends ConsumerWidget {
  const _UserCard({required this.user});
  final AppUser user;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tones = context.tones;
    final statusColor = switch (user.status) {
      AccountStatus.active => tones.success,
      AccountStatus.pending => tones.warning,
      AccountStatus.rejected => tones.danger,
      AccountStatus.blocked => tones.danger,
      _ => tones.textFaint,
    };

    return FlowCard(
      onTap: () => _openUserSheet(context, ref, user),
      child: Row(
        children: [
          FlowAvatar(url: user.photoUrl, name: user.name, size: 44),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user.name.isEmpty ? '(no name yet)' : user.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 3),
                // The member ID rides directly under the name — it is the
                // handle bans and suspensions are discussed by, so the row
                // shows the same string the search matches. Staff accounts
                // have no member ID; they are not members.
                if (!user.isStaff)
                  Text(
                    memberRef(user.uid, coach: user.role == UserRole.business),
                    style: interNum(
                      11.5,
                      640,
                      color: tones.azureBrand,
                      spacing: .4,
                    ),
                  ),
                const SizedBox(height: 3),
                // Two lines — same reason as the approval card: the domain
                // half of an email is what staff search by, and one line
                // dropped it at 1.3x.
                Text(
                  user.email,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: inter(12.5, 480, color: tones.textFaint),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              TagPill(_roleLabel(user), dense: true),
              const SizedBox(height: 4),
              TagPill(
                user.status.name.toUpperCase(),
                color: statusColor,
                dense: true,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

String _roleLabel(AppUser u) {
  if (u.isStaff) return 'STAFF';
  if (u.role == UserRole.business) {
    return u.isStation
        ? 'STATION'
        : u.isSafariOperator
        ? 'SAFARI'
        : 'TRAINER';
  }
  return 'RIDER';
}

/// Everything staff can know and do about one account, in one sheet.
void _openUserSheet(BuildContext context, WidgetRef ref, AppUser user) {
  showFlowSheet<void>(
    context,
    title: user.name.isEmpty ? user.email : user.name,
    subtitle: [
      _roleLabel(user),
      if (!user.isStaff)
        memberRef(user.uid, coach: user.role == UserRole.business),
      user.status.name,
    ].join(' · '),
    builder: (sheetContext) => _UserSheetBody(user: user),
  );
}

class _UserSheetBody extends ConsumerWidget {
  const _UserSheetBody({required this.user});
  final AppUser user;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tones = context.tones;

    // The user's footprint, from streams the console already holds open.
    // Derived on read, not stored on the profile — the console sees every
    // booking, so the numbers cannot go stale and no counter needs a write.
    final bookings = ref.watch(allBookingsProvider).value ?? const <Booking>[];
    final asRider = [
      for (final b in bookings)
        if (b.kiterId == user.uid) b,
    ];
    final asTrainer = [
      for (final b in bookings)
        if (b.instructorId == user.uid) b,
    ];
    int done(List<Booking> list) =>
        list.where((b) => b.status == BookingStatus.completed).length;
    // Cancels *they* chose, not cancellations that happened to them — the
    // number that matters when weighing a suspension.
    int walkedAwayFrom(List<Booking> list, String by) => list
        .where(
          (b) => b.status == BookingStatus.cancelled && b.cancelledBy == by,
        )
        .length;
    double volume(List<Booking> list) => list
        .where((b) => b.status == BookingStatus.completed)
        .fold(0, (sum, b) => sum + b.amountDue);
    final isCoach = user.role == UserRole.business;
    final openTickets =
        ref
            .watch(allTicketsProvider)
            .value
            ?.where((t) => t.userId == user.uid && t.isOpen)
            .length ??
        0;
    final reportsAgainst =
        ref
            .watch(reportsProvider)
            .value
            ?.where((r) => r.reportedUserId == user.uid && r.isOpen)
            .length ??
        0;

    final facts = <(String, String)>[
      if (!user.isStaff)
        (
          isCoach ? 'Coach ID' : 'Rider ID',
          memberRef(user.uid, coach: isCoach),
        ),
      ('Email', user.email),
      if (user.location != null) ('Location', user.location!),
      if (user.nationality != null) ('Nationality', user.nationality!),
      if (user.level != null) ('Level', user.level!),
      if (isCoach) ('Rate', '${money(user.displayRate)}/h'),
      if (user.ikoId != null) ('Credential', user.ikoId!),
      ('Sessions as rider', '${asRider.length} · ${done(asRider)} completed'),
      if (isCoach)
        (
          'Sessions as coach',
          '${asTrainer.length} · ${done(asTrainer)} completed',
        ),
      (
        'Cancelled by them',
        isCoach
            ? '${walkedAwayFrom(asRider, 'user')} as rider · '
                  '${walkedAwayFrom(asTrainer, 'provider')} as coach'
            : '${walkedAwayFrom(asRider, 'user')}',
      ),
      if (done(asRider) > 0) ('Spent on sessions', money(volume(asRider))),
      if (isCoach && done(asTrainer) > 0)
        ('Earned as coach', money(volume(asTrainer))),
      ('Open tickets', '$openTickets'),
      ('Open reports against them', '$reportsAgainst'),
      if (user.status == AccountStatus.blocked)
        (
          'Suspended until',
          user.isPermanentlyBlocked
              ? 'forever'
              : user.blockedUntilRaw == null
              ? 'unknown'
              : prettyYmd(user.blockedUntilRaw!),
        ),
    ];

    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
      children: [
        for (final (label, value) in facts)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 132,
                  child: Text(
                    label.toUpperCase(),
                    style: microLabel(tones.textFaint, size: 10),
                  ),
                ),
                Expanded(
                  child: Text(
                    value,
                    style: inter(
                      13.5,
                      560,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 12),
        if (user.role == UserRole.business &&
            user.status == AccountStatus.active) ...[
          OutlinedButton.icon(
            onPressed: () => context.push(
              user.isStation || user.isSafariOperator
                  ? '/station/${user.uid}'
                  : '/trainer/${user.uid}',
            ),
            icon: const Icon(Symbols.visibility_rounded, size: 20),
            label: const Text('View public profile'),
          ),
          const SizedBox(height: 8),
        ],
        if (!user.isStaff && user.status != AccountStatus.blocked)
          PrimaryButton(
            label: 'Suspend account',
            destructive: true,
            onPressed: () => _suspend(context, ref),
          ),
        if (user.status == AccountStatus.blocked)
          PrimaryButton(
            label: 'Lift suspension',
            onPressed: () => _lift(context, ref),
          ),
        if (user.isStaff)
          Text(
            'Staff accounts are managed in the Firebase console, not here — '
            'the person you would be suspending can see this screen too.',
            style: inter(12.5, 460, color: tones.textFaint),
          ),
      ],
    );
  }

  Future<void> _suspend(BuildContext context, WidgetRef ref) async {
    // Same wording and mechanics as the report flow's uphold — one mental
    // model for "suspend", wherever staff reach it from.
    final sure = await confirmAction(
      context,
      title:
          'Suspend ${user.name.isEmpty ? 'this account' : user.name} '
          'for 7 days?',
      body:
          'They lose access immediately and are shown the suspension gate. '
          'They can appeal, and you can lift it from the Suspended tab.',
      confirmLabel: 'Suspend',
      cancelLabel: 'Not yet',
      destructive: true,
    );
    if (!sure || !context.mounted) return;
    final until = DateTime.now().add(const Duration(days: 7)).toIso8601String();
    try {
      await ref.read(adminRepositoryProvider).blockUser(user.uid, until: until);
      if (context.mounted) {
        Navigator.pop(context);
        showFlowToast(
          context,
          '${user.name} suspended until ${prettyYmd(until)}',
        );
      }
    } catch (_) {
      if (context.mounted) {
        showFlowToast(context, "Couldn't suspend the account. Try again.");
      }
    }
  }

  Future<void> _lift(BuildContext context, WidgetRef ref) async {
    final sure = await confirmAction(
      context,
      title: 'Lift this suspension?',
      body:
          '${user.name.isEmpty ? 'The account' : user.name} regains full '
          'access immediately.',
      confirmLabel: 'Lift suspension',
    );
    if (!sure || !context.mounted) return;
    try {
      await ref.read(adminRepositoryProvider).unblockUser(user.uid);
      if (context.mounted) {
        Navigator.pop(context);
        showFlowToast(context, 'Suspension lifted');
      }
    } catch (_) {
      if (context.mounted) {
        showFlowToast(context, "Couldn't lift it. Try again.");
      }
    }
  }
}

// ── SESSIONS ─────────────────────────────────────────────────────────────

class AllSessionsTab extends ConsumerStatefulWidget {
  const AllSessionsTab({super.key});

  @override
  ConsumerState<AllSessionsTab> createState() => _AllSessionsTabState();
}

class _AllSessionsTabState extends ConsumerState<AllSessionsTab> {
  final _search = TextEditingController();
  BookingStatus? _status;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bookings = ref.watch(allBookingsProvider);

    return AsyncView<List<Booking>>(
      value: bookings,
      onRetry: () => ref.invalidate(allBookingsProvider),
      onRefresh: () async {
        ref.invalidate(allBookingsProvider);
        await ref.read(allBookingsProvider.future);
      },
      skeleton: const SkeletonList(count: 6, itemHeight: 76),
      data: (list) {
        final shown = filterBookings(list, _status, _search.text);
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
              child: TextField(
                controller: _search,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: 'Search rider or trainer…',
                  prefixIcon: const Icon(Symbols.search_rounded),
                  suffixIcon: _search.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Clear search',
                          onPressed: () => setState(_search.clear),
                          icon: const Icon(Symbols.close_rounded),
                        ),
                ),
              ),
            ),
            SizedBox(
              height: 52,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 6),
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FlowChoiceChip(
                      label: 'All',
                      selected: _status == null,
                      onTap: () => setState(() => _status = null),
                    ),
                  ),
                  for (final s in const [
                    BookingStatus.pending,
                    BookingStatus.confirmed,
                    BookingStatus.inProgress,
                    BookingStatus.completed,
                    BookingStatus.cancelled,
                    BookingStatus.rejected,
                  ])
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FlowChoiceChip(
                        label: s.label,
                        selected: _status == s,
                        onTap: () => setState(() => _status = s),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: shown.isEmpty
                  ? const EmptyView.scrollable(
                      icon: Symbols.event_busy_rounded,
                      title: 'No sessions match',
                      subtitle:
                          'Every booking on the platform is searchable here.',
                    )
                  : ListView.separated(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                      itemCount: shown.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, i) {
                        final b = shown[i];
                        return SessionRow(
                          when: '${prettyYmd(b.date)} · ${b.timeRange}',
                          who: '${b.studentName} → ${b.instructorName}',
                          priceLabel: money(b.totalPrice),
                          statusLabel: b.status.label.toUpperCase(),
                          statusColor: statusColorFor(context, b.status),
                          onTap: () => _openSessionSheet(context, b),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}

void _openSessionSheet(BuildContext context, Booking b) {
  showFlowSheet<void>(
    context,
    title: b.title,
    subtitle: '${prettyYmd(b.date)} · ${b.timeRange}',
    builder: (sheetContext) {
      final tones = sheetContext.tones;
      final facts = <(String, String)>[
        ('Session ID', sessionRef(b.id, b.date)),
        ('Rider', b.studentName),
        ('Trainer', b.instructorName),
        ('Hours', '${b.durationHours ?? '—'}'),
        ('Price', money(b.totalPrice)),
        ('Payment', b.payment.status.label),
        ('Checked in', b.checkedIn ? 'yes' : 'no'),
        if (b.gearNeeded) ('Gear', 'needs gear'),
        if (b.message != null && b.message!.trim().isNotEmpty)
          ('Message', b.message!),
        if (b.createdAt != null) ('Requested', timeAgo(b.createdAt!)),
      ];
      return ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: StatusPill(status: b.status),
          ),
          const SizedBox(height: 14),
          for (final (label, value) in facts)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 110,
                    child: Text(
                      label.toUpperCase(),
                      style: microLabel(tones.textFaint, size: 10),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      value,
                      style: inter(
                        13.5,
                        560,
                        color: Theme.of(sheetContext).colorScheme.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      );
    },
  );
}

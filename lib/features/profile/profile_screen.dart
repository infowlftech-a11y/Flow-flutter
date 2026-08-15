import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants.dart';
import '../../core/theme/radii.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/typography.dart';
import '../../core/utils/haptics.dart';
import '../../core/utils/refs.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/flow_top_bar.dart';
import '../../core/widgets/flow_image.dart';
import '../../core/widgets/misc.dart';
import '../../core/widgets/sheets.dart';
import '../../core/widgets/surfaces.dart';
import '../../core/widgets/theme_swap.dart';
import '../../data/repositories/auth_repository.dart';
import '../../providers/providers.dart';
import '../../providers/settings_provider.dart';

/// Profile & settings (§3.13).
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final user = session.user;
    final tones = context.tones;

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // P13: the shared header, same shape as every top-level tab.
            const FlowTopBar(title: 'Profile'),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                children: [
                  // Identity block.
                  Row(
                    children: [
                      GestureDetector(
                        onTap: () => context.push('/profile/edit'),
                        child: Stack(
                          children: [
                            FlowAvatar(
                              url: user?.photoUrl,
                              name: session.displayName,
                              size: 76,
                            ),
                            Positioned(
                              right: 0,
                              bottom: 0,
                              child: Container(
                                padding: const EdgeInsets.all(5),
                                decoration: BoxDecoration(
                                  color: tones.azureBrand,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Theme.of(
                                      context,
                                    ).scaffoldBackgroundColor,
                                    width: 2,
                                  ),
                                ),
                                child: const Icon(
                                  Symbols.edit_rounded,
                                  size: 12,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              session.displayName,
                              style: Theme.of(context).textTheme.headlineMedium,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              user?.email ?? '',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                TagPill(
                                  session.isTrainer
                                      ? 'TRAINER'
                                      : (user?.level ?? 'RIDER').toUpperCase(),
                                ),
                                if (user?.nationality != null)
                                  TagPill(
                                    user!.nationality!,
                                    color: tones.textFaint,
                                  ),
                                if ((user?.location ?? user?.homeSpot) != null)
                                  TagPill(
                                    user!.location ?? user.homeSpot!,
                                    icon: Symbols.place_rounded,
                                    color: tones.textFaint,
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  // The Staff section stood here. Staff accounts now resolve to
                  // AppStage.staff and never reach this screen — the console is their
                  // whole app — so a row pointing at it would be unreachable code
                  // pretending to be a feature.
                  const SizedBox(height: 28),
                  const SectionHeader('Account'),
                  _SettingsCard(
                    children: [
                      _row(
                        context,
                        Symbols.badge_rounded,
                        'Personal details',
                        subtitle: 'Name, photo, languages and level',
                        onTap: () => context.push('/profile/edit'),
                      ),
                      // The ID support and the console know this account by (P3) —
                      // derived from the uid, same scheme as the FLW- session refs.
                      // Tap copies: it exists to be pasted into a ticket or read
                      // aloud, never memorised.
                      _row(
                        context,
                        Symbols.fingerprint_rounded,
                        session.isTrainer ? 'Coach ID' : 'Rider ID',
                        subtitle:
                            '${memberRef(session.uid, coach: session.isTrainer)} — '
                            'tap to copy for support',
                        onTap: () {
                          Clipboard.setData(
                            ClipboardData(
                              text: memberRef(
                                session.uid,
                                coach: session.isTrainer,
                              ),
                            ),
                          );
                          showFlowToast(context, 'ID copied');
                        },
                      ),
                      if (session.isTrainer)
                        _row(
                          context,
                          Symbols.visibility_rounded,
                          'View my public profile',
                          subtitle: 'Exactly what riders see before they book',
                          onTap: () => context.push('/trainer/${session.uid}'),
                        ),
                      // Instant Book (P5) — the trainer's side of the switch the
                      // booking rules read. SwitchListTile rather than _row: the
                      // state must be visible without opening anything.
                      if (session.isTrainer)
                        SwitchListTile(
                          secondary: const Icon(Symbols.bolt_rounded, size: 22),
                          title: Text(
                            'Instant booking',
                            style: inter(
                              15,
                              560,
                              color: context.scheme.onSurface,
                            ),
                          ),
                          subtitle: Text(
                            (user?.instantBook ?? false)
                                ? 'Riders book and pay without waiting for your '
                                      'approval'
                                : 'Off — every request waits for your approval',
                            maxLines: 2,
                            style: inter(12.5, 460, color: tones.textFaint),
                          ),
                          value: user?.instantBook ?? false,
                          onChanged: (v) async {
                            Haptics.select();
                            try {
                              await ref
                                  .read(userRepositoryProvider)
                                  .setInstantBook(session.uid, v);
                              if (context.mounted) {
                                showFlowToast(
                                  context,
                                  v
                                      ? 'Instant booking on — new bookings '
                                            'confirm themselves ⚡'
                                      : 'Instant booking off — requests wait '
                                            'for you again',
                                );
                              }
                            } catch (_) {
                              if (context.mounted) {
                                showFlowToast(
                                  context,
                                  "Couldn't save that. Try again.",
                                );
                              }
                            }
                          },
                        ),
                      _row(
                        context,
                        Symbols.mail_rounded,
                        'Email address',
                        subtitle: user?.email ?? '—',
                        onTap: () =>
                            _openEmailSheet(context, user?.email ?? ''),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  const SectionHeader('Notifications'),
                  _SettingsCard(
                    children: [
                      _row(
                        context,
                        Symbols.inbox_rounded,
                        'Notification inbox',
                        subtitle: 'Everything the app has told you',
                        onTap: () => context.push('/notifications'),
                      ),
                      _row(
                        context,
                        Symbols.tune_rounded,
                        'Push notifications',
                        subtitle: 'Managed in your phone settings',
                        onTap: () => _openPushSheet(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  const SectionHeader('Support'),
                  _SettingsCard(
                    children: [
                      _row(
                        context,
                        Symbols.support_agent_rounded,
                        'Help & support',
                        subtitle: 'Open a ticket — we answer in the app',
                        onTap: () => context.push('/support'),
                      ),
                      _row(
                        context,
                        Symbols.menu_book_rounded,
                        'How FLOW works',
                        subtitle: 'Booking, check-in and payment, explained',
                        onTap: () =>
                            _openHowItWorksSheet(context, session.isTrainer),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  // Restored 2026-08-15: removed by 8593e8a (which was about
                  // staff routing, not theming), leaving the app pinned to
                  // whatever the phone's system theme said with no way to
                  // choose — reported as "the app is stuck in dark mode".
                  const SectionHeader('Appearance'),
                  _SettingsCard(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(6),
                        child: SegmentedButton<ThemeMode>(
                          segments: const [
                            ButtonSegment(
                              value: ThemeMode.system,
                              icon: Icon(
                                Symbols.brightness_auto_rounded,
                                size: 17,
                              ),
                              label: Text('Auto'),
                            ),
                            ButtonSegment(
                              value: ThemeMode.light,
                              icon: Icon(Symbols.light_mode_rounded, size: 17),
                              label: Text('Light'),
                            ),
                            ButtonSegment(
                              value: ThemeMode.dark,
                              icon: Icon(Symbols.dark_mode_rounded, size: 17),
                              label: Text('Dark'),
                            ),
                          ],
                          selected: {ref.watch(themeModeProvider)},
                          // Material 3 replaces the leading icon with a tick
                          // on the selected segment, and segments size to
                          // their content — so every selection change
                          // re-flowed the row and the fill sat over a
                          // different span than the label under it. Keeping
                          // the brightness icons holds all three widths
                          // constant.
                          showSelectedIcon: false,
                          onSelectionChanged: (s) {
                            Haptics.select();
                            // Through ThemeSwap: the old frame fades out over
                            // the new theme instead of the whole tree lerping
                            // per tick.
                            ThemeSwap.of(context).run(
                              () => ref
                                  .read(themeModeProvider.notifier)
                                  .set(s.first),
                            );
                          },
                          style: ButtonStyle(
                            side: WidgetStatePropertyAll(
                              BorderSide(color: tones.line),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  const SectionHeader('Privacy & data'),
                  _SettingsCard(
                    children: [
                      _row(
                        context,
                        Symbols.shield_rounded,
                        'Security & data',
                        subtitle: 'What we store, and who can see it',
                        onTap: () => _openPrivacySheet(context),
                      ),
                      _row(
                        context,
                        Symbols.gavel_rounded,
                        'Terms & conditions',
                        onTap: () => _openTermsSheet(context),
                      ),
                      _row(
                        context,
                        Symbols.manage_accounts_rounded,
                        'Manage my account',
                        subtitle: 'Export or delete everything',
                        onTap: () => _openAccountSheet(context, ref),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  // Sign out sits alone, and Delete lives one level down inside
                  // "Manage my account". They used to be adjacent rows in adjacent
                  // cards, ~60dp apart, with the destructive one *below* the one
                  // people tap daily — and the tap that costs you your account was
                  // the easier one to hit by accident.
                  _SettingsCard(
                    children: [
                      _row(
                        context,
                        Symbols.logout_rounded,
                        'Sign out',
                        onTap: () async {
                          final ok = await confirmAction(
                            context,
                            title: 'Sign out?',
                            body:
                                "You'll need your email and password to get back in.",
                            confirmLabel: 'Sign out',
                          );
                          if (ok) await ref.read(signOutProvider)();
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Center(
                    child: Text(
                      FlowConst.appVersionLabel,
                      style: inter(
                        11.5,
                        560,
                        color: tones.textFaint,
                        spacing: 1.2,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(
    BuildContext context,
    IconData icon,
    String label, {
    required VoidCallback onTap,
    Color? color,
    String? subtitle,
  }) {
    return ListTile(
      leading: Icon(icon, size: 22, color: color),
      title: Text(
        label,
        style: inter(15, 560, color: color ?? context.scheme.onSurface),
      ),
      subtitle: subtitle == null
          ? null
          : Text(
              subtitle,
              // Two lines: these subtitles carry real information ("we answer
              // in two days", what a page covers) and at 1.3x a single line
              // kept about three words of it — every row on the screen ended
              // in an ellipsis.
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: inter(12.5, 460, color: context.tones.textFaint),
            ),
      trailing: Icon(
        Symbols.chevron_right_rounded,
        size: 20,
        color: context.tones.textFaint,
      ),
      onTap: onTap,
    );
  }

  /// Email is identity here — it is the sign-in credential — so this explains
  /// rather than edits. Changing it means re-authenticating, which is a
  /// support conversation, not a text field.
  void _openEmailSheet(BuildContext context, String email) {
    showFlowSheet<void>(
      context,
      title: 'Email address',
      subtitle: email.isEmpty ? null : email,
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'This is the address you sign in with, and where we send '
              'anything that has to reach you outside the app.',
              style: Theme.of(
                sheetContext,
              ).textTheme.bodyMedium!.copyWith(height: 1.55),
            ),
            const SizedBox(height: 20),
            PrimaryButton(
              label: 'Ask support to change it',
              icon: Symbols.support_agent_rounded,
              onPressed: () {
                Navigator.pop(sheetContext);
                context.push('/support');
              },
            ),
          ],
        ),
      ),
    );
  }

  /// Honest about where the switch actually lives.
  ///
  /// An in-app toggle here would be a lie in one direction or the other: the
  /// OS owns the permission, so a switch turned "on" while Android has push
  /// denied would silently promise notifications that never arrive.
  void _openPushSheet(BuildContext context) {
    showFlowSheet<void>(
      context,
      title: 'Push notifications',
      subtitle: 'Booking updates, messages and reminders',
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Android owns this permission, so it is switched on and off in '
              'your phone settings — Settings → Apps → FLOW → Notifications. '
              'Turning them off there does not affect the notification inbox '
              'in the app; nothing is lost, it just waits for you.',
              style: Theme.of(
                sheetContext,
              ).textTheme.bodyMedium!.copyWith(height: 1.55),
            ),
          ],
        ),
      ),
    );
  }

  void _openHowItWorksSheet(BuildContext context, bool isTrainer) {
    showFlowSheet<void>(
      context,
      title: 'How FLOW works',
      builder: (sheetContext) => ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 28),
        children: isTrainer
            ? const [
                _PrivacyItem(
                  icon: Symbols.pending_actions_rounded,
                  title: 'Requests come to you',
                  body:
                      'Every booking arrives as a request. Nothing lands on '
                      'your calendar until you approve it, and declining is '
                      'always allowed — with a reason if you want to give one.',
                ),
                _PrivacyItem(
                  icon: Symbols.qr_code_scanner_rounded,
                  title: 'Scan them in',
                  body:
                      'Your rider shows a QR ticket on the beach. Scanning it '
                      'starts the session — that is what proves they turned '
                      'up, and it is the only way a session becomes billable.',
                ),
                _PrivacyItem(
                  icon: Symbols.payments_rounded,
                  title: 'You are paid through FLOW',
                  body:
                      'Riders pay FLOW when they book, and FLOW pays you '
                      'after each completed session. A late cancellation '
                      '(inside 24 hours) is still paid out — the policy '
                      'protects your committed hours.',
                ),
              ]
            : const [
                _PrivacyItem(
                  icon: Symbols.event_available_rounded,
                  title: 'Request, then confirm',
                  body:
                      'You pick hours and send a request. Your trainer '
                      'approves it — you are notified either way, and nothing '
                      'is owed until a session actually happens.',
                ),
                _PrivacyItem(
                  icon: Symbols.confirmation_number_rounded,
                  title: 'Your ticket is your check-in',
                  body:
                      'Confirmed sessions get a QR ticket in the Ticket tab. '
                      'Your trainer scans it on the beach to start the '
                      'session. No signal needed on your side.',
                ),
                _PrivacyItem(
                  icon: Symbols.payments_rounded,
                  title: 'Pay when you book',
                  body:
                      'Prices are in euros. You pay FLOW at booking and your '
                      'trainer is paid after the session. Free cancellation '
                      'until 24 hours before the start; declined or '
                      'unanswered requests are always refunded in full.',
                ),
              ],
      ),
    );
  }

  void _openTermsSheet(BuildContext context) {
    showFlowSheet<void>(
      context,
      title: 'Terms & conditions',
      builder: (sheetContext) => ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 28),
        children: const [
          _PrivacyItem(
            icon: Symbols.handshake_rounded,
            title: 'FLOW introduces, it does not instruct',
            body:
                'Every lesson is an agreement between you and your trainer. '
                'FLOW lists certified trainers and handles the booking; the '
                'session itself, and the money for it, are between the two '
                'of you.',
          ),
          _PrivacyItem(
            icon: Symbols.verified_user_rounded,
            title: 'Certification is checked by hand',
            body:
                'Every trainer on FLOW has had their IKO or VDWS credential '
                'reviewed by a person before appearing in Explore. Report '
                'anyone whose conduct does not match that standard.',
          ),
          _PrivacyItem(
            icon: Symbols.waves_rounded,
            title: 'The sea decides',
            body:
                'Wind forecasts are indicative. A trainer may cancel for '
                'safety, and should — conditions on the Red Sea change '
                'faster than any forecast does.',
          ),
        ],
      ),
    );
  }

  /// Where account deletion now lives.
  ///
  /// It used to be a top-level "Danger zone" row directly under Sign out —
  /// the two most different actions on the screen, adjacent, with the
  /// irreversible one second. This puts a sheet between the list and the
  /// deed, so reaching it is deliberate rather than a mis-tap.
  void _openAccountSheet(BuildContext context, WidgetRef ref) {
    showFlowSheet<void>(
      context,
      title: 'Manage my account',
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _PrivacyItem(
              icon: Symbols.download_rounded,
              title: 'A copy of your data',
              body:
                  'Ask support for everything FLOW holds about you and we '
                  'send it to your sign-in address.',
            ),
            OutlinedButton.icon(
              onPressed: () {
                Navigator.pop(sheetContext);
                context.push('/support');
              },
              icon: const Icon(Symbols.download_rounded, size: 18),
              label: const Text('Request my data'),
            ),
            const SizedBox(height: 28),
            Text(
              'Delete my account',
              style: inter(15, 700, color: context.tones.danger),
            ),
            const SizedBox(height: 6),
            Text(
              'Permanently removes your profile, favourites and history. '
              'Your past sessions stay on your trainers’ records, because '
              'they are their books too. This cannot be undone.',
              style: Theme.of(
                sheetContext,
              ).textTheme.bodyMedium!.copyWith(height: 1.55),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: context.tones.danger,
                  side: BorderSide(
                    color: context.tones.danger.withValues(alpha: .5),
                  ),
                ),
                onPressed: () {
                  Navigator.pop(sheetContext);
                  _deleteAccountFlow(context, ref);
                },
                icon: const Icon(Symbols.delete_forever_rounded, size: 18),
                label: const Text('Delete my account'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// "Security & data" explainer (§3.13).
  void _openPrivacySheet(BuildContext context) {
    showFlowSheet<void>(
      context,
      title: 'Security & data',
      builder: (sheetContext) => ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 28),
        children: const [
          _PrivacyItem(
            icon: Symbols.lock_outline_rounded,
            title: 'Your session is encrypted',
            body:
                'Sign-in is handled by Firebase Authentication over TLS. FLOW '
                'never stores your password — not on the device, not anywhere.',
          ),
          _PrivacyItem(
            icon: Symbols.visibility_rounded,
            title: 'What trainers see',
            body:
                'When you book, your trainer sees your name, kite level and '
                'the message you attach — enough to prep your session, nothing more.',
          ),
          _PrivacyItem(
            icon: Symbols.photo_rounded,
            title: 'Your photos',
            body:
                'Profile and gallery photos are stored in Firebase Storage and '
                'downscaled before upload. Delete your account and your profile '
                'data goes with it.',
          ),
        ],
      ),
    );
  }

  /// Danger zone: destructive confirm → leave-reason sheet → heavy haptic →
  /// blocking overlay (§3.13, §10.4).
  Future<void> _deleteAccountFlow(BuildContext context, WidgetRef ref) async {
    final sure = await confirmAction(
      context,
      title: 'Delete your account?',
      body:
          'This permanently removes your profile, favourites and history. '
          'This cannot be undone.',
      confirmLabel: 'Delete forever',
      cancelLabel: 'Keep my account',
      destructive: true,
    );
    if (!sure || !context.mounted) return;

    final reason = TextEditingController();
    final confirmed = await showFlowSheet<bool>(
      context,
      title: 'Before you go…',
      subtitle: 'Why are you leaving? It genuinely helps.',
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: reason,
              maxLines: 3,
              decoration: const InputDecoration(
                hintText: 'Too few trainers? Moving on? Something broke?',
              ),
            ),
            const SizedBox(height: 16),
            PrimaryButton(
              label: 'Delete my account',
              destructive: true,
              onPressed: () => Navigator.pop(sheetContext, true),
            ),
            TextButton(
              onPressed: () => Navigator.pop(sheetContext, false),
              child: const Text('Never mind'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !context.mounted) {
      reason.dispose();
      return;
    }

    // Checked *before* the profile is touched. The auth deletion below is the
    // step that fails on a stale session, but the profile is deleted first
    // and cannot be restored (the rules forbid re-creating a business
    // account as anything but `pending`). Refusing early leaves the account
    // intact; letting it through would strand a signed-in user with no
    // profile and no way back.
    if (ref.read(authRepositoryProvider).needsReauthForDeletion) {
      showFlowToast(
        context,
        'For your security, sign out and sign back in before deleting your account.',
      );
      reason.dispose();
      return;
    }

    Haptics.heavy();
    try {
      await withBusyOverlay(context, label: 'Deleting your account…', () async {
        final session = ref.read(sessionProvider);
        final support = ref.read(supportRepositoryProvider);
        // Record the reason, delete the Firestore profile, then the auth user.
        await support.recordLeaveReason(
          userId: session.uid,
          userName: session.displayName,
          userEmail: session.user?.email ?? '',
          reason: reason.text.trim().isEmpty
              ? 'No reason given'
              : reason.text.trim(),
        );
        await ref.read(userRepositoryProvider).deleteProfile(session.uid);
        await ref.read(authRepositoryProvider).deleteAccount();
      });
    } on AuthFailure catch (e) {
      if (context.mounted) showFlowToast(context, e.message);
    } catch (_) {
      if (context.mounted) {
        showFlowToast(
          context,
          "Couldn't delete your account. Try again later.",
        );
      }
    } finally {
      reason.dispose();
    }
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    // A `Material` for the fill, an `Ink` for the outline — deliberately not
    // the `Container` this was, and deliberately not `FlowCard` either.
    //
    // A `ListTile` paints its splash on the nearest `Material` ancestor. With
    // an opaque `Container` in between, every ripple on this card was drawn
    // *behind* that background and never seen: the whole settings list — which
    // is nothing but tappable rows — gave no touch feedback at all. Flutter
    // asserts about this in debug, and the assertion only surfaced once the
    // app was actually driven; no widget test renders this screen.
    //
    // `Ink` paints its decoration onto the Material rather than stacking a
    // DecoratedBox above it, so the border survives without hiding anything.
    // `clipBehavior` keeps the first and last row's splash inside the radius.
    return Material(
      color: context.tones.card,
      borderRadius: FlowRadii.card,
      clipBehavior: Clip.antiAlias,
      child: Ink(
        decoration: BoxDecoration(
          borderRadius: FlowRadii.card,
          border: Border.all(color: context.tones.line),
        ),
        child: Column(children: children),
      ),
    );
  }
}

class _PrivacyItem extends StatelessWidget {
  const _PrivacyItem({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FlowIconChip(icon: icon, size: 42),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(
                  body,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium!.copyWith(height: 1.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

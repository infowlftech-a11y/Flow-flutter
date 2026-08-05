import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/typography.dart';
import '../../core/utils/haptics.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/flow_image.dart';
import '../../core/widgets/misc.dart';
import '../../core/widgets/sheets.dart';
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
    final themeMode = ref.watch(themeModeProvider);
    final tones = context.tones;

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
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
                        size: 76),
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        padding: const EdgeInsets.all(5),
                        decoration: BoxDecoration(
                          color: tones.azureBrand,
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: Theme.of(context)
                                  .scaffoldBackgroundColor,
                              width: 2),
                        ),
                        child: const Icon(Icons.edit_rounded,
                            size: 12, color: Colors.white),
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
                    Text(session.displayName,
                        style: Theme.of(context).textTheme.headlineMedium),
                    const SizedBox(height: 2),
                    Text(user?.email ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        TagPill(session.isTrainer
                            ? 'TRAINER'
                            : (user?.level ?? 'RIDER').toUpperCase()),
                        if (user?.nationality != null)
                          TagPill(user!.nationality!,
                              color: tones.textFaint),
                        if ((user?.location ?? user?.homeSpot) != null)
                          TagPill(user!.location ?? user.homeSpot!,
                              icon: Icons.place_outlined,
                              color: tones.textFaint),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (session.isStaff) ...[
            const SizedBox(height: 28),
            const SectionHeader('Staff'),
            _SettingsCard(children: [
              Builder(builder: (context) {
                final queue = ref.watch(adminQueueCountProvider);
                return ListTile(
                  leading: Icon(Icons.shield_moon_outlined,
                      size: 22, color: tones.azureBrand),
                  title: Text('Admin console',
                      style: inter(15, 620, color: context.scheme.onSurface)),
                  subtitle: const Text('Approvals, reports and appeals'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (queue > 0)
                        Badge.count(count: queue)
                      else
                        const SizedBox.shrink(),
                      Icon(Icons.chevron_right_rounded,
                          size: 20, color: tones.textFaint),
                    ],
                  ),
                  onTap: () => context.push('/admin'),
                );
              }),
            ]),
          ],
          const SizedBox(height: 28),
          const SectionHeader('Account'),
          _SettingsCard(children: [
            _row(context, Icons.badge_outlined, 'Personal details',
                onTap: () => context.push('/profile/edit')),
            if (session.isTrainer)
              _row(context, Icons.visibility_outlined,
                  'View my public profile',
                  onTap: () => context.push('/trainer/${session.uid}')),
            _row(context, Icons.notifications_outlined, 'Notifications',
                onTap: () => context.push('/notifications')),
            _row(context, Icons.support_agent_rounded, 'Help & support',
                onTap: () => context.push('/support')),
          ]),
          const SizedBox(height: 20),
          const SectionHeader('Appearance'),
          _SettingsCard(children: [
            Padding(
              padding: const EdgeInsets.all(6),
              child: SegmentedButton<ThemeMode>(
                segments: const [
                  ButtonSegment(
                      value: ThemeMode.system,
                      icon: Icon(Icons.brightness_auto_rounded, size: 18),
                      label: Text('Auto')),
                  ButtonSegment(
                      value: ThemeMode.light,
                      icon: Icon(Icons.light_mode_rounded, size: 18),
                      label: Text('Light')),
                  ButtonSegment(
                      value: ThemeMode.dark,
                      icon: Icon(Icons.dark_mode_rounded, size: 18),
                      label: Text('Dark')),
                ],
                selected: {themeMode},
                onSelectionChanged: (s) {
                  Haptics.select();
                  ref.read(themeModeProvider.notifier).set(s.first);
                },
                style: ButtonStyle(
                  side: WidgetStatePropertyAll(
                      BorderSide(color: tones.line)),
                ),
              ),
            ),
          ]),
          const SizedBox(height: 20),
          const SectionHeader('Privacy'),
          _SettingsCard(children: [
            _row(context, Icons.shield_outlined, 'Security & data',
                onTap: () => _openPrivacySheet(context)),
          ]),
          const SizedBox(height: 20),
          _SettingsCard(children: [
            _row(context, Icons.logout_rounded, 'Sign out', onTap: () async {
              final ok = await confirmAction(
                context,
                title: 'Sign out?',
                body: "You'll need your email and password to get back in.",
                confirmLabel: 'Sign out',
              );
              if (ok) await ref.read(signOutProvider)();
            }),
          ]),
          const SizedBox(height: 28),
          const SectionHeader('Danger zone'),
          _SettingsCard(children: [
            _row(context, Icons.delete_forever_outlined, 'Delete my account',
                color: tones.danger,
                onTap: () => _deleteAccountFlow(context, ref)),
          ]),
          const SizedBox(height: 24),
          Center(
            child: Text(FlowConst.appVersionLabel,
                style: inter(11.5, 560,
                    color: tones.textFaint, spacing: 1.2)),
          ),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, IconData icon, String label,
      {required VoidCallback onTap, Color? color}) {
    return ListTile(
      leading: Icon(icon, size: 22, color: color),
      title: Text(label,
          style: inter(15, 560, color: color ?? context.scheme.onSurface)),
      trailing: Icon(Icons.chevron_right_rounded,
          size: 20, color: context.tones.textFaint),
      onTap: onTap,
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
            icon: Icons.lock_outline_rounded,
            title: 'Your session is encrypted',
            body:
                'Sign-in is handled by Firebase Authentication over TLS. FLOW '
                'never stores your password — not on the device, not anywhere.',
          ),
          _PrivacyItem(
            icon: Icons.visibility_outlined,
            title: 'What trainers see',
            body:
                'When you book, your trainer sees your name, kite level and '
                'the message you attach — enough to prep your session, nothing more.',
          ),
          _PrivacyItem(
            icon: Icons.photo_outlined,
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
                  hintText: 'Too few trainers? Moving on? Something broke?'),
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
      showFlowToast(context,
          'For your security, sign out and sign back in before deleting your account.');
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
            context, "Couldn't delete your account. Try again later.");
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
    return Container(
      decoration: BoxDecoration(
        color: context.tones.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: context.tones.line),
      ),
      child: Column(children: children),
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
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: context.tones.azureBrand.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(icon, size: 20, color: context.tones.azureBrand),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(body,
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium!
                        .copyWith(height: 1.5)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

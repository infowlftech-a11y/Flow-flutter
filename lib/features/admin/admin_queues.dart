import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/radii.dart';
import '../../core/theme/typography.dart';
import '../../core/utils/date_x.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/flow_image.dart';
import '../../core/widgets/misc.dart';
import '../../core/widgets/sheets.dart';
import '../../core/widgets/surfaces.dart';
import '../../data/models/app_user.dart';
import '../../data/models/support.dart';
import '../../providers/providers.dart';

/// The three staff queues that had a repository, rules and a provider — and
/// no screen at all.
///
/// Each one was a half-built feature that read as a whole one from the
/// outside. A rider could open a support ticket and be told support would be
/// in touch; nothing on the staff side could read it. `blockUser` could
/// suspend an account "until Tuesday"; `unblockUser` had no caller, so every
/// ban was permanent. Account deletion asked "why are you leaving? it
/// genuinely helps" and filed the answer where nobody could open it.
///
/// Kept beside `admin_screen.dart` rather than inside it: that file is the
/// three moderation queues and is long enough already.

// ── Support tickets (§3.14, staff half) ──────────────────────────────────

class TicketsTab extends ConsumerWidget {
  const TicketsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tickets = ref.watch(allTicketsProvider);

    return AsyncView<List<SupportTicket>>(
      value: tickets,
      onRetry: () => ref.invalidate(allTicketsProvider),
      onRefresh: () async {
        ref.invalidate(allTicketsProvider);
        await ref.read(allTicketsProvider.future);
      },
      skeleton: const SkeletonList(count: 4, itemHeight: 96),
      data: (list) {
        if (list.isEmpty) {
          return const EmptyView.scrollable(
            icon: Symbols.support_agent_rounded,
            title: 'No tickets yet',
            subtitle: 'Questions riders and trainers send you land here.',
          );
        }
        return ListView.separated(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(20),
          itemCount: list.length,
          separatorBuilder: (_, _) => const SizedBox(height: 12),
          itemBuilder: (context, i) => _TicketCard(ticket: list[i]),
        );
      },
    );
  }
}

class _TicketCard extends ConsumerWidget {
  const _TicketCard({required this.ticket});
  final SupportTicket ticket;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tones = context.tones;
    return FlowCard(
      borderColor: ticket.isOpen ? tones.warning.withValues(alpha: .4) : null,
      onTap: () => _openThread(context, ref),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(ticket.subject,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium),
              ),
              const SizedBox(width: 10),
              TagPill(ticket.isOpen ? 'OPEN' : 'CLOSED',
                  color: ticket.isOpen ? tones.warning : tones.textFaint),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            ticket.lastMessageAt == null
                ? '${ticket.userName} · no replies yet'
                : '${ticket.userName} · ${timeAgo(ticket.lastMessageAt!)}',
            style: inter(12.5, 480, color: tones.textFaint),
          ),
        ],
      ),
    );
  }

  /// The conversation, in a sheet rather than a route: staff are triaging a
  /// list, and answering one ticket should not cost them their place in it.
  void _openThread(BuildContext context, WidgetRef ref) {
    final reply = TextEditingController();
    showFlowSheet<void>(
      context,
      title: ticket.subject,
      subtitle: '${ticket.userName} · ${ticket.isOpen ? 'open' : 'closed'}',
      // No viewInsets here: showFlowSheet already pads the sheet by the
      // keyboard inset. Adding it again doubled the padding — with the
      // keyboard up that was ~600px of blank sheet, the content squeezed to
      // nothing, and "everything turns white" is exactly how that looks.
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Flexible, so when the keyboard takes the height it is the
            // thread that gives way and scrolls — never the reply field or
            // the buttons, which are what the keyboard was opened for.
            Flexible(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(sheetContext).size.height * .4),
                child: Consumer(
                  builder: (context, ref, _) {
                    final messages =
                        ref.watch(ticketMessagesProvider(ticket.id));
                    return switch (messages) {
                      AsyncData(:final value) when value.isEmpty => Text(
                          'No messages on this ticket.',
                          style:
                              inter(14, 460, color: context.tones.textFaint)),
                      // Reversed, so it opens showing the newest message —
                      // the one being replied to.
                      AsyncData(:final value) => ListView.separated(
                          shrinkWrap: true,
                          reverse: true,
                          itemCount: value.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: 10),
                          itemBuilder: (context, i) => _TicketBubble(
                              message: value[value.length - 1 - i]),
                        ),
                      AsyncError() => const Text('Could not load the thread.'),
                      _ => const Center(child: CircularProgressIndicator()),
                    };
                  },
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: reply,
              minLines: 2,
              maxLines: 5,
              decoration:
                  const InputDecoration(hintText: 'Reply as FLOW support…'),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                if (ticket.isOpen)
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () async {
                        final ok = await confirmAction(
                          sheetContext,
                          title: 'Close this ticket?',
                          body: 'They can reopen it by replying.',
                          confirmLabel: 'Close ticket',
                          cancelLabel: 'Leave open',
                        );
                        if (!ok) return;
                        await ref
                            .read(supportRepositoryProvider)
                            .closeTicket(ticket.id);
                        if (sheetContext.mounted) {
                          Navigator.pop(sheetContext);
                        }
                      },
                      // Not 'Close': next to a text field, a bare Close
                      // reads as "dismiss this sheet", and what it actually
                      // does is resolve the customer's ticket.
                      child: const FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text('Close ticket', maxLines: 1),
                      ),
                    ),
                  ),
                if (ticket.isOpen) const SizedBox(width: 12),
                Expanded(
                  child: PrimaryButton(
                    label: 'Send reply',
                    onPressed: () async {
                      final text = reply.text.trim();
                      if (text.isEmpty) return;
                      await ref.read(supportRepositoryProvider).replyAsStaff(
                            ticketId: ticket.id,
                            staffId: ref.read(sessionProvider).uid,
                            text: text,
                          );
                      if (sheetContext.mounted) Navigator.pop(sheetContext);
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ).whenComplete(reply.dispose);
  }
}

class _TicketBubble extends StatelessWidget {
  const _TicketBubble({required this.message});
  final TicketMessage message;

  @override
  Widget build(BuildContext context) {
    final tones = context.tones;
    final staff = message.fromStaff;
    return Align(
      alignment: staff ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints:
            BoxConstraints(maxWidth: MediaQuery.of(context).size.width * .68),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: staff ? tones.azureBrand.withValues(alpha: .14) : tones.card,
          borderRadius: FlowRadii.inset,
          border: Border.all(color: tones.line),
        ),
        child: Column(
          crossAxisAlignment:
              staff ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Text(message.text,
                style: inter(14, 460,
                    color: context.scheme.onSurface, height: 1.45)),
            if (message.createdAt != null) ...[
              const SizedBox(height: 3),
              Text(timeAgo(message.createdAt!),
                  style: inter(11, 500, color: tones.textFaint)),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Suspensions ──────────────────────────────────────────────────────────

class SuspendedTab extends ConsumerWidget {
  const SuspendedTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final blocked = ref.watch(blockedUsersProvider);

    return AsyncView<List<AppUser>>(
      value: blocked,
      onRetry: () => ref.invalidate(blockedUsersProvider),
      onRefresh: () async {
        ref.invalidate(blockedUsersProvider);
        await ref.read(blockedUsersProvider.future);
      },
      skeleton: const SkeletonList(count: 3, itemHeight: 108),
      data: (list) {
        if (list.isEmpty) {
          return const EmptyView.scrollable(
            icon: Symbols.lock_open_rounded,
            title: 'Nobody is suspended',
            subtitle: 'Suspended accounts appear here so a ban can be lifted.',
          );
        }
        return ListView.separated(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(20),
          itemCount: list.length,
          separatorBuilder: (_, _) => const SizedBox(height: 12),
          itemBuilder: (context, i) => _SuspendedCard(user: list[i]),
        );
      },
    );
  }
}

class _SuspendedCard extends ConsumerWidget {
  const _SuspendedCard({required this.user});
  final AppUser user;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tones = context.tones;
    return FlowCard(
      borderColor: tones.danger.withValues(alpha: .4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              FlowAvatar(url: user.photoUrl, name: user.name, size: 44),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(user.name,
                        style: Theme.of(context).textTheme.titleMedium),
                    Text(user.email,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: inter(12.5, 480, color: tones.textFaint)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              TagPill(
                  user.isPermanentlyBlocked
                      ? 'PERMANENT'
                      : 'UNTIL ${user.blockedUntilRaw ?? '—'}',
                  icon: Symbols.gavel_rounded,
                  color: tones.danger),
              TagPill(user.isTrainer ? 'TRAINER' : 'RIDER'),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: MicroAction(
              label: 'LIFT SUSPENSION',
              icon: Symbols.lock_open_rounded,
              color: tones.success,
              onPressed: () => _lift(context, ref),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _lift(BuildContext context, WidgetRef ref) async {
    final ok = await confirmAction(
      context,
      title: 'Lift the suspension on ${user.name}?',
      body: 'They get their account back exactly as it was before the ban, '
          'and are told it was lifted.',
      confirmLabel: 'Lift suspension',
      cancelLabel: 'Keep suspended',
    );
    if (!ok) return;
    try {
      await ref.read(adminRepositoryProvider).unblockUser(user.uid);
      if (context.mounted) showFlowToast(context, '${user.name} is back');
    } catch (_) {
      if (context.mounted) {
        showFlowToast(context, "Couldn't lift it. Try again.");
      }
    }
  }
}

// ── Leave reasons (§3.13) ────────────────────────────────────────────────

class LeaveReasonsTab extends ConsumerWidget {
  const LeaveReasonsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reasons = ref.watch(leaveReasonsProvider);

    return AsyncView<List<LeaveReason>>(
      value: reasons,
      onRetry: () => ref.invalidate(leaveReasonsProvider),
      onRefresh: () async {
        ref.invalidate(leaveReasonsProvider);
        await ref.read(leaveReasonsProvider.future);
      },
      skeleton: const SkeletonList(count: 4, itemHeight: 96),
      data: (list) {
        if (list.isEmpty) {
          return const EmptyView.scrollable(
            icon: Symbols.waving_hand_rounded,
            title: 'Nobody has left yet',
            subtitle: 'When someone deletes their account, what they tell us '
                'on the way out shows up here.',
          );
        }
        return ListView.separated(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(20),
          itemCount: list.length,
          separatorBuilder: (_, _) => const SizedBox(height: 12),
          itemBuilder: (context, i) => _LeaveReasonCard(reason: list[i]),
        );
      },
    );
  }
}

class _LeaveReasonCard extends StatelessWidget {
  const _LeaveReasonCard({required this.reason});
  final LeaveReason reason;

  @override
  Widget build(BuildContext context) {
    final tones = context.tones;
    return FlowCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(reason.userName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium),
              ),
              if (reason.createdAt != null)
                Text(timeAgo(reason.createdAt!),
                    style: inter(12, 500, color: tones.textFaint)),
            ],
          ),
          if (reason.userEmail.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(reason.userEmail,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: inter(12.5, 480, color: tones.textFaint)),
          ],
          const SizedBox(height: 10),
          Text(
            reason.isBlank ? 'They left without saying why.' : reason.reason,
            style: reason.isBlank
                ? inter(14, 440, color: tones.textFaint, height: 1.45)
                : inter(14.5, 460,
                    color: context.scheme.onSurface, height: 1.5),
          ),
        ],
      ),
    );
  }
}

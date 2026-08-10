import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/typography.dart';
import '../../core/utils/date_x.dart';
import '../../core/utils/haptics.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/flow_image.dart';
import '../../core/widgets/media.dart';
import '../../core/widgets/misc.dart';
import '../../core/widgets/surfaces.dart';
import '../../core/widgets/sheets.dart';
import '../../data/models/app_user.dart';
import '../../data/models/report.dart';
import '../../data/models/support.dart';
import '../../providers/providers.dart';

/// Staff moderation console (§14.2, ported in-app).
///
/// Trainer approval is the load-bearing tab: Explore only shows
/// `role == 'business' && status == 'active'`, so until someone approves an
/// applicant here the marketplace has no supply at all.
class AdminScreen extends ConsumerWidget {
  const AdminScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Defence in depth: the entry point is staff-gated, the route is gated,
    // and Firestore rules gate the writes.
    if (!ref.watch(sessionProvider).isStaff) {
      return Scaffold(
        appBar: AppBar(title: const Text('Admin')),
        body: EmptyView(
          icon: Symbols.lock_outline_rounded,
          title: 'Staff only',
          subtitle: 'This console is limited to admin and support accounts.',
          action: OutlinedButton(
              onPressed: () => context.pop(), child: const Text('Go back')),
        ),
      );
    }

    final pending = ref.watch(pendingTrainersProvider).value ?? const [];
    final reports = ref.watch(reportsProvider).value ?? const [];
    final appeals = ref.watch(appealsProvider).value ?? const [];
    final openReports = reports.where((r) => r.isOpen).length;
    final openAppeals = appeals.where((a) => a.status == 'pending').length;

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Admin console'),
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(text: 'APPROVALS${pending.isEmpty ? '' : ' (${pending.length})'}'),
              Tab(text: 'REPORTS${openReports == 0 ? '' : ' ($openReports)'}'),
              Tab(text: 'APPEALS${openAppeals == 0 ? '' : ' ($openAppeals)'}'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [_ApprovalsTab(), _ReportsTab(), _AppealsTab()],
        ),
      ),
    );
  }
}

// ── Approvals ────────────────────────────────────────────────────────────

class _ApprovalsTab extends ConsumerWidget {
  const _ApprovalsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pending = ref.watch(pendingTrainersProvider);

    return AsyncView<List<AppUser>>(
      value: pending,
      onRetry: () => ref.invalidate(pendingTrainersProvider),
      onRefresh: () async {
        ref.invalidate(pendingTrainersProvider);
        await ref.read(pendingTrainersProvider.future);
      },
      skeleton: const SkeletonList(count: 4, itemHeight: 132),
      data: (list) {
        if (list.isEmpty) {
          return const EmptyView.scrollable(
            icon: Symbols.verified_rounded,
            title: 'No applications waiting',
            subtitle:
                'New trainer sign-ups land here for certification review.',
          );
        }
        return ListView.separated(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(20),
          itemCount: list.length,
          separatorBuilder: (_, _) => const SizedBox(height: 12),
          itemBuilder: (context, i) => _ApplicantCard(trainer: list[i]),
        );
      },
    );
  }
}

class _ApplicantCard extends ConsumerStatefulWidget {
  const _ApplicantCard({required this.trainer});
  final AppUser trainer;

  @override
  ConsumerState<_ApplicantCard> createState() => _ApplicantCardState();
}

class _ApplicantCardState extends ConsumerState<_ApplicantCard> {
  bool _busy = false;

  Future<void> _approve() async {
    if (_busy) return;
    setState(() => _busy = true);
    final repo = ref.read(adminRepositoryProvider);
    try {
      Haptics.medium();
      await repo.approveTrainer(widget.trainer);
      if (mounted) {
        showFlowToast(
          context,
          '${widget.trainer.name} is live',
          undoLabel: 'UNDO',
          onUndo: () => repo.restoreToPending(widget.trainer.uid).ignore(),
        );
      }
    } catch (_) {
      if (mounted) showFlowToast(context, "Couldn't approve. Try again.");
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reject() async {
    if (_busy) return;
    final reason = TextEditingController();
    final confirmed = await showFlowSheet<bool>(
      context,
      title: 'Decline ${widget.trainer.name}?',
      subtitle: 'They are told the outcome, and the reason if you give one.',
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: reason,
              maxLines: 3,
              minLines: 2,
              decoration: const InputDecoration(
                  hintText:
                      'Reason (optional) — e.g. "Certification ID could not be verified"'),
            ),
            const SizedBox(height: 16),
            PrimaryButton(
              label: 'Decline application',
              destructive: true,
              onPressed: () => Navigator.pop(sheetContext, true),
            ),
            TextButton(
              onPressed: () => Navigator.pop(sheetContext, false),
              child: const Text('Keep pending'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) {
      reason.dispose();
      return;
    }
    setState(() => _busy = true);
    try {
      await ref
          .read(adminRepositoryProvider)
          .rejectTrainer(widget.trainer, reason: reason.text);
      if (mounted) showFlowToast(context, 'Application declined');
    } catch (_) {
      if (mounted) showFlowToast(context, "Couldn't decline. Try again.");
    } finally {
      reason.dispose();
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.trainer;
    final tones = context.tones;

    return FlowCard(
      borderColor: tones.warning.withValues(alpha: .4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              FlowAvatar(url: t.photoUrl, name: t.name, size: 48),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t.name,
                        style: Theme.of(context).textTheme.titleMedium),
                    Text(t.email,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: inter(12.5, 480, color: tones.textFaint)),
                  ],
                ),
              ),
              Text('${euro(t.displayRate)}/h',
                  style: interNum(14, 720, color: tones.azureBrand)),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              TagPill(t.ikoId == null ? 'NO IKO ID' : 'IKO ${t.ikoId}',
                  icon: Symbols.workspace_premium_rounded,
                  color: t.ikoId == null ? tones.danger : null),
              if (t.location != null)
                TagPill(t.location!, icon: Symbols.place_rounded),
              for (final lang in t.languages.take(3)) TagPill(lang),
            ],
          ),
          if ((t.bio ?? '').isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(t.bio!,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium!
                    .copyWith(height: 1.45)),
          ],
          const SizedBox(height: 12),
          // The whole point of review: look at the certificate.
          Row(
            children: [
              Expanded(
                child: MicroAction(
                  label: t.certificateUrl == null
                      ? 'NO CERTIFICATE'
                      : 'VIEW CERTIFICATE',
                  icon: Symbols.description_rounded,
                  filled: false,
                  color: t.certificateUrl == null ? tones.textFaint : null,
                  onPressed: t.certificateUrl == null
                      ? null
                      : () => _openCertificate(context, t),
                ),
              ),
              const SizedBox(width: 10),
              MicroAction(
                label: 'PROFILE',
                filled: false,
                onPressed: () => context.push('/trainer/${t.uid}'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: MicroAction(
                  label: 'DECLINE',
                  filled: false,
                  color: tones.danger,
                  onPressed: _busy ? null : _reject,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: MicroAction(
                  label: _busy ? '…' : 'APPROVE',
                  icon: Symbols.check_rounded,
                  onPressed: _busy ? null : _approve,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _openCertificate(BuildContext context, AppUser trainer) =>
      showFullScreenImages(context, [trainer.certificateUrl]);
}

// ── Reports ──────────────────────────────────────────────────────────────

class _ReportsTab extends ConsumerWidget {
  const _ReportsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reports = ref.watch(reportsProvider);

    return AsyncView<List<Report>>(
      value: reports,
      onRetry: () => ref.invalidate(reportsProvider),
      onRefresh: () async {
        ref.invalidate(reportsProvider);
        await ref.read(reportsProvider.future);
      },
      skeleton: const SkeletonList(count: 4, itemHeight: 110),
      data: (list) {
        if (list.isEmpty) {
          return const EmptyView.scrollable(
            icon: Symbols.flag_rounded,
            title: 'No reports',
            subtitle: 'Rider reports about trainers appear here.',
          );
        }
        return ListView.separated(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(20),
          itemCount: list.length,
          separatorBuilder: (_, _) => const SizedBox(height: 12),
          itemBuilder: (context, i) => _ReportCard(report: list[i]),
        );
      },
    );
  }
}

class _ReportCard extends ConsumerWidget {
  const _ReportCard({required this.report});
  final Report report;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tones = context.tones;
    return FlowCard(
      borderColor:
          report.isOpen ? tones.danger.withValues(alpha: .4) : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(report.reason,
                    style: Theme.of(context).textTheme.titleMedium),
              ),
              TagPill(report.status.toUpperCase(),
                  color: report.isOpen ? tones.danger : tones.textFaint),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${report.reporterName} → ${report.reportedUserName} · ${timeAgo(report.createdAt)}',
            style: inter(12.5, 500, color: tones.textFaint),
          ),
          if ((report.details ?? '').isNotEmpty) ...[
            const SizedBox(height: 10),
            Text('"${report.details}"',
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium!
                    .copyWith(fontStyle: FontStyle.italic, height: 1.45)),
          ],
          if (report.attachments.isNotEmpty) ...[
            const SizedBox(height: 10),
            SizedBox(
              height: 64,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: report.attachments.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (_, i) => FlowImage(
                  url: report.attachments[i],
                  width: 64,
                  height: 64,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: MicroAction(
                  label: 'VIEW TRAINER',
                  filled: false,
                  onPressed: () =>
                      context.push('/trainer/${report.reportedUserId}'),
                ),
              ),
              if (report.isOpen) ...[
                const SizedBox(width: 10),
                Expanded(
                  child: MicroAction(
                    label: 'RESOLVE',
                    onPressed: () => _openResolveSheet(context, ref),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  void _openResolveSheet(BuildContext context, WidgetRef ref) {
    final note = TextEditingController();
    showFlowSheet<void>(
      context,
      title: 'Resolve report',
      subtitle: 'Suspending is reversible from the Appeals tab.',
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: note,
              maxLines: 2,
              decoration:
                  const InputDecoration(hintText: 'Internal note (optional)'),
            ),
            const SizedBox(height: 16),
            PrimaryButton(
              label: 'Uphold & suspend 7 days',
              destructive: true,
              onPressed: () async {
                final admin = ref.read(adminRepositoryProvider);
                // Full timestamp, not a bare `ymd`. A date-only value parses
                // to midnight *starting* that day, so a suspension issued at
                // 18:00 expired after 6 days and 6 hours — visible now that
                // the gate actually enforces blockedUntil. `DateTime.tryParse`
                // reads both forms, and prettyYmd still renders the date part.
                final until =
                    DateTime.now().add(const Duration(days: 7)).toIso8601String();
                await admin.blockUser(report.reportedUserId, until: until);
                await admin.closeReport(report.id,
                    upheld: true, note: note.text);
                if (sheetContext.mounted) Navigator.pop(sheetContext);
                if (context.mounted) {
                  showFlowToast(context,
                      '${report.reportedUserName} suspended until ${prettyYmd(until)}');
                }
              },
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () async {
                await ref
                    .read(adminRepositoryProvider)
                    .closeReport(report.id, upheld: false, note: note.text);
                if (sheetContext.mounted) Navigator.pop(sheetContext);
                if (context.mounted) {
                  showFlowToast(context, 'Report dismissed');
                }
              },
              child: const Text('Dismiss — no action needed'),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Appeals ──────────────────────────────────────────────────────────────

class _AppealsTab extends ConsumerWidget {
  const _AppealsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appeals = ref.watch(appealsProvider);

    return AsyncView<List<Appeal>>(
      value: appeals,
      onRetry: () => ref.invalidate(appealsProvider),
      onRefresh: () async {
        ref.invalidate(appealsProvider);
        await ref.read(appealsProvider.future);
      },
      skeleton: const SkeletonList(count: 3, itemHeight: 120),
      data: (list) {
        if (list.isEmpty) {
          return const EmptyView.scrollable(
            icon: Symbols.gavel_rounded,
            title: 'No appeals',
            subtitle: 'Suspended users can appeal, and it lands here.',
          );
        }
        return ListView.separated(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(20),
          itemCount: list.length,
          separatorBuilder: (_, _) => const SizedBox(height: 12),
          itemBuilder: (context, i) => _AppealCard(appeal: list[i]),
        );
      },
    );
  }
}

class _AppealCard extends ConsumerStatefulWidget {
  const _AppealCard({required this.appeal});
  final Appeal appeal;

  @override
  ConsumerState<_AppealCard> createState() => _AppealCardState();
}

class _AppealCardState extends ConsumerState<_AppealCard> {
  final _reply = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _reply.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _reply.text.trim();
    if (text.isEmpty || _busy) return;
    setState(() => _busy = true);
    final session = ref.read(sessionProvider);
    try {
      await ref.read(adminRepositoryProvider).replyToAppeal(
            widget.appeal.id,
            AppealMessage(
              id: DateTime.now().millisecondsSinceEpoch.toString(),
              senderId: session.uid,
              senderName: 'Flow Support',
              text: text,
              timestamp: DateTime.now(),
            ),
          );
      Haptics.light();
      _reply.clear();

      // Bumping the status is a follow-up to a reply that has already
      // committed, so it needs its own guard. Sharing the outer catch meant a
      // failure here restored the text and reported "Couldn't send" for a
      // message that actually landed — and resending appends a second copy,
      // because each AppealMessage carries a fresh id and timestamp, so
      // arrayUnion's value-equality dedupe never matches.
      //
      // 'resolved' is terminal: a follow-up note sent after LIFT SUSPENSION
      // must not drag the appeal back to 'reviewed', which would re-show the
      // lift button on an account whose block was already lifted and flip the
      // user's badge from RESOLVED back to REVIEWED.
      if (widget.appeal.status != 'resolved') {
        try {
          await ref
              .read(adminRepositoryProvider)
              .setAppealStatus(widget.appeal.id, 'reviewed');
        } catch (_) {
          // The reply is the part that matters; the queue badge catches up on
          // the next staff action rather than lying about a failed send.
        }
      }
    } catch (_) {
      if (mounted) {
        _reply.text = text;
        showFlowToast(context, "Couldn't send. Your reply is back below.");
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _lift() async {
    final ok = await confirmAction(
      context,
      title: 'Lift this suspension?',
      body:
          '${widget.appeal.userName} regains full access immediately and is '
          'notified.',
      confirmLabel: 'Lift suspension',
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      final admin = ref.read(adminRepositoryProvider);
      await admin.unblockUser(widget.appeal.userId);
      await admin.setAppealStatus(widget.appeal.id, 'resolved');
      if (mounted) showFlowToast(context, 'Suspension lifted');
    } catch (_) {
      if (mounted) showFlowToast(context, "Couldn't lift it. Try again.");
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.appeal;
    final tones = context.tones;
    final statusColor = switch (a.status) {
      'resolved' => tones.success,
      'reviewed' => tones.azureBrand,
      _ => tones.warning,
    };

    return FlowCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(a.userName,
                    style: Theme.of(context).textTheme.titleMedium),
              ),
              TagPill(a.status.toUpperCase(), color: statusColor),
            ],
          ),
          const SizedBox(height: 4),
          Text(timeAgo(a.createdAt),
              style: inter(11.5, 500, color: tones.textFaint)),
          const SizedBox(height: 10),
          Text(a.reason,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium!
                  .copyWith(height: 1.5)),
          if (a.attachments.isNotEmpty) ...[
            const SizedBox(height: 10),
            SizedBox(
              height: 64,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: a.attachments.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (_, i) => FlowImage(
                  url: a.attachments[i],
                  width: 64,
                  height: 64,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ],
          if (a.messages.isNotEmpty) ...[
            const SizedBox(height: 12),
            for (final m in a.messages)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      m.senderId == a.userId
                          ? Symbols.person_outline_rounded
                          : Symbols.support_agent_rounded,
                      size: 16,
                      color: tones.textFaint,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(m.text,
                          style: inter(14, 460,
                              color: context.scheme.onSurfaceVariant,
                              height: 1.45)),
                    ),
                  ],
                ),
              ),
          ],
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  controller: _reply,
                  enabled: !_busy,
                  minLines: 1,
                  maxLines: 3,
                  decoration:
                      const InputDecoration(hintText: 'Reply as support…'),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                onPressed: _busy ? null : _send,
                tooltip: 'Send reply',
                icon: const Icon(Symbols.send_rounded, size: 20),
              ),
            ],
          ),
          if (a.status != 'resolved') ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: MicroAction(
                label: 'LIFT SUSPENSION',
                icon: Symbols.lock_open_rounded,
                color: tones.success,
                onPressed: _busy ? null : _lift,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/typography.dart';
import '../../core/utils/date_x.dart';
import '../../core/utils/haptics.dart';
import '../../core/utils/refs.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/misc.dart';
import '../../core/widgets/sheets.dart';
import '../../core/widgets/surfaces.dart';
import '../../core/widgets/thread.dart';
import '../../data/models/booking.dart';
import '../../data/models/support.dart';
import '../../providers/providers.dart';

/// Support tickets (§3.14): list with open/resolved state, new-ticket sheet,
/// and a thread whose composer locks when support resolves the ticket.
class SupportScreen extends ConsumerWidget {
  const SupportScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tickets = ref.watch(myTicketsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Help & support')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openNewTicketSheet(context, ref),
        icon: const Icon(Symbols.add_rounded),
        label: const Text('NEW TICKET'),
      ),
      body: AsyncView<List<SupportTicket>>(
        value: tickets,
        onRetry: () => ref.invalidate(myTicketsProvider),
        onRefresh: () async {
          ref.invalidate(myTicketsProvider);
          await ref.read(myTicketsProvider.future);
        },
        skeleton: const SkeletonList(count: 4, itemHeight: 76),
        data: (list) {
          if (list.isEmpty) {
            return const EmptyView.scrollable(
              icon: Symbols.support_agent_rounded,
              title: 'How can we help?',
              subtitle: 'Open a ticket and our crew will get back to you here.',
            );
          }
          return ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 96),
            itemCount: list.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, i) {
              final t = list[i];
              final tones = context.tones;
              return FlowCard(
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => TicketThreadScreen(ticketId: t.id),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: t.isOpen ? tones.success : tones.textFaint,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            t.subject,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          Text(
                            [
                              t.isOpen ? 'Open' : 'Resolved',
                              ?t.topic,
                              ?t.sessionRef,
                              timeAgo(t.lastMessageAt),
                            ].join(' · '),
                            style: inter(12.5, 520, color: tones.textFaint),
                          ),
                        ],
                      ),
                    ),
                    Icon(Symbols.chevron_right_rounded, color: tones.textFaint),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  /// New ticket: topic* + subject* + body*; the sheet owns the send, so it
  /// stays open until it succeeds (§9.7, §10.5). A recent session can be
  /// attached, which stamps the ticket with the `FLW-…` reference staff can
  /// search.
  void _openNewTicketSheet(BuildContext context, WidgetRef ref) {
    final subject = TextEditingController();
    final body = TextEditingController();
    var busy = false;
    var attempted = false;
    String? topic;
    Booking? about;

    showFlowSheet<void>(
      context,
      title: 'New support ticket',
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheet) {
          Future<void> submit() async {
            setSheet(() => attempted = true);
            if (topic == null ||
                subject.text.trim().isEmpty ||
                body.text.trim().isEmpty) {
              return;
            }
            setSheet(() => busy = true);
            try {
              final session = ref.read(sessionProvider);
              await ref
                  .read(supportRepositoryProvider)
                  .openTicket(
                    userId: session.uid,
                    userName: session.displayName,
                    subject: subject.text.trim(),
                    body: body.text.trim(),
                    topic: topic,
                    sessionId: about?.id,
                    sessionRef: about == null
                        ? null
                        : sessionRef(about!.id, about!.date),
                  );
              Haptics.light();
              if (sheetContext.mounted) {
                Navigator.pop(sheetContext);
                showFlowToast(context, "Ticket opened — we'll reply here.");
              }
            } catch (e) {
              if (sheetContext.mounted) {
                setSheet(() => busy = false);
                showFlowToast(
                  sheetContext,
                  "Couldn't open the ticket. ${ErrorView.friendly(e)}",
                );
              }
            }
          }

          return ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
            children: [
              // The topic comes first because it is the first thing support
              // reads: the queue triages by it before anyone opens the
              // thread. Required, same contract as the report sheet's reason.
              Text(
                'TOPIC',
                style: microLabel(sheetContext.tones.textFaint, size: 10),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final t in FlowConst.ticketTopics)
                    FlowChoiceChip(
                      label: t,
                      selected: topic == t,
                      onTap: busy
                          ? () {}
                          : () {
                              Haptics.select();
                              setSheet(() => topic = t);
                            },
                    ),
                ],
              ),
              if (attempted && topic == null) ...[
                const SizedBox(height: 8),
                Text(
                  'Pick a topic so the right person sees it first.',
                  style: inter(12.5, 560, color: sheetContext.tones.danger),
                ),
              ],
              const SizedBox(height: 16),
              TextField(
                controller: subject,
                enabled: !busy,
                decoration: InputDecoration(
                  hintText: 'Subject',
                  errorText: attempted && subject.text.trim().isEmpty
                      ? 'Add a short subject'
                      : null,
                ),
                onChanged: (_) => setSheet(() {}),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: body,
                enabled: !busy,
                maxLines: 5,
                minLines: 3,
                decoration: InputDecoration(
                  hintText: 'What happened?',
                  errorText: attempted && body.text.trim().isEmpty
                      ? 'Tell us what happened so we can help'
                      : null,
                ),
                onChanged: (_) => setSheet(() {}),
              ),
              // The session the ticket is about, offered rather than asked:
              // most tickets concern no session, so nothing here is required.
              Consumer(
                builder: (context, ref, _) {
                  final me = ref.watch(sessionProvider);
                  final recent =
                      ref
                          .watch(
                            me.isTrainer
                                ? trainerBookingsProvider
                                : riderBookingsProvider,
                          )
                          .value ??
                      const <Booking>[];
                  if (recent.isEmpty) return const SizedBox.shrink();
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 16),
                      Text(
                        'ABOUT A SESSION? — OPTIONAL',
                        style: microLabel(context.tones.textFaint, size: 10),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final b in recent.take(6))
                            FlowChoiceChip(
                              label:
                                  '${prettyYmd(b.date)} · ${me.isTrainer ? b.studentName : b.instructorName}',
                              selected: about?.id == b.id,
                              onTap: busy
                                  ? () {}
                                  : () {
                                      Haptics.select();
                                      setSheet(
                                        () => about = about?.id == b.id
                                            ? null
                                            : b,
                                      );
                                    },
                            ),
                        ],
                      ),
                      if (about != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Attaches ${sessionRef(about!.id, about!.date)} so support can look it up.',
                          style: inter(12, 500, color: context.tones.textFaint),
                        ),
                      ],
                    ],
                  );
                },
              ),
              const SizedBox(height: 18),
              PrimaryButton(
                label: 'Open ticket',
                busy: busy,
                onPressed: submit,
              ),
            ],
          );
        },
      ),
    );
  }
}

/// One ticket conversation. The composer locks when resolved, replaced by
/// REOPEN (§3.14).
class TicketThreadScreen extends ConsumerStatefulWidget {
  const TicketThreadScreen({super.key, required this.ticketId});

  final String ticketId;

  @override
  ConsumerState<TicketThreadScreen> createState() => _TicketThreadScreenState();
}

class _TicketThreadScreenState extends ConsumerState<TicketThreadScreen> {
  final _input = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    _input.clear();
    try {
      await ref
          .read(supportRepositoryProvider)
          .replyToTicket(
            ticketId: widget.ticketId,
            userId: ref.read(sessionProvider).uid,
            text: text,
          );
      Haptics.light();
    } catch (_) {
      if (mounted) {
        _input.text = text; // failed sends restore the text (§10.5)
        showFlowToast(context, "Couldn't send. Your message is back below.");
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ticket = ref.watch(ticketProvider(widget.ticketId)).value;
    final messages = ref.watch(ticketMessagesProvider(widget.ticketId));
    final me = ref.watch(sessionProvider).uid;
    final tones = context.tones;
    final isOpen = ticket?.isOpen ?? true;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          ticket?.subject ?? 'Ticket',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          if (ticket != null)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(
                child: TagPill(
                  isOpen ? 'OPEN' : 'RESOLVED',
                  color: isOpen ? tones.success : tones.textFaint,
                ),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          // What the ticket is filed under and the session it concerns — the
          // same topic and `FLW-…` reference the staff queue triages by, so
          // both sides of the conversation see the same header facts.
          if (ticket != null &&
              (ticket.topic != null || ticket.sessionRef != null))
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: Row(
                children: [
                  Icon(
                    Symbols.confirmation_number_rounded,
                    size: 16,
                    color: tones.textFaint,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      [
                        ?ticket.topic,
                        if (ticket.sessionRef != null)
                          'About session ${ticket.sessionRef}',
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: inter(12.5, 600, color: tones.textFaint),
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: AsyncView<List<TicketMessage>>(
              value: messages,
              onRetry: () =>
                  ref.invalidate(ticketMessagesProvider(widget.ticketId)),
              skeleton: const SkeletonList(count: 4, itemHeight: 64),
              data: (list) => ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: list.length,
                itemBuilder: (context, i) {
                  final m = list[i];
                  final mine = m.senderId == me && !m.fromStaff;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: ChatBubble(
                      text: m.text,
                      mine: mine,
                      theirsColor: tones.card,
                      header: m.fromStaff
                          ? Text(
                              'FLOW SUPPORT',
                              style: inter(
                                10,
                                800,
                                color: tones.azureBrand,
                                spacing: 1,
                              ),
                            )
                          : null,
                      footer: Text(
                        timeAgo(m.createdAt),
                        style: inter(10, 500, color: tones.textFaint),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          StickyBar(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: isOpen
                ? ComposerField(
                    controller: _input,
                    busy: _sending,
                    maxLines: 4,
                    hintText: 'Reply to support…',
                    onSend: _send,
                  )
                : Row(
                    children: [
                      Expanded(
                        child: Text(
                          'This ticket was resolved by support.',
                          style: inter(14, 520, color: tones.textFaint),
                        ),
                      ),
                      MicroAction(
                        label: 'REOPEN',
                        filled: false,
                        onPressed: () async {
                          await ref
                              .read(supportRepositoryProvider)
                              .reopenTicket(widget.ticketId);
                          if (context.mounted) {
                            showFlowToast(context, 'Ticket reopened');
                          }
                        },
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

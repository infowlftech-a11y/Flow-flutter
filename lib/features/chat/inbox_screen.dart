import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/typography.dart';
import '../../core/utils/date_x.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/flow_image.dart';
import '../../core/widgets/surfaces.dart';
import '../../data/models/social.dart';
import '../../providers/providers.dart';

/// Messages inbox (§3.11): newest first, unread rows tinted + bolded, search
/// filters by partner name.
class InboxScreen extends ConsumerStatefulWidget {
  const InboxScreen({super.key});

  @override
  ConsumerState<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends ConsumerState<InboxScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(sessionProvider).uid;
    final inbox = ref.watch(inboxProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Inbox')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
            child: TextField(
              onChanged: (q) => setState(() => _query = q),
              decoration: const InputDecoration(
                hintText: 'Search conversations…',
                prefixIcon: Icon(Icons.search_rounded, size: 22),
              ),
            ),
          ),
          Expanded(
            child: AsyncView<List<ChatThread>>(
              value: inbox,
              onRetry: () => ref.invalidate(inboxProvider),
              onRefresh: () async {
                ref.invalidate(inboxProvider);
                await ref.read(inboxProvider.future);
              },
              skeleton: const SkeletonList(count: 6, itemHeight: 76),
              data: (threads) {
                final q = _query.trim().toLowerCase();
                final visible = [
                  for (final t in threads)
                    if (q.isEmpty ||
                        t.partnerName(me).toLowerCase().contains(q))
                      t,
                ];
                if (visible.isEmpty) {
                  return const EmptyView.scrollable(
                    icon: Icons.forum_outlined,
                    title: 'No conversations',
                    subtitle:
                        'Message a trainer from their profile to start one.',
                  );
                }
                return ListView.separated(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                  itemCount: visible.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, i) =>
                      _ThreadRow(thread: visible[i], me: me),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ThreadRow extends ConsumerWidget {
  const _ThreadRow({required this.thread, required this.me});

  final ChatThread thread;
  final String me;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tones = context.tones;
    final unread = thread.unreadFor(me);
    final partnerName = thread.partnerName(me);
    final partnerId = thread.partnerId(me);

    return Semantics(
      label: unread > 0
          ? '$partnerName, $unread unread message${unread == 1 ? '' : 's'}'
          : partnerName,
      button: true,
      child: FlowCard(
        padding: const EdgeInsets.all(14),
        color: unread > 0 ? tones.azureBrand.withValues(alpha: .08) : null,
        borderColor:
            unread > 0 ? tones.azureBrand.withValues(alpha: .35) : null,
        onTap: () => context.push(
            '/chat/$partnerId?name=${Uri.encodeComponent(partnerName)}'),
        child: Row(
              children: [
                FlowAvatar(name: partnerName, size: 48),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(partnerName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: inter(15, unread > 0 ? 720 : 620,
                                    color: context.scheme.onSurface)),
                          ),
                          Text(timeAgo(thread.lastMessageAt),
                              style: inter(11.5, 520,
                                  color: unread > 0
                                      ? tones.azureBrand
                                      : tones.textFaint)),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              thread.lastMessage ?? 'Say hi 👋',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: inter(14, unread > 0 ? 600 : 440,
                                  color: unread > 0
                                      ? context.scheme.onSurface
                                      : tones.textFaint),
                            ),
                          ),
                          if (unread > 0) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 7, vertical: 2.5),
                              decoration: BoxDecoration(
                                color: tones.azureBrand,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text('$unread',
                                  style: interNum(11.5, 760,
                                      color: Colors.white)),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
      ),
    );
  }
}

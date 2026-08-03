import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/typography.dart';
import '../../core/utils/date_x.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/sheets.dart';
import '../../data/models/social.dart';
import '../../providers/providers.dart';

/// Notification centre (§3.12).
class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifications = ref.watch(notificationsProvider);
    final unread = notifications.value?.where((n) => !n.read).toList() ?? [];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          // Mark all read appears only when something is unread; batched,
          // with UNDO (§3.12, §10.4).
          if (unread.isNotEmpty)
            TextButton(
              onPressed: () async {
                final repo = ref.read(notificationRepositoryProvider);
                final ids = [for (final n in unread) n.id];
                await repo.markAllRead(ids);
                if (context.mounted) {
                  showFlowToast(
                    context,
                    '${ids.length} marked read',
                    undoLabel: 'UNDO',
                    onUndo: () => repo.markAllUnread(ids).ignore(),
                  );
                }
              },
              child: const Text('Mark all read'),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: AsyncView<List<AppNotification>>(
        value: notifications,
        onRetry: () => ref.invalidate(notificationsProvider),
        onRefresh: () async {
          ref.invalidate(notificationsProvider);
          await ref.read(notificationsProvider.future);
        },
        skeleton: const SkeletonList(count: 6, itemHeight: 76),
        data: (list) {
          if (list.isEmpty) {
            return ListView(children: const [
              SizedBox(height: 60),
              EmptyView(
                icon: Icons.notifications_none_rounded,
                title: 'All quiet',
                subtitle:
                    'Booking updates and messages will land here.',
              ),
            ]);
          }
          return ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(20),
            itemCount: list.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, i) => _NotificationTile(item: list[i]),
          );
        },
      ),
    );
  }
}

class _NotificationTile extends ConsumerWidget {
  const _NotificationTile({required this.item});

  final AppNotification item;

  IconData get _icon => switch (item.kind) {
        NotificationKind.bookingRequest => Icons.pending_actions_rounded,
        NotificationKind.bookingConfirmed => Icons.event_available_rounded,
        NotificationKind.bookingRejected => Icons.event_busy_rounded,
        NotificationKind.bookingCancelled => Icons.cancel_outlined,
        NotificationKind.reminder => Icons.alarm_rounded,
        NotificationKind.review => Icons.star_rounded,
        NotificationKind.message => Icons.chat_bubble_rounded,
        _ => Icons.campaign_rounded,
      };

  void _open(BuildContext context, WidgetRef ref) {
    // Tapping marks read, fire-and-forget (§11.2).
    ref.read(notificationRepositoryProvider).markRead(item.id);
    final isTrainer = ref.read(sessionProvider).isTrainer;

    switch (item.kind) {
      case NotificationKind.bookingRequest:
      case NotificationKind.bookingConfirmed:
      case NotificationKind.bookingRejected:
      case NotificationKind.bookingCancelled:
      case NotificationKind.reminder:
        if (isTrainer) {
          context.go('/home');
        } else {
          context.go(item.bookingId != null
              ? '/sessions?highlight=${item.bookingId}'
              : '/sessions');
        }
      case NotificationKind.message:
        context.go('/inbox');
      case NotificationKind.review:
        context.go('/sessions');
      case NotificationKind.broadcast:
      case NotificationKind.system:
        // No destination — full untruncated text in a sheet (§3.12).
        showFlowSheet<void>(
          context,
          title: item.title,
          builder: (sheetContext) => Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 28),
            child: SingleChildScrollView(
              child: Text(item.message,
                  style: Theme.of(sheetContext)
                      .textTheme
                      .bodyLarge!
                      .copyWith(height: 1.55)),
            ),
          ),
        );
    }
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    await ref.read(notificationRepositoryProvider).delete(item.id);
    if (context.mounted) showFlowToast(context, 'Notification deleted');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tones = context.tones;

    return Semantics(
      customSemanticsActions: {
        // Swipe-to-delete exposed to screen readers too (§3.12).
        const CustomSemanticsAction(label: 'Delete notification'): () =>
            _delete(context, ref),
      },
      child: Dismissible(
        key: ValueKey(item.id),
        direction: DismissDirection.endToStart,
        onDismissed: (_) => _delete(context, ref),
        background: Container(
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 22),
          decoration: BoxDecoration(
            color: tones.danger,
            borderRadius: BorderRadius.circular(16),
          ),
          child:
              const Icon(Icons.delete_outline_rounded, color: Colors.white),
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          // Unread → read tint tweens (§10.9).
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => _open(context, ref),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: item.read
                    ? tones.card
                    : tones.azureBrand.withValues(alpha: .09),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                    color: item.read
                        ? tones.line
                        : tones.azureBrand.withValues(alpha: .35)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: tones.azureBrand.withValues(alpha: .12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child:
                        Icon(_icon, size: 20, color: tones.azureBrand),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(item.title,
                                  style: inter(
                                      14, item.read ? 600 : 720,
                                      color:
                                          context.scheme.onSurface)),
                            ),
                            Text(timeAgo(item.createdAt),
                                style: inter(11, 520,
                                    color: tones.textFaint)),
                            if (!item.read) ...[
                              const SizedBox(width: 6),
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                    color: tones.azureBrand,
                                    shape: BoxShape.circle),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(item.message,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: inter(12.5, item.read ? 440 : 540,
                                color: context.scheme.onSurfaceVariant,
                                height: 1.4)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

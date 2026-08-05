import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/theme/palette.dart';
import '../../core/theme/typography.dart';
import '../../core/utils/date_x.dart';
import '../../core/utils/haptics.dart';
import '../../core/widgets/brand.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/sheets.dart';
import '../../data/firestore_paths.dart';
import '../../data/models/support.dart';
import '../../providers/providers.dart';
import '../../services/image_service.dart';

/// The suspension gate + rider-facing appeals (§3.14).
///
/// A one-minute ticker recomputes the countdown; once the ban lapses it
/// invalidates the profile stream once so the router releases the user
/// automatically (§2.4).
class BlockedScreen extends ConsumerStatefulWidget {
  const BlockedScreen({super.key});

  @override
  ConsumerState<BlockedScreen> createState() => _BlockedScreenState();
}

class _BlockedScreenState extends ConsumerState<BlockedScreen> {
  Timer? _ticker;
  bool _invalidatedOnLapse = false;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(minutes: 1), (_) {
      if (!mounted) return;
      setState(() {});
      final until = ref.read(sessionProvider).user?.blockedUntil;
      if (until != null &&
          DateTime.now().isAfter(until) &&
          !_invalidatedOnLapse) {
        _invalidatedOnLapse = true;
        ref.invalidate(currentUserProvider);
      }
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  String _countdown(DateTime until) {
    final left = until.difference(DateTime.now());
    if (left.isNegative) return 'Any moment now';
    if (left.inDays > 0) {
      return '${left.inDays}d ${left.inHours % 24}h remaining';
    }
    if (left.inHours > 0) {
      return '${left.inHours}h ${left.inMinutes % 60}m remaining';
    }
    return '${left.inMinutes}m remaining';
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    final user = session.user;
    final appeal = ref.watch(myAppealProvider);

    final String untilLabel;
    if (user?.isPermanentlyBlocked ?? false) {
      untilLabel = 'This suspension is permanent.';
    } else if (user?.blockedUntil != null) {
      untilLabel = _countdown(user!.blockedUntil!);
    } else {
      untilLabel = 'Duration under review.';
    }

    return Scaffold(
      backgroundColor: FlowColors.ink,
      body: WaveBackdrop(
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(28),
            children: [
              Align(
                alignment: Alignment.topRight,
                child: TextButton.icon(
                  onPressed: () => ref.read(signOutProvider)(),
                  icon: const Icon(Icons.logout_rounded,
                      size: 18, color: FlowColors.haze),
                  label: Text('Sign out',
                      style: inter(14, 600, color: FlowColors.haze)),
                ),
              ),
              const SizedBox(height: 24),
              Center(
                child: Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    color: FlowColors.coral.withValues(alpha: .14),
                    borderRadius: BorderRadius.circular(28),
                  ),
                  child: const Icon(Icons.front_hand_rounded,
                      color: FlowColors.coral, size: 40),
                ),
              ),
              const SizedBox(height: 28),
              Center(
                child: Text('Account suspended',
                    style: sora(26, 760, color: FlowColors.mist, spacing: -.5)),
              ),
              const SizedBox(height: 10),
              Center(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: FlowColors.navy900.withValues(alpha: .8),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(untilLabel,
                      style: inter(13.5, 640, color: FlowColors.amber)),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Your account was suspended by our moderation team. If you '
                'believe this is a mistake, you can appeal the decision and '
                'talk to us directly below.',
                textAlign: TextAlign.center,
                style: inter(14.5, 440, color: FlowColors.haze, height: 1.55),
              ),
              const SizedBox(height: 28),
              switch (appeal) {
                AsyncValue(hasValue: true, value: final a) => a == null
                    ? PrimaryButton(
                        label: 'Appeal this decision',
                        icon: Icons.gavel_rounded,
                        onPressed: () => _openAppealSheet(context),
                      )
                    : _AppealThread(appeal: a),
                AsyncValue(hasError: true, :final error?) => ErrorView(
                    error: error,
                    onRetry: () => ref.invalidate(myAppealProvider)),
                _ => const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: CircularProgressIndicator(),
                    ),
                  ),
              },
            ],
          ),
        ),
      ),
    );
  }

  /// The appeal sheet stays open until the upload succeeds — a flaky
  /// connection can never discard a typed appeal (§3.14, §10.5).
  Future<void> _openAppealSheet(BuildContext context) async {
    final reasonController = TextEditingController();
    final evidence = <XFile>[];
    var busy = false;

    await showFlowSheet<void>(
      context,
      title: 'Appeal this decision',
      subtitle: 'Explain what happened. Evidence helps.',
      isDismissible: false,
      enableDrag: false,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheet) {
          Future<void> submit() async {
            final reason = reasonController.text.trim();
            if (reason.isEmpty) {
              showFlowToast(sheetContext, 'Please explain your appeal');
              return;
            }
            setSheet(() => busy = true);
            try {
              final session = ref.read(sessionProvider);
              final urls = await ref.read(storageRepositoryProvider).uploadAll(
                    folder: StorageFolder.appeals,
                    files: evidence,
                    ownerId: session.uid,
                  );
              await ref.read(supportRepositoryProvider).submitAppeal(
                    userId: session.uid,
                    userName: session.displayName,
                    reason: reason,
                    attachments: urls,
                  );
              if (sheetContext.mounted) Navigator.pop(sheetContext);
            } catch (_) {
              // Keep the sheet (and the typed text) — let them retry.
              if (sheetContext.mounted) {
                setSheet(() => busy = false);
                showFlowToast(sheetContext,
                    "Couldn't send your appeal. Check your connection and try again.");
              }
            }
          }

          return ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
            children: [
              TextField(
                controller: reasonController,
                maxLines: 5,
                minLines: 3,
                enabled: !busy,
                decoration: const InputDecoration(
                    hintText: 'Why should we lift this suspension?'),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (var i = 0; i < evidence.length; i++)
                    Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.file(File(evidence[i].path),
                              width: 72, height: 72, fit: BoxFit.cover),
                        ),
                        Positioned(
                          right: 2,
                          top: 2,
                          child: GestureDetector(
                            onTap: busy
                                ? null
                                : () => setSheet(() => evidence.removeAt(i)),
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: const BoxDecoration(
                                  color: Colors.black54,
                                  shape: BoxShape.circle),
                              child: const Icon(Icons.close_rounded,
                                  size: 14, color: Colors.white),
                            ),
                          ),
                        ),
                      ],
                    ),
                  OutlinedButton.icon(
                    onPressed: busy
                        ? null
                        : () async {
                            // No crop: this is appeal evidence, and trimming
                            // it is the last thing a moderator wants.
                            final picked = await ImageService.pickWithSheet(
                                sheetContext,
                                shape: null);
                            if (picked != null) {
                              setSheet(() => evidence.add(picked));
                            }
                          },
                    icon: const Icon(Icons.add_photo_alternate_outlined,
                        size: 20),
                    label: const Text('Evidence'),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              PrimaryButton(
                  label: 'Send appeal', busy: busy, onPressed: submit),
              const SizedBox(height: 8),
              TextButton(
                onPressed: busy ? null : () => Navigator.pop(sheetContext),
                child: const Text('Not now'),
              ),
            ],
          );
        },
      ),
    );
    reasonController.dispose();
  }
}

/// In-thread conversation with admins on an existing appeal.
class _AppealThread extends ConsumerStatefulWidget {
  const _AppealThread({required this.appeal});
  final Appeal appeal;

  @override
  ConsumerState<_AppealThread> createState() => _AppealThreadState();
}

class _AppealThreadState extends ConsumerState<_AppealThread> {
  final _controller = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _reply() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    final session = ref.read(sessionProvider);
    try {
      await ref.read(supportRepositoryProvider).replyToAppeal(
            widget.appeal.id,
            AppealMessage(
              id: DateTime.now().millisecondsSinceEpoch.toString(),
              senderId: session.uid,
              senderName: session.displayName,
              text: text,
              timestamp: DateTime.now(),
            ),
          );
      Haptics.light();
      _controller.clear();
    } catch (_) {
      if (mounted) {
        showFlowToast(context, "Couldn't send. Try again.");
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.appeal;
    final statusColor = switch (a.status) {
      'resolved' => FlowColors.emerald,
      'reviewed' => FlowColors.azure,
      _ => FlowColors.amber,
    };

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: FlowColors.navy900.withValues(alpha: .85),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: FlowColors.navy700),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('YOUR APPEAL',
                    style: microLabel(FlowColors.slate)),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: .16),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(a.status.toUpperCase(),
                    style: inter(10.5, 720, color: statusColor, spacing: 1)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(a.reason,
              style: inter(14.5, 460, color: FlowColors.mist, height: 1.5)),
          if (a.messages.isNotEmpty) ...[
            const SizedBox(height: 16),
            for (final m in a.messages) _AppealBubble(message: m),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  enabled: !_sending,
                  style: inter(14.5, 460, color: FlowColors.mist),
                  decoration: const InputDecoration(
                    hintText: 'Reply to the team…',
                    isDense: true,
                  ),
                  onSubmitted: (_) => _reply(),
                ),
              ),
              const SizedBox(width: 10),
              IconButton.filled(
                onPressed: _sending ? null : _reply,
                icon: _sending
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.send_rounded, size: 20),
                tooltip: 'Send reply',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AppealBubble extends ConsumerWidget {
  const _AppealBubble({required this.message});
  final AppealMessage message;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mine = message.senderId == ref.watch(sessionProvider).uid;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment:
            mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
            constraints: const BoxConstraints(maxWidth: 280),
            decoration: BoxDecoration(
              color: mine
                  ? FlowColors.azure.withValues(alpha: .18)
                  : FlowColors.navy800,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(message.text,
                style: inter(13.5, 460, color: FlowColors.mist, height: 1.45)),
          ),
          const SizedBox(height: 3),
          Text(
            '${mine ? 'You' : message.senderName} · ${timeAgo(message.timestamp)}',
            style: inter(11, 520, color: FlowColors.slate),
          ),
        ],
      ),
    );
  }
}

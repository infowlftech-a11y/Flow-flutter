import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/radii.dart';
import '../../core/theme/typography.dart';
import '../../core/utils/date_x.dart';
import '../../core/utils/haptics.dart';
import '../../core/widgets/gate.dart';
import '../../core/widgets/misc.dart';
import '../../core/widgets/media.dart';
import '../../core/widgets/surfaces.dart';
import '../../core/widgets/thread.dart';
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

    return GateScaffold(
      onSignOut: () => ref.read(signOutProvider)(),
      padding: EdgeInsets.zero,
      child: ListView(
            padding: const EdgeInsets.all(28),
            children: [
              Center(
                child: FlowIconChip(
                  icon: Symbols.front_hand_rounded,
                  color: context.tones.danger,
                  size: 88,
                  tintOpacity: .14,
                ),
              ),
              const SizedBox(height: 28),
              Center(
                child: Text('Account suspended',
                    style: display(26, 760, color: context.scheme.onSurface, spacing: -.5)),
              ),
              const SizedBox(height: 10),
              Center(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: context.tones.card.withValues(alpha: .8),
                    borderRadius: FlowRadii.chip,
                  ),
                  child: Text(untilLabel,
                      style: inter(14, 640, color: context.tones.warning)),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Your account was suspended by our moderation team. If you '
                'believe this is a mistake, you can appeal the decision and '
                'talk to us directly below.',
                textAlign: TextAlign.center,
                style: inter(14, 440, color: context.scheme.onSurfaceVariant, height: 1.55),
              ),
              const SizedBox(height: 28),
              switch (appeal) {
                AsyncValue(hasValue: true, value: final a) => a == null
                    ? PrimaryButton(
                        label: 'Appeal this decision',
                        icon: Symbols.gavel_rounded,
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
            } catch (e) {
              // Keep the sheet (and the typed text) — let them retry.
              if (sheetContext.mounted) {
                setSheet(() => busy = false);
                showFlowToast(sheetContext,
                    "Couldn't send your appeal. ${ErrorView.friendly(e)}");
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
                    ThumbTile.file(
                      evidence[i].path,
                      size: 72,
                      onRemove: busy
                          ? null
                          : () => setSheet(() => evidence.removeAt(i)),
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
                    icon: const Icon(Symbols.add_photo_alternate_rounded,
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
    } catch (e) {
      if (mounted) {
        showFlowToast(context, "Couldn't send. ${ErrorView.friendly(e)}");
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.appeal;
    final statusColor = switch (a.status) {
      'resolved' => context.tones.success,
      'reviewed' => context.scheme.primary,
      _ => context.tones.warning,
    };

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: context.tones.card.withValues(alpha: .85),
        borderRadius: FlowRadii.card,
        border: Border.all(color: context.tones.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('YOUR APPEAL',
                    style: microLabel(context.tones.textFaint)),
              ),
              TagPill(a.status.toUpperCase(),
                  color: statusColor, dense: true),
            ],
          ),
          const SizedBox(height: 12),
          Text(a.reason,
              style: inter(14, 460, color: context.scheme.onSurface, height: 1.5)),
          if (a.messages.isNotEmpty) ...[
            const SizedBox(height: 16),
            for (final m in a.messages) _AppealBubble(message: m),
          ],
          const SizedBox(height: 14),
          ComposerField(
            controller: _controller,
            busy: _sending,
            maxLines: 4,
            isDense: true,
            hintText: 'Reply to the team…',
            sendIcon: Symbols.send_rounded,
            textStyle: inter(14, 460, color: context.scheme.onSurface),
            onSend: _reply,
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
      child: ChatBubble(
        text: message.text,
        mine: mine,
        // The gate screens keep the ink palette in both themes.
        mineColor: context.scheme.primary.withValues(alpha: .18),
        theirsColor: context.tones.cardHigh,
        mineTextColor: context.scheme.onSurface,
        theirsTextColor: context.scheme.onSurface,
        bordered: false,
        footer: Text(
          '${mine ? 'You' : message.senderName} · ${timeAgo(message.timestamp)}',
          style: inter(11.5, 520, color: context.tones.textFaint),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/typography.dart';
import '../../core/utils/haptics.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/flow_image.dart';
import '../../data/models/social.dart';
import '../../providers/providers.dart';

/// One conversation (§3.11).
///
/// Scroll contract: jump to newest on first load; afterwards follow new
/// messages **only when already near the bottom** (120px), so reading history
/// is never interrupted. A jump-to-latest pill shows how many arrived while
/// scrolled away.
class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({
    super.key,
    required this.partnerId,
    required this.partnerName,
  });

  final String partnerId;
  final String partnerName;

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _scroll = ScrollController();
  final _input = TextEditingController();
  bool _didInitialJump = false;
  int _missedWhileAway = 0;
  int _lastCount = 0;
  bool _canSend = false;

  String get _chatId =>
      ChatThread.idFor(ref.read(sessionProvider).uid, widget.partnerId);

  @override
  void initState() {
    super.initState();
    // Opening a thread creates the doc if needed and clears my unread count.
    final session = ref.read(sessionProvider);
    ref.read(chatRepositoryProvider).openThread(
          me: session.uid,
          myName: session.displayName,
          partnerId: widget.partnerId,
          partnerName: widget.partnerName,
        );
    ref.read(chatRepositoryProvider).markThreadRead(_chatId, session.uid);
    _input.addListener(() {
      final can = _input.text.trim().isNotEmpty;
      if (can != _canSend) setState(() => _canSend = can);
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    _input.dispose();
    super.dispose();
  }

  bool get _nearBottom {
    if (!_scroll.hasClients) return true;
    return _scroll.position.maxScrollExtent - _scroll.offset <=
        FlowConst.chatFollowThresholdPx;
  }

  void _jumpToLatest({bool animate = true}) {
    if (!_scroll.hasClients) return;
    final target = _scroll.position.maxScrollExtent;
    if (animate) {
      _scroll.animateTo(target,
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic);
    } else {
      _scroll.jumpTo(target);
    }
    setState(() => _missedWhileAway = 0);
  }

  void _onMessages(List<ChatMessage> messages) {
    final grew = messages.length > _lastCount;
    _lastCount = messages.length;
    if (!grew) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!_didInitialJump) {
        _didInitialJump = true;
        _jumpToLatest(animate: false);
        return;
      }
      if (_nearBottom) {
        _jumpToLatest();
        // Anything that lands while we're here is read.
        ref
            .read(chatRepositoryProvider)
            .markThreadRead(_chatId, ref.read(sessionProvider).uid);
      } else {
        setState(() => _missedWhileAway++);
      }
    });
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    final session = ref.read(sessionProvider);
    Haptics.light();
    _input.clear();
    _jumpToLatest();
    try {
      // Fire-and-forget: latency compensation paints the bubble instantly
      // (§10.6). A failure restores the text to the composer.
      await ref.read(chatRepositoryProvider).send(
            me: session.uid,
            myName: session.displayName,
            partnerId: widget.partnerId,
            text: text,
          );
    } catch (_) {
      if (mounted) {
        _input.text = text;
        showFlowToast(context, "Couldn't send. Your message is back below.");
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final messages = ref.watch(chatMessagesProvider(_chatId));
    final me = ref.watch(sessionProvider).uid;

    if (messages case AsyncData(:final value)) {
      _onMessages(value);
    }

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            FlowAvatar(name: widget.partnerName, size: 36),
            const SizedBox(width: 10),
            Expanded(
              child: Text(widget.partnerName,
                  maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                AsyncView<List<ChatMessage>>(
                  value: messages,
                  onRetry: () =>
                      ref.invalidate(chatMessagesProvider(_chatId)),
                  skeleton: const _ChatSkeleton(),
                  data: (list) {
                    if (list.isEmpty) {
                      return EmptyView(
                        icon: Icons.waving_hand_outlined,
                        title: 'Say hi to ${widget.partnerName}',
                        subtitle:
                            'Ask about conditions, gear or the next session.',
                      );
                    }
                    return ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                      itemCount: list.length,
                      itemBuilder: (context, i) {
                        final m = list[i];
                        final prev = i > 0 ? list[i - 1] : null;
                        final next =
                            i < list.length - 1 ? list[i + 1] : null;
                        // Absolute timestamp only when there's a >10-minute
                        // gap (§3.11).
                        final showTimestamp = prev == null ||
                            (m.createdAt != null &&
                                prev.createdAt != null &&
                                m.createdAt!
                                        .difference(prev.createdAt!)
                                        .inMinutes >
                                    FlowConst.chatTimestampGapMinutes);
                        // Consecutive messages from one sender share a run.
                        final firstOfRun =
                            showTimestamp || prev.senderId != m.senderId;
                        final lastOfRun =
                            next == null || next.senderId != m.senderId;
                        return _Bubble(
                          message: m,
                          mine: m.senderId == me,
                          firstOfRun: firstOfRun,
                          lastOfRun: lastOfRun,
                          showTimestamp: showTimestamp,
                        );
                      },
                    );
                  },
                ),
                Positioned(
                  bottom: 10,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: AnimatedScale(
                      scale: _missedWhileAway > 0 ? 1 : 0,
                      duration: const Duration(milliseconds: 200),
                      child: Material(
                        color: context.tones.azureBrand,
                        borderRadius: BorderRadius.circular(20),
                        elevation: 3,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(20),
                          onTap: _jumpToLatest,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 8),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.arrow_downward_rounded,
                                    size: 16, color: Colors.white),
                                const SizedBox(width: 6),
                                Text(
                                  '$_missedWhileAway new',
                                  style: inter(12.5, 680,
                                      color: Colors.white),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          _Composer(
            controller: _input,
            canSend: _canSend,
            onSend: _send,
          ),
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.message,
    required this.mine,
    required this.firstOfRun,
    required this.lastOfRun,
    required this.showTimestamp,
  });

  final ChatMessage message;
  final bool mine;
  final bool firstOfRun;
  final bool lastOfRun;
  final bool showTimestamp;

  String _clock(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final tones = context.tones;
    final dark = Theme.of(context).brightness == Brightness.dark;

    final radius = BorderRadius.only(
      topLeft: Radius.circular(mine || firstOfRun ? 18 : 6),
      topRight: Radius.circular(!mine || firstOfRun ? 18 : 6),
      bottomLeft: Radius.circular(mine || lastOfRun ? 18 : 6),
      bottomRight: Radius.circular(!mine || lastOfRun ? 18 : 6),
    );

    return Column(
      crossAxisAlignment:
          mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        if (showTimestamp && message.createdAt != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Center(
              child: Text(
                '${message.createdAt!.day} ${monthsForChat[message.createdAt!.month - 1]} · ${_clock(message.createdAt!)}',
                style: inter(11, 600, color: tones.textFaint, spacing: .4),
              ),
            ),
          ),
        Padding(
          padding: EdgeInsets.only(top: firstOfRun ? 8 : 2),
          child: GestureDetector(
            // Long-press any bubble to copy (§3.11).
            onLongPress: () {
              Haptics.light();
              Clipboard.setData(ClipboardData(text: message.text));
              showFlowToast(context, 'Copied');
            },
            child: Container(
              constraints: BoxConstraints(
                  maxWidth: MediaQuery.sizeOf(context).width * .74),
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: mine
                    ? tones.azureBrand
                    : (dark
                        ? context.scheme.surfaceContainerHigh
                        : Colors.white),
                borderRadius: radius,
                border: mine ? null : Border.all(color: tones.line),
              ),
              child: Text(
                message.text,
                style: inter(14.5, 460,
                    color: mine ? Colors.white : context.scheme.onSurface,
                    height: 1.4),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

const monthsForChat = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.canSend,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool canSend;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final tones = context.tones;
    return Container(
      padding: EdgeInsets.fromLTRB(
          14, 10, 14, 10 + MediaQuery.paddingOf(context).bottom),
      decoration: BoxDecoration(
        color: context.scheme.surfaceContainerLow,
        border: Border(top: BorderSide(color: tones.line)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              minLines: 1,
              maxLines: 5,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(hintText: 'Message…'),
              onSubmitted: (_) => canSend ? onSend() : null,
            ),
          ),
          const SizedBox(width: 10),
          AnimatedOpacity(
            duration: const Duration(milliseconds: 150),
            opacity: canSend ? 1 : .45,
            child: SizedBox(
              width: 48,
              height: 48,
              child: IconButton.filled(
                onPressed: canSend ? onSend : null,
                tooltip: 'Send',
                icon: const Icon(Icons.arrow_upward_rounded, size: 22),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChatSkeleton extends StatelessWidget {
  const _ChatSkeleton();

  @override
  Widget build(BuildContext context) {
    Widget bubble(bool mine, double width) => Align(
          alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: SkeletonPulse(width: width, height: 40, radius: 16),
          ),
        );
    return ListView(
      padding: const EdgeInsets.all(16),
      physics: const NeverScrollableScrollPhysics(),
      children: [
        bubble(false, 200),
        bubble(false, 150),
        bubble(true, 220),
        bubble(false, 120),
        bubble(true, 180),
      ],
    );
  }
}

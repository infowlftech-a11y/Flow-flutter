import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/motion.dart';
import '../../core/theme/radii.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/typography.dart';
import '../../core/utils/haptics.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/misc.dart';
import '../../providers/providers.dart';

/// Inline review composer (stars + optional comment). Used on the trainer
/// profile (eligibility-gated) and from Sessions ▸ Rate (§3.4, §3.7).
/// The repository independently guards against double submission (§8.9).
class ReviewComposerCard extends ConsumerStatefulWidget {
  const ReviewComposerCard({
    super.key,
    required this.trainerId,
    required this.bookingId,
    this.onSubmitted,
    this.title = 'How was your session?',
  });

  final String trainerId;
  final String bookingId;
  final VoidCallback? onSubmitted;
  final String title;

  @override
  ConsumerState<ReviewComposerCard> createState() =>
      _ReviewComposerCardState();
}

class _ReviewComposerCardState extends ConsumerState<ReviewComposerCard> {
  int _stars = 0;
  final _comment = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_stars == 0 || _busy) return;
    setState(() => _busy = true);
    try {
      final session = ref.read(sessionProvider);
      await ref.read(reviewRepositoryProvider).submit(
            trainerId: widget.trainerId,
            userId: session.uid,
            userName: session.displayName,
            rating: _stars,
            comment: _comment.text,
            bookingId: widget.bookingId,
          );
      Haptics.medium();
      if (mounted) {
        showFlowToast(context, 'Thanks — review posted 🤙');
        widget.onSubmitted?.call();
      }
    } catch (_) {
      if (mounted) {
        setState(() => _busy = false);
        showFlowToast(context, "Couldn't post your review. Try again.");
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final tones = context.tones;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: tones.azureBrand.withValues(alpha: .07),
        borderRadius: FlowRadii.card,
        border: Border.all(color: tones.azureBrand.withValues(alpha: .35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.title,
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          Center(
            child: Stars(
              value: _stars.toDouble(),
              onChanged: (v) {
                Haptics.select();
                setState(() => _stars = v);
              },
            ),
          ),
          AnimatedSize(
            duration: FlowMotion.base,
            curve: FlowMotion.curve,
            alignment: Alignment.topCenter,
            child: _stars == 0
                ? const SizedBox.shrink()
                : Column(
                    children: [
                      const SizedBox(height: 10),
                      TextField(
                        controller: _comment,
                        enabled: !_busy,
                        maxLines: 3,
                        minLines: 1,
                        decoration: const InputDecoration(
                            hintText: 'Add a comment (optional)'),
                      ),
                      const SizedBox(height: 12),
                      PrimaryButton(
                        label: 'Post review',
                        busy: _busy,
                        onPressed: _submit,
                      ),
                    ],
                  ),
          ),
          if (_stars == 0)
            Center(
              child: Text('Tap a star to rate',
                  style: inter(12.5, 500, color: tones.textFaint)),
            ),
        ],
      ),
    );
  }
}

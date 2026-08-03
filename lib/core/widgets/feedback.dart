import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme/app_theme.dart';
import '../theme/typography.dart';
import '../utils/haptics.dart';

/// The single place async state is rendered (APP_LOGIC_BLUEPRINT.md §10.1).
///
/// `onRetry` is **required** — it is impossible to ship an error dead end by
/// forgetting it. Previous data stays visible while a stream re-subscribes,
/// so lists never flash empty on navigation.
class AsyncView<T> extends StatelessWidget {
  const AsyncView({
    super.key,
    required this.value,
    required this.data,
    required this.onRetry,
    this.skeleton,
    this.onRefresh,
  });

  final AsyncValue<T> value;
  final Widget Function(T data) data;
  final VoidCallback onRetry;
  final Widget? skeleton;
  final Future<void> Function()? onRefresh;

  @override
  Widget build(BuildContext context) {
    Widget child;
    if (value.hasValue) {
      child = data(value.value as T);
      if (onRefresh != null) {
        child = RefreshIndicator(
          onRefresh: onRefresh!,
          edgeOffset: 12,
          child: child,
        );
      }
    } else if (value.hasError) {
      child = ErrorView(error: value.error!, onRetry: onRetry);
    } else {
      child = skeleton ?? const Center(child: CircularProgressIndicator());
    }
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      child: KeyedSubtree(
        key: ValueKey(value.hasValue
            ? 'data'
            : value.hasError
                ? 'error'
                : 'loading'),
        child: child,
      ),
    );
  }
}

class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  /// Firestore / generic error → human words (§10.3).
  static String friendly(Object error) {
    final s = error.toString().toLowerCase();
    if (s.contains('permission-denied')) {
      return "You don't have access to this yet.";
    }
    if (s.contains('unavailable') || s.contains('network')) {
      return 'No connection. Check your internet and try again.';
    }
    if (s.contains('failed-precondition') && s.contains('index')) {
      return "This view needs a database index that hasn't been created yet.";
    }
    return 'Something went wrong. Please try again.';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: context.tones.dangerTint,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(Icons.wifi_tethering_error_rounded,
                  color: context.tones.danger, size: 30),
            ),
            const SizedBox(height: 20),
            Text('Hit some chop', style: theme.textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(
              friendly(error),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 20),
              label: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Friendly empty state.
class EmptyView extends StatelessWidget {
  const EmptyView({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.action,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(32, 40, 32, 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: context.tones.azureBrand.withValues(alpha: .12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(icon, color: context.tones.azureBrand, size: 30),
            ),
            const SizedBox(height: 20),
            Text(title,
                style: theme.textTheme.headlineSmall,
                textAlign: TextAlign.center),
            if (subtitle != null) ...[
              const SizedBox(height: 8),
              Text(subtitle!,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium),
            ],
            if (action != null) ...[const SizedBox(height: 20), action!],
          ],
        ),
      ),
    );
  }
}

/// Skeleton building block. Holds a static opacity when the OS reports
/// reduce-motion; excluded from semantics.
class SkeletonPulse extends StatefulWidget {
  const SkeletonPulse({super.key, this.width, this.height = 14, this.radius = 8});

  final double? width;
  final double height;
  final double radius;

  @override
  State<SkeletonPulse> createState() => _SkeletonPulseState();
}

class _SkeletonPulseState extends State<SkeletonPulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1100));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _c.stop();
      _c.value = .5;
    } else if (!_c.isAnimating) {
      _c.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: FadeTransition(
        opacity: Tween(begin: .35, end: .9).animate(
            CurvedAnimation(parent: _c, curve: Curves.easeInOut)),
        child: Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            color: context.tones.cardHigh,
            borderRadius: BorderRadius.circular(widget.radius),
          ),
        ),
      ),
    );
  }
}

/// A skeleton card shaped like list content, so nothing jumps on arrival.
class SkeletonCard extends StatelessWidget {
  const SkeletonCard({super.key, this.height = 84});
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.tones.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: context.tones.line),
      ),
      child: Row(
        children: [
          const SkeletonPulse(width: 48, height: 48, radius: 14),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                SkeletonPulse(width: 140),
                SizedBox(height: 8),
                SkeletonPulse(width: 90, height: 10),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class SkeletonList extends StatelessWidget {
  const SkeletonList({super.key, this.count = 5, this.itemHeight = 84});
  final int count;
  final double itemHeight;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      physics: const NeverScrollableScrollPhysics(),
      itemCount: count,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (_, _) => SkeletonCard(height: itemHeight),
    );
  }
}

/// Brand toast. Optional [onUndo] renders the frequent-reversible pattern —
/// undo instead of a confirm dialog (§10.4).
void showFlowToast(
  BuildContext context,
  String message, {
  String? undoLabel,
  VoidCallback? onUndo,
  IconData? icon,
}) {
  Haptics.light();
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      duration: Duration(seconds: onUndo != null ? 5 : 3),
      content: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 18, color: context.tones.azureBrand),
            const SizedBox(width: 10),
          ],
          Expanded(child: Text(message)),
        ],
      ),
      action: onUndo != null
          ? SnackBarAction(label: undoLabel ?? 'UNDO', onPressed: onUndo)
          : null,
    ),
  );
}

/// Blocking, non-dismissible overlay for multi-second uploads (§10.5).
Future<T> withBusyOverlay<T>(
  BuildContext context,
  Future<T> Function() task, {
  String label = 'Uploading…',
}) async {
  final navigator = Navigator.of(context, rootNavigator: true);
  var dismissed = false;
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    useRootNavigator: true,
    builder: (dialogContext) => PopScope(
      canPop: false,
      child: Center(
        child: Container(
          padding: const EdgeInsets.fromLTRB(28, 26, 28, 24),
          decoration: BoxDecoration(
            color: Theme.of(dialogContext).dialogTheme.backgroundColor,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                  width: 34, height: 34,
                  child: CircularProgressIndicator(strokeWidth: 3)),
              const SizedBox(height: 18),
              Material(
                color: Colors.transparent,
                child: Text(label,
                    style: inter(14.5, 560,
                        color: Theme.of(dialogContext).colorScheme.onSurface)),
              ),
            ],
          ),
        ),
      ),
    ),
  ).then((_) => dismissed = true);
  try {
    return await task();
  } finally {
    if (!dismissed && navigator.mounted) navigator.pop();
  }
}

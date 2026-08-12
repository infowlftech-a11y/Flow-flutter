import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme/motion.dart';
import '../theme/app_theme.dart';
import '../theme/palette.dart';
import '../theme/radii.dart';
import '../theme/typography.dart';
import '../utils/error_copy.dart';
import '../utils/haptics.dart';
import 'loader.dart';
import 'surfaces.dart';

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
      child = skeleton ?? const Center(child: FlowLoader());
    }
    return AnimatedSwitcher(
      duration: FlowMotion.base,
      switchInCurve: FlowMotion.curve,
      switchOutCurve: FlowMotion.curve,
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
  ///
  /// The mapping itself lives in `core/utils/error_copy.dart` — it is a rule
  /// about what users are told, not a presentation detail, and it should not
  /// be editable as a side effect of restyling this widget. Kept here as a
  /// delegating alias so existing call sites are unaffected.
  static String friendly(Object error) => friendlyError(error);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FlowIconChip(
              icon: Symbols.wifi_tethering_error_rounded,
              color: context.tones.danger,
              size: 64,
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
              icon: const Icon(Symbols.refresh_rounded, size: 20),
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
    this.onScrim = false,
  })  : _scrollable = false,
        topGap = 0;

  /// The same view wrapped in a scrollable, for a list slot whose non-empty
  /// branch scrolls.
  ///
  /// Seven call sites hand-rolled this as
  /// `ListView(children: const [SizedBox(height: 60), EmptyView(…)])`, and
  /// every one of them dropped the `physics: AlwaysScrollableScrollPhysics()`
  /// its own non-empty branch sets. That is not cosmetic: an empty state is
  /// shorter than the viewport, so `minScrollExtent == maxScrollExtent` and the
  /// default clamping physics refuses the drag outright — the enclosing
  /// `RefreshIndicator` never sees it. Pull-to-refresh was dead on precisely
  /// the state where someone is most likely to pull.
  const EmptyView.scrollable({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.action,
    this.topGap = 0,
  })  : onScrim = false,
        _scrollable = true;

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? action;

  /// Renders on the fixed dark palette instead of the theme's, for the
  /// full-screen media surfaces (crop, scanner) that stay black in both
  /// themes. Drops the tinted chip for a bare glyph — those screens are
  /// deliberately chrome-free.
  final bool onScrim;

  final bool _scrollable;

  /// Nudges the centred state off true centre. Only read by
  /// [EmptyView.scrollable], and only where something else already occupies
  /// the top of the viewport — a filter bar the list scrolls under, say —
  /// so that "centred" means centred in the space the user can actually see.
  final double topGap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final content = Padding(
      padding: const EdgeInsets.fromLTRB(32, 40, 32, 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (onScrim)
            Icon(icon, color: FlowColors.haze, size: 44)
          else
            FlowIconChip(icon: icon, size: 64),
          const SizedBox(height: 20),
          Text(
            title,
            textAlign: TextAlign.center,
            style: onScrim
                ? display(20, 700, color: FlowColors.mist)
                : theme.textTheme.headlineSmall,
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 8),
            Text(
              subtitle!,
              textAlign: TextAlign.center,
              style: onScrim
                  ? inter(14, 460, color: FlowColors.haze, height: 1.5)
                  : theme.textTheme.bodyMedium,
            ),
          ],
          if (action != null) ...[const SizedBox(height: 20), action!],
        ],
      ),
    );

    if (!_scrollable) return Center(child: content);

    // Centred in the viewport, not pinned near the top.
    //
    // This used to be `ListView(children: [SizedBox(height: 60), content])`,
    // which left every empty state hanging under the app bar with the whole
    // lower half of the screen blank beneath it — the emptiness read as a
    // rendering failure rather than as an answer.
    //
    // The scroll view stays, and stays `AlwaysScrollableScrollPhysics`: an
    // empty state is shorter than its viewport, so without it the drag is
    // refused outright and the enclosing RefreshIndicator never fires. The
    // minHeight constraint is what lets `Center` have something to centre
    // within — a bare SingleChildScrollView shrink-wraps its child and
    // centring inside it would be a no-op.
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(
            child: Padding(
              padding: EdgeInsets.only(top: topGap),
              child: content,
            ),
          ),
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
      vsync: this, duration: FlowMotion.pulse);

  // Built once. The previous version created a CurvedAnimation inside build(),
  // and every one of those registers a status listener on `_c` that nothing
  // ever removes — on a skeleton list that rebuilds while data streams in,
  // the listener list grew without bound behind a widget that is on screen
  // for under a second.
  late final CurvedAnimation _curve =
      CurvedAnimation(parent: _c, curve: Curves.easeInOut);
  late final Animation<double> _opacity =
      Tween(begin: .35, end: .9).animate(_curve);

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
    _curve.dispose();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: FadeTransition(
        opacity: _opacity,
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
    return SizedBox(
      height: height,
      child: FlowCard(
        child: Row(
          children: [
            const SkeletonPulse(
                width: 48, height: 48, radius: FlowRadius.control),
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

/// A grid of identical placeholder tiles.
///
/// The counterpart to [SkeletonList]. Explore's trainer grid and the booking
/// screen's slot grid each hand-rolled `GridView.builder`, and the point of
/// centralising it is [NeverScrollableScrollPhysics]: a skeleton that scrolls
/// on its own leaves the viewport somewhere the real list will not be, so the
/// content jumps the moment it arrives.
class SkeletonGrid extends StatelessWidget {
  const SkeletonGrid({
    super.key,
    required this.gridDelegate,
    required this.tile,
    this.count = 6,
    this.padding = EdgeInsets.zero,
    this.shrinkWrap = false,
  });

  final SliverGridDelegate gridDelegate;

  /// One tile, reused for every cell — placeholders never differ by index.
  final Widget tile;
  final int count;
  final EdgeInsetsGeometry padding;
  final bool shrinkWrap;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: padding,
      shrinkWrap: shrinkWrap,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: gridDelegate,
      itemCount: count,
      itemBuilder: (_, _) => tile,
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
            borderRadius: FlowRadii.dialog,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const FlowLoader(size: 34),
              const SizedBox(height: 18),
              Material(
                color: Colors.transparent,
                child: Text(label,
                    style: inter(14, 560,
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

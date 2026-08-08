import 'package:flutter/material.dart';

import '../../core/theme/motion.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/radii.dart';
import '../../core/theme/typography.dart';
import '../../core/widgets/brand.dart';

/// Shared chrome for every auth route.
///
/// The old screen packed log-in and registration into one form behind a
/// segmented toggle, so the first thing a user had to do was work out which
/// mode they were in. Each flow now gets its own route with its own title and
/// its own single call to action; this is what makes them look like one
/// family rather than four unrelated pages.
class AuthScaffold extends StatelessWidget {
  const AuthScaffold({
    super.key,
    required this.title,
    required this.subtitle,
    required this.children,
    this.showBack = true,
    this.footer,
  });

  final String title;
  final String subtitle;
  final List<Widget> children;
  final bool showBack;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      // Was hardcoded ink, which made all four auth routes a dark island in a
      // light app. WaveBackdrop switches ground with the theme; the copy has
      // to follow it or it disappears.
      backgroundColor: scheme.surface,
      appBar: showBack
          ? AppBar(
              backgroundColor: Colors.transparent,
              foregroundColor: scheme.onSurface,
              elevation: 0,
            )
          : null,
      extendBodyBehindAppBar: true,
      body: WaveBackdrop(
        child: SafeArea(
          // The footer used to be pinned below a fixed-height scroll view.
          // With the keyboard up that viewport ended mid-CTA, so the Sign in
          // button was sliced in half with "New to FLOW?" pinned underneath
          // it — reachable only by scrolling, and reading as broken.
          //
          // SliverFillRemaining gives the content at least the viewport's
          // height and lets it grow past it. The Spacer therefore pushes the
          // footer to the bottom when there is room to spare, and collapses
          // to nothing when the keyboard takes that room, at which point the
          // whole column scrolls as one piece.
          child: CustomScrollView(
            slivers: [
              SliverFillRemaining(
                hasScrollBody: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(28, 8, 28, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 8),
                      Text(title,
                          style: sora(32, 780,
                              color: scheme.onSurface,
                              spacing: -.8,
                              height: 1.12)),
                      const SizedBox(height: 10),
                      Text(subtitle,
                          style: inter(14, 460,
                              color: scheme.onSurfaceVariant, height: 1.45)),
                      const SizedBox(height: 28),
                      ...children,
                      if (footer != null) ...[
                        const SizedBox(height: 24),
                        const Spacer(),
                        footer!,
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Form-level problem: no connection, rate limited, service misconfigured.
/// Anything tied to one input belongs under that input instead.
class AuthBanner extends StatelessWidget {
  const AuthBanner({super.key, required this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    final tones = context.tones;
    final scheme = Theme.of(context).colorScheme;
    return AnimatedSize(
      duration: FlowMotion.base,
      alignment: Alignment.topCenter,
      child: message == null
          ? const SizedBox(width: double.infinity)
          : Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 18),
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              decoration: BoxDecoration(
                color: tones.dangerTint,
                borderRadius: FlowRadii.chip,
                border:
                    Border.all(color: tones.danger.withValues(alpha: .45)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.error_outline_rounded,
                      size: 18, color: tones.danger),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(message!,
                        style: inter(14, 500,
                            color: scheme.onSurface, height: 1.35)),
                  ),
                ],
              ),
            ),
    );
  }
}

/// A one-tap route out of the wrong door — "this email already has an
/// account, sign in instead" and its mirror image.
///
/// Presented as an offer rather than an error because the user did nothing
/// wrong; they just started on the other screen.
class AuthRecoveryCard extends StatelessWidget {
  const AuthRecoveryCard({
    super.key,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final accent = context.tones.azureBrand;
    return Container(
      margin: const EdgeInsets.only(bottom: 18),
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: .12),
        borderRadius: FlowRadii.chip,
        border: Border.all(color: accent.withValues(alpha: .4)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(message,
                style: inter(14, 500,
                    color: Theme.of(context).colorScheme.onSurface,
                    height: 1.35)),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: onAction,
            child: Text(actionLabel, style: inter(14, 700, color: accent)),
          ),
        ],
      ),
    );
  }
}

/// A labelled auth input.
///
/// Password fields carry a reveal toggle. On registration it sits on both the
/// password and its confirmation and drives a single flag, so revealing one
/// reveals the other — a typo hiding in the field you cannot see would defeat
/// the point of asking twice.
class AuthTextField extends StatelessWidget {
  const AuthTextField({
    super.key,
    required this.label,
    required this.controller,
    required this.focusNode,
    this.hintText,
    this.errorText,
    this.keyboardType,
    this.autofillHints,
    this.textInputAction = TextInputAction.next,
    this.textCapitalization = TextCapitalization.none,
    this.obscure = false,
    this.onToggleObscure,
    this.onSubmitted,
    this.onChanged,
    this.enabled = true,
    this.autofocus = false,
  });

  final String label;
  final TextEditingController controller;
  final FocusNode focusNode;
  final String? hintText;
  final String? errorText;
  final TextInputType? keyboardType;
  final Iterable<String>? autofillHints;
  final TextInputAction textInputAction;
  final TextCapitalization textCapitalization;
  final bool obscure;
  final VoidCallback? onToggleObscure;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;
  final bool enabled;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label.toUpperCase(),
              style: microLabel(scheme.onSurfaceVariant)),
          const SizedBox(height: 8),
          TextField(
            controller: controller,
            focusNode: focusNode,
            enabled: enabled,
            autofocus: autofocus,
            obscureText: obscure,
            keyboardType: keyboardType,
            // Correct hints are what let a password manager offer to fill and
            // to save; the wrong ones stop it silently.
            autofillHints: autofillHints,
            textInputAction: textInputAction,
            textCapitalization: textCapitalization,
            style: inter(15, 520, color: scheme.onSurface),
            onSubmitted: onSubmitted,
            onChanged: onChanged,
            decoration: InputDecoration(
              hintText: hintText,
              errorText: errorText,
              suffixIcon: onToggleObscure == null
                  ? null
                  : IconButton(
                      onPressed: onToggleObscure,
                      tooltip: obscure ? 'Show password' : 'Hide password',
                      icon: Icon(
                        obscure
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                        size: 20,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../../core/theme/palette.dart';
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
    return Scaffold(
      backgroundColor: FlowColors.ink,
      appBar: showBack
          ? AppBar(
              backgroundColor: Colors.transparent,
              foregroundColor: FlowColors.mist,
              elevation: 0,
            )
          : null,
      extendBodyBehindAppBar: true,
      body: WaveBackdrop(
        child: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(28, 8, 28, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 8),
                      Text(title,
                          style: sora(30, 780,
                              color: FlowColors.mist,
                              spacing: -.8,
                              height: 1.12)),
                      const SizedBox(height: 10),
                      Text(subtitle,
                          style: inter(14.5, 460,
                              color: FlowColors.haze, height: 1.45)),
                      const SizedBox(height: 28),
                      ...children,
                    ],
                  ),
                ),
              ),
              if (footer != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(28, 0, 28, 14),
                  child: footer,
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
    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      alignment: Alignment.topCenter,
      child: message == null
          ? const SizedBox(width: double.infinity)
          : Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 18),
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              decoration: BoxDecoration(
                color: FlowColors.coral.withValues(alpha: .13),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: FlowColors.coral.withValues(alpha: .45)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.error_outline_rounded,
                      size: 18, color: FlowColors.coral),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(message!,
                        style: inter(13.5, 500,
                            color: FlowColors.mist, height: 1.35)),
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
    return Container(
      margin: const EdgeInsets.only(bottom: 18),
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      decoration: BoxDecoration(
        color: FlowColors.azure.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: FlowColors.azure.withValues(alpha: .4)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(message,
                style: inter(13.5, 500,
                    color: FlowColors.mist, height: 1.35)),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: onAction,
            child: Text(actionLabel,
                style: inter(13.5, 700, color: FlowColors.azure)),
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label.toUpperCase(), style: microLabel(FlowColors.haze)),
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
            style: inter(15.5, 520, color: FlowColors.mist),
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
                        color: FlowColors.haze,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

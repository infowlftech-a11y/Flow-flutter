import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/typography.dart';
import '../../core/utils/haptics.dart';
import '../../core/widgets/buttons.dart';
import 'auth_controller.dart';
import 'auth_validators.dart';
import 'auth_widgets.dart';

/// Password reset, as its own screen.
///
/// Previously this was a link on the combined form that reused whatever was
/// in the email box — so tapping it with an empty or half-typed field put an
/// error under an input the user had not been asked to fill yet. Here the
/// single field *is* the request.
class ResetPasswordScreen extends ConsumerStatefulWidget {
  const ResetPasswordScreen({super.key});

  @override
  ConsumerState<ResetPasswordScreen> createState() =>
      _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends ConsumerState<ResetPasswordScreen> {
  late final TextEditingController _email;
  final _emailFocus = FocusNode();

  bool _attempted = false;
  bool _sent = false;

  @override
  void initState() {
    super.initState();
    _email = TextEditingController(text: ref.read(authEmailProvider));
  }

  @override
  void dispose() {
    _email.dispose();
    _emailFocus.dispose();
    super.dispose();
  }

  String? get _emailError =>
      _attempted ? AuthValidators.email(_email.text) : null;

  Future<void> _send() async {
    if (ref.read(authControllerProvider).busy) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _attempted = true);
    if (_emailError != null) {
      Haptics.error();
      _emailFocus.requestFocus();
      return;
    }

    ref.read(authEmailProvider.notifier).set(_email.text);
    final ok = await ref
        .read(authControllerProvider.notifier)
        .sendPasswordReset(_email.text);
    if (!mounted || !ok) return;
    Haptics.medium();
    setState(() => _sent = true);
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);

    if (_sent) return _SentState(email: _email.text.trim(), onResend: _resend);

    return AuthScaffold(
      title: 'Reset your password',
      subtitle:
          'Enter the email you signed up with and we’ll send you a link.',
      children: [
        AuthBanner(message: auth.banner),
        AuthTextField(
          label: 'Email',
          controller: _email,
          focusNode: _emailFocus,
          hintText: 'you@example.com',
          errorText: auth.fieldErrors[AuthField.email] ?? _emailError,
          keyboardType: TextInputType.emailAddress,
          autofillHints: const [AutofillHints.username],
          textInputAction: TextInputAction.done,
          enabled: !auth.busy,
          autofocus: _email.text.isEmpty,
          onChanged: (_) {
            ref
                .read(authControllerProvider.notifier)
                .clearFieldError(AuthField.email);
            if (_attempted) setState(() {});
          },
          onSubmitted: (_) => _send(),
        ),
        const SizedBox(height: 10),
        PrimaryButton(
          label: 'Send reset link',
          busy: auth.busy,
          onPressed: _send,
        ),
      ],
    );
  }

  void _resend() {
    setState(() => _sent = false);
    _send();
  }
}

/// Deliberately identical whether or not an account exists for that address.
///
/// Saying "no account found" here would turn this form into a checker for
/// which emails are registered on the platform. The wording is therefore
/// conditional — "if you have an account" — which is both honest and
/// enumeration-safe.
class _SentState extends StatelessWidget {
  const _SentState({required this.email, required this.onResend});

  final String email;
  final VoidCallback onResend;

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      title: 'Check your inbox',
      subtitle: 'If an account exists for $email, a reset link is on its way.',
      children: [
        const SizedBox(height: 8),
        Center(
          child: Container(
            padding: const EdgeInsets.all(26),
            decoration: BoxDecoration(
              color: context.scheme.primary.withValues(alpha: .12),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.mark_email_read_outlined,
                size: 46, color: context.scheme.primary),
          ),
        ),
        const SizedBox(height: 28),
        Text(
          'The link expires after an hour. If it hasn’t arrived in a few '
          'minutes, check your spam folder — then try again.',
          style: inter(14, 460, color: context.scheme.onSurfaceVariant, height: 1.5),
        ),
        const SizedBox(height: 24),
        PrimaryButton(
          label: 'Back to sign in',
          onPressed: () {
            Haptics.select();
            context.pushReplacement('/auth/sign-in');
          },
        ),
        const SizedBox(height: 10),
        TextButton(
          onPressed: onResend,
          child: Text('Send it again',
              style: inter(14, 600, color: context.scheme.primary)),
        ),
      ],
    );
  }
}

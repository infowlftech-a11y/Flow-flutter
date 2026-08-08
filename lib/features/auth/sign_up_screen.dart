import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/motion.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/typography.dart';
import '../../core/utils/haptics.dart';
import '../../core/widgets/buttons.dart';
import 'auth_controller.dart';
import 'auth_validators.dart';
import 'auth_widgets.dart';

/// Create account — email, password, confirm password.
///
/// Credentials and nothing else. The name used to live here too, which meant
/// the very first thing the app asked for was a value it then asked for again
/// on the onboarding form a screen later — the profile document is the only
/// place `name` is ever read from, so the sign-up copy was decoration. It is
/// now collected once, in the form that owns it.
class SignUpScreen extends ConsumerStatefulWidget {
  const SignUpScreen({super.key});

  @override
  ConsumerState<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends ConsumerState<SignUpScreen> {
  late final TextEditingController _email;
  final _password = TextEditingController();
  final _confirm = TextEditingController();

  final _emailFocus = FocusNode();
  final _passwordFocus = FocusNode();
  final _confirmFocus = FocusNode();

  /// One toggle governs both password fields. Revealing one and not the other
  /// would let a typo hide in the field you cannot see, which is the whole
  /// thing the confirmation exists to catch.
  bool _obscure = true;
  bool _attempted = false;

  /// Set the first time the confirmation loses focus. Until then a mismatch
  /// is almost certainly just "still typing", and flagging it mid-keystroke
  /// makes the form feel like it is arguing with you.
  bool _confirmTouched = false;

  @override
  void initState() {
    super.initState();
    _email = TextEditingController(text: ref.read(authEmailProvider));
    _confirmFocus.addListener(_onConfirmFocusChange);
  }

  void _onConfirmFocusChange() {
    if (!_confirmFocus.hasFocus && _confirm.text.isNotEmpty && !_confirmTouched) {
      setState(() => _confirmTouched = true);
    }
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    _confirmFocus.removeListener(_onConfirmFocusChange);
    _confirmFocus.dispose();
    super.dispose();
  }

  AuthController get _controller => ref.read(authControllerProvider.notifier);

  String? get _emailError =>
      _attempted ? AuthValidators.email(_email.text) : null;
  String? get _passwordError =>
      _attempted ? AuthValidators.password(_password.text, signUp: true) : null;
  String? get _confirmError => (_attempted || _confirmTouched)
      ? AuthValidators.confirmPassword(_confirm.text, _password.text)
      : null;

  /// The quiet reassurance that the two match, shown only once there is
  /// something to be reassured about.
  bool get _confirmMatches =>
      _confirm.text.isNotEmpty &&
      _confirm.text == _password.text &&
      _password.text.length >= AuthValidators.minPasswordLength;

  Future<void> _submit() async {
    if (ref.read(authControllerProvider).busy) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _attempted = true;
      _confirmTouched = true;
    });

    if (_emailError != null || _passwordError != null || _confirmError != null) {
      Haptics.error();
      (_emailError != null
              ? _emailFocus
              : _passwordError != null
                  ? _passwordFocus
                  : _confirmFocus)
          .requestFocus();
      return;
    }

    ref.read(authEmailProvider.notifier).set(_email.text);
    final ok = await _controller.signUp(
      email: _email.text,
      password: _password.text,
    );
    if (ok) Haptics.medium();
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    final strength = PasswordStrength.of(_password.text);

    return AuthScaffold(
      title: 'Create your account',
      subtitle: 'Email and a password. You choose rider or trainer next.',
      footer: TextButton(
        onPressed: auth.busy ? null : () => _switchTo('/auth/sign-in'),
        child: RichText(
          text: TextSpan(
            style: inter(14, 460, color: context.scheme.onSurfaceVariant),
            children: [
              const TextSpan(text: 'Already have an account?  '),
              TextSpan(
                  text: 'Sign in',
                  style: inter(14, 700, color: context.scheme.primary)),
            ],
          ),
        ),
      ),
      children: [
        AuthBanner(message: auth.banner),
        if (auth.recovery == AuthRecovery.accountExists)
          AuthRecoveryCard(
            message: 'That email already has an account.',
            actionLabel: 'Sign in',
            onAction: () => _switchTo('/auth/sign-in'),
          ),
        AutofillGroup(
          child: Column(
            children: [
              AuthTextField(
                label: 'Email',
                controller: _email,
                focusNode: _emailFocus,
                hintText: 'you@example.com',
                errorText: auth.fieldErrors[AuthField.email] ?? _emailError,
                keyboardType: TextInputType.emailAddress,
                // `newUsername` tells the password manager this is a
                // registration, so it offers to *save* rather than to fill.
                autofillHints: const [AutofillHints.newUsername],
                enabled: !auth.busy,
                autofocus: true,
                onChanged: (_) {
                  _controller.clearFieldError(AuthField.email);
                  if (_attempted) setState(() {});
                },
                onSubmitted: (_) => _passwordFocus.requestFocus(),
              ),
              AuthTextField(
                label: 'Password',
                controller: _password,
                focusNode: _passwordFocus,
                hintText:
                    'At least ${AuthValidators.minPasswordLength} characters',
                errorText:
                    auth.fieldErrors[AuthField.password] ?? _passwordError,
                obscure: _obscure,
                onToggleObscure: () => setState(() => _obscure = !_obscure),
                autofillHints: const [AutofillHints.newPassword],
                enabled: !auth.busy,
                onChanged: (_) {
                  _controller.clearFieldError(AuthField.password);
                  // Rebuilds the strength meter and re-tests the confirmation
                  // against the new value — editing the password after
                  // confirming must not leave a stale "match".
                  setState(() {});
                },
                onSubmitted: (_) => _confirmFocus.requestFocus(),
              ),
              // Advisory only — it never blocks beyond the 6-character floor.
              AnimatedSize(
                duration: FlowMotion.base,
                alignment: Alignment.topCenter,
                child: _password.text.isEmpty
                    ? const SizedBox(width: double.infinity)
                    : _StrengthMeter(strength: strength),
              ),
              AuthTextField(
                label: 'Confirm password',
                controller: _confirm,
                focusNode: _confirmFocus,
                hintText: 'Type it once more',
                errorText: _confirmError,
                obscure: _obscure,
                onToggleObscure: () => setState(() => _obscure = !_obscure),
                // Same hint as the field above: the platform manager treats
                // the pair as one new credential rather than two.
                autofillHints: const [AutofillHints.newPassword],
                textInputAction: TextInputAction.done,
                enabled: !auth.busy,
                onChanged: (_) {
                  _controller.clearFeedback();
                  setState(() {});
                },
                onSubmitted: (_) => _submit(),
              ),
            ],
          ),
        ),
        AnimatedSize(
          duration: FlowMotion.base,
          alignment: Alignment.topCenter,
          child: _confirmMatches && _confirmError == null
              ? const _MatchHint()
              : const SizedBox(width: double.infinity),
        ),
        const SizedBox(height: 20),
        PrimaryButton(
          label: 'Create account',
          busy: auth.busy,
          onPressed: _submit,
        ),
      ],
    );
  }

  void _switchTo(String route) {
    Haptics.select();
    ref.read(authEmailProvider.notifier).set(_email.text);
    _controller.reset();
    context.pushReplacement(route);
  }
}

/// Confirms the pair matches without shouting about it. The absence of an
/// error is ambiguous while you are still typing; this is not.
class _MatchHint extends StatelessWidget {
  const _MatchHint();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Icon(Icons.check_circle_outline_rounded,
              size: 16, color: context.tones.success),
          const SizedBox(width: 8),
          Text('Passwords match',
              style: inter(12.5, 600, color: context.tones.success)),
        ],
      ),
    );
  }
}

class _StrengthMeter extends StatelessWidget {
  const _StrengthMeter({required this.strength});

  final PasswordStrength strength;

  /// Takes the context rather than reading a getter: these are theme tones
  /// now, and the light theme needs deeper shades than the dark one.
  Color _color(BuildContext context) => switch (strength) {
        PasswordStrength.weak => context.tones.danger,
        PasswordStrength.fair => context.tones.warning,
        PasswordStrength.strong => context.tones.success,
      };

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Row(
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: TweenAnimationBuilder<double>(
                duration: FlowMotion.base,
                curve: Curves.easeOutCubic,
                tween: Tween(begin: 0, end: strength.fraction),
                builder: (_, value, _) => LinearProgressIndicator(
                  value: value,
                  minHeight: 5,
                  backgroundColor: context.scheme.onSurface.withValues(alpha: .14),
                  valueColor: AlwaysStoppedAnimation(_color(context)),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(strength.label, style: inter(12.5, 640, color: _color(context))),
        ],
      ),
    );
  }
}

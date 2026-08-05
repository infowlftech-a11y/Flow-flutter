import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/palette.dart';
import '../../core/theme/typography.dart';
import '../../core/utils/haptics.dart';
import '../../core/widgets/buttons.dart';
import 'auth_controller.dart';
import 'auth_validators.dart';
import 'auth_widgets.dart';

/// Sign in — email + password, and nothing else.
class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key});

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  late final TextEditingController _email;
  final _password = TextEditingController();

  final _emailFocus = FocusNode();
  final _passwordFocus = FocusNode();

  bool _obscure = true;
  bool _attempted = false;

  @override
  void initState() {
    super.initState();
    // Whatever was typed on Welcome / Create account / Reset comes with them.
    _email = TextEditingController(text: ref.read(authEmailProvider));
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  AuthController get _controller => ref.read(authControllerProvider.notifier);

  // Local rules only surface once they have tried — validating an untouched
  // form in red is nagging, not helping.
  String? get _emailError =>
      _attempted ? AuthValidators.email(_email.text) : null;
  String? get _passwordError => _attempted
      ? AuthValidators.password(_password.text, signUp: false)
      : null;

  Future<void> _submit() async {
    if (ref.read(authControllerProvider).busy) return;
    // Settle the IME first so the platform text-input and autofill sessions
    // close cleanly rather than being torn down mid-submit by a rebuild.
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _attempted = true);

    if (_emailError != null || _passwordError != null) {
      Haptics.error();
      // Put the cursor where the fix is.
      (_emailError != null ? _emailFocus : _passwordFocus).requestFocus();
      return;
    }

    ref.read(authEmailProvider.notifier).set(_email.text);
    final ok = await _controller.signIn(
      email: _email.text,
      password: _password.text,
    );
    if (ok) Haptics.medium();
    // On success the auth stream flips the session and the router replaces
    // this screen — there is nothing to navigate to from here.
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    final serverEmail = auth.fieldErrors[AuthField.email];
    final serverPassword = auth.fieldErrors[AuthField.password];

    return AuthScaffold(
      title: 'Welcome back',
      subtitle: 'Sign in to pick up where you left off.',
      footer: TextButton(
        onPressed: auth.busy ? null : () => _switchTo('/auth/sign-up'),
        child: RichText(
          text: TextSpan(
            style: inter(14, 460, color: FlowColors.haze),
            children: [
              const TextSpan(text: 'New to FLOW?  '),
              TextSpan(
                  text: 'Create an account',
                  style: inter(14, 700, color: FlowColors.azure)),
            ],
          ),
        ),
      ),
      children: [
        AuthBanner(message: auth.banner),
        if (auth.recovery == AuthRecovery.noAccount)
          AuthRecoveryCard(
            message: 'No account uses that email yet.',
            actionLabel: 'Sign up',
            onAction: () => _switchTo('/auth/sign-up'),
          ),
        AutofillGroup(
          child: Column(
            children: [
              AuthTextField(
                label: 'Email',
                controller: _email,
                focusNode: _emailFocus,
                hintText: 'you@example.com',
                errorText: serverEmail ?? _emailError,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.username],
                enabled: !auth.busy,
                autofocus: _email.text.isEmpty,
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
                hintText: 'Your password',
                errorText: serverPassword ?? _passwordError,
                obscure: _obscure,
                onToggleObscure: () => setState(() => _obscure = !_obscure),
                autofillHints: const [AutofillHints.password],
                textInputAction: TextInputAction.done,
                enabled: !auth.busy,
                autofocus: _email.text.isNotEmpty,
                onChanged: (_) {
                  _controller.clearFieldError(AuthField.password);
                  if (_attempted) setState(() {});
                },
                onSubmitted: (_) => _submit(),
              ),
            ],
          ),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: auth.busy ? null : () => _switchTo('/auth/reset'),
            child: Text('Forgot password?',
                style: inter(13.5, 600, color: FlowColors.azure)),
          ),
        ),
        const SizedBox(height: 10),
        PrimaryButton(
          label: 'Sign in',
          busy: auth.busy,
          onPressed: _submit,
        ),
      ],
    );
  }

  /// Moves to a sibling auth route, taking the typed email along and dropping
  /// errors that belonged to the screen being left.
  void _switchTo(String route) {
    Haptics.select();
    ref.read(authEmailProvider.notifier).set(_email.text);
    _controller.reset();
    context.pushReplacement(route);
  }
}

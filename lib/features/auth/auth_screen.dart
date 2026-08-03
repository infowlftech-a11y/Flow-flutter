import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/palette.dart';
import '../../core/theme/typography.dart';
import '../../core/utils/haptics.dart';
import '../../core/widgets/brand.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/feedback.dart';
import 'auth_controller.dart';
import 'auth_validators.dart';

/// Log in ⇄ Create account on one screen (§3.1). Firebase persists the
/// session itself — no "remember me", no credential storage.
///
/// Submitting by keyboard and by button take the identical path: both call
/// [_submit], which settles the IME, validates, then hands off to
/// [AuthController]. The widget owns no submission state of its own.
class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  final _formKey = GlobalKey<FormState>();

  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();

  final _nameFocus = FocusNode();
  final _emailFocus = FocusNode();
  final _passwordFocus = FocusNode();

  bool _obscure = true;

  @override
  void initState() {
    super.initState();
    // Drives the live password-strength meter on sign-up.
    _password.addListener(_onPasswordChanged);
  }

  @override
  void dispose() {
    _password.removeListener(_onPasswordChanged);
    _name.dispose();
    _email.dispose();
    _password.dispose();
    _nameFocus.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  void _onPasswordChanged() {
    if (ref.read(authControllerProvider).isSignUp) setState(() {});
  }

  AuthController get _controller => ref.read(authControllerProvider.notifier);

  /// The single submission path — keyboard and button both land here.
  Future<void> _submit() async {
    final auth = ref.read(authControllerProvider);
    if (auth.busy) return;

    // Settle the IME *before* touching state. Doing this first means the
    // platform text-input connection and autofill session are closed cleanly
    // rather than being torn down mid-submit by a rebuild.
    FocusManager.instance.primaryFocus?.unfocus();

    if (!(_formKey.currentState?.validate() ?? false)) {
      Haptics.error();
      return;
    }

    final ok = await _controller.submit(
      name: _name.text,
      email: _email.text,
      password: _password.text,
    );
    if (ok) Haptics.medium();
    // On success the auth stream flips the session and the router replaces
    // this screen — there is nothing to navigate to from here.
  }

  Future<void> _resetPassword() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final sent = await _controller.sendPasswordReset(_email.text);
    if (!mounted) return;
    if (!sent) {
      // The controller put the reason under the email field; put the cursor
      // where the fix is.
      _emailFocus.requestFocus();
      _formKey.currentState?.validate();
      return;
    }
    showFlowToast(context, 'Reset link sent to ${_email.text.trim()}',
        icon: Icons.mark_email_read_outlined);
  }

  void _switchMode(AuthMode mode) {
    Haptics.select();
    // Deliberately keeps whatever they've typed — switching modes mid-entry
    // shouldn't cost them their email. `setMode` drops server-side errors;
    // any stale local error re-evaluates on their next keystroke or submit.
    _controller.setMode(mode);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    final signUp = auth.isSignUp;

    return Scaffold(
      backgroundColor: FlowColors.ink,
      body: WaveBackdrop(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
              child: AutofillGroup(
                child: Form(
                  key: _formKey,
                  // Quiet until the user has actually interacted, then live.
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Center(child: FlowLogo(size: 84)),
                      const SizedBox(height: 18),
                      const Center(child: FlowWordmark()),
                      const SizedBox(height: 36),
                      _ModeSwitch(
                        signUp: signUp,
                        onChanged: auth.busy ? null : _switchMode,
                      ),
                      const SizedBox(height: 22),
                      _Banner(message: auth.banner),
                      // Name — sign-up only.
                      AnimatedSize(
                        duration: const Duration(milliseconds: 220),
                        curve: Curves.easeOutCubic,
                        alignment: Alignment.topCenter,
                        child: signUp
                            ? Padding(
                                padding: const EdgeInsets.only(bottom: 14),
                                child: _AuthField(
                                  controller: _name,
                                  focusNode: _nameFocus,
                                  hint: 'Full name',
                                  icon: Icons.person_outline_rounded,
                                  textCapitalization: TextCapitalization.words,
                                  autofillHints: const [AutofillHints.name],
                                  readOnly: auth.busy,
                                  textInputAction: TextInputAction.next,
                                  onSubmitted: (_) =>
                                      _emailFocus.requestFocus(),
                                  onChanged: (_) => _controller
                                      .clearFieldError(AuthField.name),
                                  validator: (value) =>
                                      auth.fieldErrors[AuthField.name] ??
                                      AuthValidators.name(value),
                                ),
                              )
                            : const SizedBox.shrink(),
                      ),
                      _AuthField(
                        controller: _email,
                        focusNode: _emailFocus,
                        hint: 'Email',
                        icon: Icons.alternate_email_rounded,
                        keyboardType: TextInputType.emailAddress,
                        autofillHints: const [AutofillHints.email],
                        readOnly: auth.busy,
                        textInputAction: TextInputAction.next,
                        onSubmitted: (_) => _passwordFocus.requestFocus(),
                        onChanged: (_) =>
                            _controller.clearFieldError(AuthField.email),
                        validator: (value) =>
                            auth.fieldErrors[AuthField.email] ??
                            AuthValidators.email(value),
                      ),
                      const SizedBox(height: 14),
                      _AuthField(
                        controller: _password,
                        focusNode: _passwordFocus,
                        hint: 'Password',
                        icon: Icons.lock_outline_rounded,
                        obscure: _obscure,
                        autofillHints: [
                          signUp
                              ? AutofillHints.newPassword
                              : AutofillHints.password,
                        ],
                        readOnly: auth.busy,
                        // Enter on the last field submits the form.
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _submit(),
                        onChanged: (_) =>
                            _controller.clearFieldError(AuthField.password),
                        validator: (value) =>
                            auth.fieldErrors[AuthField.password] ??
                            AuthValidators.password(value, signUp: signUp),
                        suffix: IconButton(
                          onPressed: () =>
                              setState(() => _obscure = !_obscure),
                          tooltip:
                              _obscure ? 'Show password' : 'Hide password',
                          icon: Icon(
                            _obscure
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                            color: FlowColors.slate,
                            size: 21,
                          ),
                        ),
                      ),
                      if (signUp)
                        _StrengthMeter(password: _password.text)
                      else
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: auth.busy ? null : _resetPassword,
                            child: Text('Forgot password?',
                                style:
                                    inter(13.5, 620, color: FlowColors.azure)),
                          ),
                        ),
                      const SizedBox(height: 18),
                      PrimaryButton(
                        label: signUp ? 'Create account' : 'Log in',
                        busy: auth.busy,
                        onPressed: _submit,
                      ),
                      const SizedBox(height: 20),
                      Center(
                        child: Text(
                          signUp
                              ? 'Trainers are verified before going live.'
                              : 'Certified trainers. Real availability.',
                          style: inter(12.5, 460, color: FlowColors.slate),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Form-level errors only — anything not attributable to a single field.
class _Banner extends StatelessWidget {
  const _Banner({required this.message});
  final String? message;

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: message == null
          ? const SizedBox.shrink()
          : Semantics(
              liveRegion: true,
              child: Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: FlowColors.coral.withValues(alpha: .14),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: FlowColors.coral.withValues(alpha: .4)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline_rounded,
                        color: FlowColors.coral, size: 19),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(message!,
                          style: inter(13.5, 560, color: FlowColors.mist)),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

class _ModeSwitch extends StatelessWidget {
  const _ModeSwitch({required this.signUp, required this.onChanged});

  final bool signUp;
  final ValueChanged<AuthMode>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 52,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: FlowColors.navy900,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: FlowColors.navy700),
      ),
      child: Row(
        children: [
          _segment('Log in', !signUp, AuthMode.logIn),
          _segment('Create account', signUp, AuthMode.signUp),
        ],
      ),
    );
  }

  Widget _segment(String label, bool active, AuthMode mode) => Expanded(
        child: Semantics(
          button: true,
          selected: active,
          child: GestureDetector(
            onTap: onChanged == null ? null : () => onChanged!(mode),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              decoration: BoxDecoration(
                color: active ? FlowColors.azure : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
              ),
              alignment: Alignment.center,
              child: Text(
                label,
                style: inter(14, 660,
                    color: active ? FlowColors.ink : FlowColors.haze),
              ),
            ),
          ),
        ),
      );
}

/// Advisory strength feedback on sign-up (never blocks beyond the 6-char
/// floor, which the validator owns).
class _StrengthMeter extends StatelessWidget {
  const _StrengthMeter({required this.password});
  final String password;

  @override
  Widget build(BuildContext context) {
    if (password.isEmpty) return const SizedBox(height: 18);
    final strength = PasswordStrength.of(password);
    final color = switch (strength) {
      PasswordStrength.weak => FlowColors.coral,
      PasswordStrength.fair => FlowColors.amber,
      PasswordStrength.strong => FlowColors.emerald,
    };

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: TweenAnimationBuilder<double>(
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutCubic,
                tween: Tween(begin: 0, end: strength.fraction),
                builder: (context, value, _) => LinearProgressIndicator(
                  value: value,
                  minHeight: 4,
                  color: color,
                  backgroundColor: FlowColors.navy700,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text(strength.label, style: inter(11.5, 700, color: color)),
        ],
      ),
    );
  }
}

/// Brand-styled field on the dark auth backdrop.
///
/// Note it is never `enabled: false` while submitting — disabling a focused
/// field destroys its input connection and unregisters it from the enclosing
/// AutofillGroup mid-flight. `readOnly` blocks edits and keeps both intact.
class _AuthField extends StatelessWidget {
  const _AuthField({
    required this.controller,
    required this.hint,
    required this.icon,
    this.focusNode,
    this.obscure = false,
    this.keyboardType,
    this.autofillHints,
    this.suffix,
    this.readOnly = false,
    this.textInputAction,
    this.textCapitalization = TextCapitalization.none,
    this.onSubmitted,
    this.onChanged,
    this.validator,
  });

  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final FocusNode? focusNode;
  final bool obscure;
  final TextInputType? keyboardType;
  final List<String>? autofillHints;
  final Widget? suffix;
  final bool readOnly;
  final TextInputAction? textInputAction;
  final TextCapitalization textCapitalization;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;
  final FormFieldValidator<String>? validator;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      focusNode: focusNode,
      obscureText: obscure,
      keyboardType: keyboardType,
      autofillHints: autofillHints,
      readOnly: readOnly,
      textInputAction: textInputAction,
      textCapitalization: textCapitalization,
      onFieldSubmitted: onSubmitted,
      onChanged: onChanged,
      validator: validator,
      style: inter(15, 520, color: FlowColors.mist),
      cursorColor: FlowColors.azure,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: inter(15, 420, color: FlowColors.slate),
        prefixIcon: Icon(icon, color: FlowColors.slate, size: 21),
        suffixIcon: suffix,
        filled: true,
        fillColor: FlowColors.navy900,
        errorStyle: inter(12.5, 560, color: FlowColors.coral),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: FlowColors.navy700),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: FlowColors.azure, width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: FlowColors.coral),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: FlowColors.coral, width: 1.6),
        ),
      ),
    );
  }
}

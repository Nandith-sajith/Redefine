import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:redefine_core/redefine_core.dart';

import 'async.dart';
import 'report.dart';
import 'session.dart';
import 'theme.dart';
import 'widgets.dart';

/// Per-app persona configuration for the shared auth screens.
class AuthPersona {
  const AuthPersona({
    required this.role,
    required this.label,
    required this.icon,
    required this.loginSubtitle,
    required this.signupTitle,
    required this.signupSubtitle,
    this.pillBg = RColors.tealTint,
    this.pillFg = RColors.tealDeep,
    this.demoEmail = '',
    this.demoPassword = '',
    this.allowSignup = true,
    this.extra,
  });

  final String role; // 'admin' | 'crew' | 'customer'
  final String label; // 'ADMIN'
  final IconData icon;
  final Color pillBg, pillFg;
  final String loginSubtitle;
  final String signupTitle, signupSubtitle;

  /// Prefilled on the login screen in debug builds only.
  final String demoEmail, demoPassword;

  /// Whether the login screen links to sign-up.
  final bool allowSignup;
  final AuthExtraField? extra; // extra signup field (phone / invite code)
}

class AuthExtraField {
  const AuthExtraField({
    required this.key,
    required this.label,
    required this.icon,
    required this.placeholder,
  });
  final String key; // 'phone' | 'inviteCode'
  final String label;
  final IconData icon;
  final String placeholder;
}

final _emailShape = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

String? _checkEmail(String email) {
  if (email.isEmpty) return 'Enter your email.';
  return _emailShape.hasMatch(email) ? null : "That doesn't look like an email address.";
}

/// What to show when signing in or up fails. Anything but an [ApiException]
/// is a bug: it is logged, and still shown, so that the button never just
/// seems to do nothing.
String _failureMessage(Object error, StackTrace stack, String doing) {
  if (error is! ApiException) reportBug(error, stack, doing);
  return friendlyError(error);
}

// ---------------------------------------------------------------------------
/// Signs in through the enclosing [SessionScope]; the app's gate swaps this
/// screen out once the session is signed in.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.persona});
  final AuthPersona persona;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _emailFocus = FocusNode();
  final _passwordFocus = FocusNode();
  String? _emailError, _passwordError, _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    if (kDebugMode) {
      _email.text = widget.persona.demoEmail;
      _password.text = widget.persona.demoPassword;
    }
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    final email = _email.text.trim();
    final password = _password.text;
    final emailError = _checkEmail(email);
    final passwordError = password.isEmpty ? 'Enter your password.' : null;
    setState(() {
      _emailError = emailError;
      _passwordError = passwordError;
      _error = null;
    });
    final invalid = emailError != null
        ? _emailFocus
        : passwordError != null
        ? _passwordFocus
        : null;
    if (invalid != null) {
      invalid.requestFocus();
      return;
    }

    setState(() => _busy = true);
    try {
      // On success the session changes and the gate replaces this screen.
      await SessionScope.of(context, listen: false).login(email, password);
    } catch (e, stack) {
      final message = _failureMessage(e, stack, 'while signing in');
      if (!mounted) return;
      setState(() => _error = message);
      _refocus(_passwordFocus);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // Deferred: the field cannot take focus until it is rebuilt enabled.
  void _refocus(FocusNode node) => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (mounted) node.requestFocus();
  });

  void _openSignup() => Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => SignupScreen(persona: widget.persona)));

  @override
  Widget build(BuildContext context) {
    final p = widget.persona;
    final notice = SessionScope.of(context).notice;
    return AuthScaffold(
      children: [
        const RWordmark(),
        const SizedBox(height: 24),
        _Hero(persona: p, title: 'Welcome back', subtitle: p.loginSubtitle),
        const SizedBox(height: 24),
        if (_error != null) ...[
          RBanner(_error!, error: true),
          const SizedBox(height: 16),
        ] else if (notice != null) ...[
          RBanner(notice),
          const SizedBox(height: 16),
        ],
        AutofillGroup(
          child: Column(
            children: [
              RTextField(
                label: 'Email',
                icon: Icons.mail_outline,
                hint: 'you@example.com',
                controller: _email,
                focusNode: _emailFocus,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.username, AutofillHints.email],
                enabled: !_busy,
                errorText: _emailError,
                onSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: 14),
              RTextField(
                label: 'Password',
                icon: Icons.lock_outline,
                hint: 'Enter your password',
                controller: _password,
                focusNode: _passwordFocus,
                obscure: true,
                autofillHints: const [AutofillHints.password],
                enabled: !_busy,
                errorText: _passwordError,
                onSubmitted: (_) => _submit(),
              ),
            ],
          ),
        ),
        const SizedBox(height: 22),
        RPrimaryButton('Log in', busy: _busy, onPressed: _submit),
        if (p.allowSignup) ...[
          const SizedBox(height: 18),
          _FooterLink(
            prompt: "Don't have an account?",
            action: 'Sign up',
            onTap: _busy ? null : _openSignup,
          ),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
/// Creates an account for the persona's role through the enclosing
/// [SessionScope]. Pushed on top of [LoginScreen]; a successful sign-up
/// re-keys the app, which drops this route.
class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key, required this.persona});
  final AuthPersona persona;

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _name = TextEditingController();
  final _extra = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _nameFocus = FocusNode();
  final _extraFocus = FocusNode();
  final _emailFocus = FocusNode();
  final _passwordFocus = FocusNode();
  String? _nameError, _extraError, _emailError, _passwordError, _error;
  bool _busy = false;

  bool get _needsInvite => widget.persona.extra?.key == 'inviteCode';

  @override
  void dispose() {
    for (final c in [_name, _extra, _email, _password]) {
      c.dispose();
    }
    for (final f in [_nameFocus, _extraFocus, _emailFocus, _passwordFocus]) {
      f.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    final name = _name.text.trim();
    final extra = _extra.text.trim();
    final email = _email.text.trim();
    final password = _password.text;
    final nameError = name.isEmpty
        ? 'Enter your name.'
        : name.length > 80
        ? 'Use 80 characters or fewer.'
        : null;
    final extraError = _needsInvite && extra.isEmpty ? 'Enter your invite code.' : null;
    final emailError = _checkEmail(email);
    final passwordError = password.length < 8 ? 'Use at least 8 characters.' : null;
    setState(() {
      _nameError = nameError;
      _extraError = extraError;
      _emailError = emailError;
      _passwordError = passwordError;
      _error = null;
    });
    final invalid = nameError != null
        ? _nameFocus
        : extraError != null
        ? _extraFocus
        : emailError != null
        ? _emailFocus
        : passwordError != null
        ? _passwordFocus
        : null;
    if (invalid != null) {
      invalid.requestFocus();
      return;
    }

    final extraKey = widget.persona.extra?.key;
    setState(() => _busy = true);
    try {
      // On success the session changes and the app drops this route.
      await SessionScope.of(context, listen: false).signup(
        name: name,
        email: email,
        password: password,
        phone: extraKey == 'phone' ? extra : null,
        inviteCode: extraKey == 'inviteCode' ? extra : null,
      );
    } catch (e, stack) {
      final message = _failureMessage(e, stack, 'while signing up');
      if (mounted) setState(() => _error = message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.persona;
    final extra = p.extra;
    return AuthScaffold(
      children: [
        const RWordmark(),
        const SizedBox(height: 24),
        _Hero(persona: p, title: p.signupTitle, subtitle: p.signupSubtitle),
        const SizedBox(height: 24),
        if (_error != null) ...[RBanner(_error!, error: true), const SizedBox(height: 16)],
        AutofillGroup(
          child: Column(
            children: [
              RTextField(
                label: 'Full name',
                icon: Icons.person_outline,
                hint: 'Your name',
                controller: _name,
                focusNode: _nameFocus,
                keyboardType: TextInputType.name,
                autofillHints: const [AutofillHints.name],
                enabled: !_busy,
                errorText: _nameError,
                onSubmitted: (_) => _submit(),
              ),
              if (extra != null) ...[
                const SizedBox(height: 14),
                RTextField(
                  label: extra.label,
                  icon: extra.icon,
                  hint: extra.placeholder,
                  controller: _extra,
                  focusNode: _extraFocus,
                  keyboardType: extra.key == 'phone' ? TextInputType.phone : null,
                  autofillHints: extra.key == 'phone'
                      ? const [AutofillHints.telephoneNumber]
                      : null,
                  enabled: !_busy,
                  errorText: _extraError,
                  onSubmitted: (_) => _submit(),
                ),
              ],
              const SizedBox(height: 14),
              RTextField(
                label: 'Email',
                icon: Icons.mail_outline,
                hint: 'you@example.com',
                controller: _email,
                focusNode: _emailFocus,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                enabled: !_busy,
                errorText: _emailError,
                onSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: 14),
              RTextField(
                label: 'Password',
                icon: Icons.lock_outline,
                hint: 'At least 8 characters',
                controller: _password,
                focusNode: _passwordFocus,
                obscure: true,
                autofillHints: const [AutofillHints.newPassword],
                enabled: !_busy,
                errorText: _passwordError,
                onSubmitted: (_) => _submit(),
              ),
            ],
          ),
        ),
        const SizedBox(height: 22),
        RPrimaryButton('Create account', busy: _busy, onPressed: _submit),
        const SizedBox(height: 18),
        _FooterLink(
          prompt: 'Already have an account?',
          action: 'Log in',
          onTap: _busy ? null : () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}

// ---- shared pieces --------------------------------------------------------
/// The scrollable page the auth screens (and other signed-out pages) sit on.
class AuthScaffold extends StatelessWidget {
  const AuthScaffold({super.key, required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: RColors.surface,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
        ),
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.persona, required this.title, required this.subtitle});
  final AuthPersona persona;
  final String title, subtitle;
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
          decoration: BoxDecoration(
            color: persona.pillBg,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(persona.icon, size: 13, color: persona.pillFg),
              const SizedBox(width: 6),
              Text(
                persona.label,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: persona.pillFg,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Text(
          title,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 28,
            fontWeight: FontWeight.w700,
            color: RColors.ink,
            letterSpacing: -0.5,
            height: 1.1,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          subtitle,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: RColors.inkMuted,
            height: 1.5,
          ),
        ),
      ],
    );
  }
}

class _FooterLink extends StatelessWidget {
  const _FooterLink({required this.prompt, required this.action, required this.onTap});
  final String prompt, action;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Center(
    // Wraps rather than overflows on a narrow window or with large text.
    child: Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          prompt,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: RColors.inkMuted,
          ),
        ),
        TextButton(
          onPressed: onTap,
          style: TextButton.styleFrom(
            foregroundColor: RColors.tealDeep,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            minimumSize: const Size(0, 32),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            textStyle: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          child: Text(action),
        ),
      ],
    ),
  );
}

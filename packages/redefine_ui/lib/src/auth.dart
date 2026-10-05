import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:redefine_core/redefine_core.dart';

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
    this.extra,
  });

  final String role; // 'admin' | 'crew' | 'customer'
  final String label; // 'ADMIN'
  final IconData icon;
  final Color pillBg, pillFg;
  final String loginSubtitle;
  final String signupTitle, signupSubtitle;
  final String demoEmail;
  final AuthExtraField? extra; // extra signup field (business / phone)
}

class AuthExtraField {
  const AuthExtraField({required this.key, required this.label, required this.icon, required this.placeholder});
  final String key; // 'business' | 'phone'
  final String label;
  final IconData icon;
  final String placeholder;
}

// ---------------------------------------------------------------------------
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.persona, required this.api, required this.home});
  final AuthPersona persona;
  final ApiClient api;
  final WidgetBuilder home;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _email.text = widget.persona.demoEmail;
    _password.text = 'redefine';
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _busy = true);
    try {
      final res = await widget.api.login(_email.text.trim(), _password.text);
      if (!mounted) return;
      _goHome(context, widget.home);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Welcome back, ${res.user.name.split(' ').first} 👋')));
    } on AuthException catch (e) {
      _error(context, e.message);
    } catch (_) {
      _error(context, "Couldn't reach the server. Please try again.");
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.persona;
    return AuthScaffold(children: [
      const _Wordmark(),
      const SizedBox(height: 24),
      _Hero(persona: p, title: 'Welcome back', subtitle: p.loginSubtitle),
      const SizedBox(height: 24),
      AuthField(label: 'EMAIL', icon: Icons.mail_outline, placeholder: 'you@example.com', controller: _email, keyboardType: TextInputType.emailAddress),
      const SizedBox(height: 14),
      AuthField(label: 'PASSWORD', icon: Icons.lock_outline, placeholder: 'Enter your password', controller: _password, password: true),
      const SizedBox(height: 10),
      Align(alignment: Alignment.centerRight, child: GestureDetector(
        onTap: () => _info(context, 'Password reset isn\'t wired up in this demo.'),
        child: Text('Forgot password?', style: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.w600, color: RColors.tealDeep)),
      )),
      const SizedBox(height: 20),
      RPrimaryButton(_busy ? 'Signing in…' : 'Log in', onPressed: _busy ? null : _submit),
      const SizedBox(height: 14),
      const _OrDivider(),
      const SizedBox(height: 14),
      _GoogleButton(onTap: () => _info(context, 'Google sign-in isn\'t set up in this demo.')),
      const SizedBox(height: 22),
      _FooterLink(
        prompt: "Don't have an account?",
        action: 'Sign up',
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => SignupScreen(persona: p, api: widget.api, home: widget.home))),
      ),
    ]);
  }
}

// ---------------------------------------------------------------------------
class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key, required this.persona, required this.api, required this.home});
  final AuthPersona persona;
  final ApiClient api;
  final WidgetBuilder home;

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _name = TextEditingController();
  final _extra = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _extra.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _busy = true);
    final p = widget.persona;
    try {
      final res = await widget.api.signup(
        name: _name.text.trim(),
        email: _email.text.trim(),
        password: _password.text,
        role: p.role,
        phone: p.extra?.key == 'phone' ? _extra.text.trim() : null,
        business: p.extra?.key == 'business' ? _extra.text.trim() : null,
      );
      if (!mounted) return;
      _goHome(context, widget.home);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Account created — welcome, ${res.user.name.split(' ').first} 🌱')));
    } on AuthException catch (e) {
      _error(context, e.message);
    } catch (_) {
      _error(context, "Couldn't reach the server. Please try again.");
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.persona;
    return AuthScaffold(children: [
      const _Wordmark(),
      const SizedBox(height: 24),
      _Hero(persona: p, title: p.signupTitle, subtitle: p.signupSubtitle),
      const SizedBox(height: 24),
      AuthField(label: 'FULL NAME', icon: Icons.person_outline, placeholder: 'Your name', controller: _name),
      if (p.extra != null) ...[
        const SizedBox(height: 14),
        AuthField(label: p.extra!.label, icon: p.extra!.icon, placeholder: p.extra!.placeholder, controller: _extra),
      ],
      const SizedBox(height: 14),
      AuthField(label: 'EMAIL', icon: Icons.mail_outline, placeholder: 'you@example.com', controller: _email, keyboardType: TextInputType.emailAddress),
      const SizedBox(height: 14),
      AuthField(label: 'PASSWORD', icon: Icons.lock_outline, placeholder: 'Create a password', controller: _password, password: true),
      const SizedBox(height: 20),
      RPrimaryButton(_busy ? 'Creating account…' : 'Create account', onPressed: _busy ? null : _submit),
      const SizedBox(height: 12),
      Text('By continuing you agree to our Terms of Service and Privacy Policy.',
          textAlign: TextAlign.center, style: GoogleFonts.plusJakartaSans(fontSize: 11, color: RColors.inkSoft, height: 1.45)),
      const SizedBox(height: 18),
      _FooterLink(prompt: 'Already have an account?', action: 'Log in', onTap: () => Navigator.of(context).pop()),
    ]);
  }
}

// ---- shared pieces --------------------------------------------------------
void _goHome(BuildContext context, WidgetBuilder home) =>
    Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: home), (r) => false);

void _error(BuildContext context, String msg) => ScaffoldMessenger.of(context)
    .showSnackBar(SnackBar(backgroundColor: const Color(0xFF8A2E2E), content: Text(msg)));

void _info(BuildContext context, String msg) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

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

class _Wordmark extends StatelessWidget {
  const _Wordmark();
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
        Text('redefine', style: GoogleFonts.plusJakartaSans(fontSize: 18, fontWeight: FontWeight.w700, color: RColors.tealDeep, letterSpacing: -0.3)),
        Text('.', style: GoogleFonts.plusJakartaSans(fontSize: 18, fontWeight: FontWeight.w700, color: RColors.lime)),
      ]);
}

class _Hero extends StatelessWidget {
  const _Hero({required this.persona, required this.title, required this.subtitle});
  final AuthPersona persona;
  final String title, subtitle;
  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
        decoration: BoxDecoration(color: persona.pillBg, borderRadius: BorderRadius.circular(999)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(persona.icon, size: 13, color: persona.pillFg),
          const SizedBox(width: 6),
          Text(persona.label, style: GoogleFonts.plusJakartaSans(fontSize: 11, fontWeight: FontWeight.w700, color: persona.pillFg, letterSpacing: 0.5)),
        ]),
      ),
      const SizedBox(height: 10),
      Text(title, style: GoogleFonts.plusJakartaSans(fontSize: 28, fontWeight: FontWeight.w700, color: RColors.ink, letterSpacing: -0.5, height: 1.1)),
      const SizedBox(height: 8),
      Text(subtitle, style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w500, color: RColors.inkMuted, height: 1.5)),
    ]);
  }
}

class AuthField extends StatefulWidget {
  const AuthField({super.key, required this.label, required this.icon, required this.placeholder, required this.controller, this.password = false, this.keyboardType});
  final String label, placeholder;
  final IconData icon;
  final TextEditingController controller;
  final bool password;
  final TextInputType? keyboardType;
  @override
  State<AuthField> createState() => _AuthFieldState();
}

class _AuthFieldState extends State<AuthField> {
  bool _show = false;
  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(widget.label, style: GoogleFonts.plusJakartaSans(fontSize: 11, fontWeight: FontWeight.w600, color: const Color(0xFF888888), letterSpacing: 0.5)),
      const SizedBox(height: 7),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(color: RColors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: RColors.border, width: 0.8)),
        child: Row(children: [
          Icon(widget.icon, size: 17, color: RColors.inkSoft),
          const SizedBox(width: 10),
          Expanded(child: TextField(
            controller: widget.controller,
            obscureText: widget.password && !_show,
            keyboardType: widget.keyboardType,
            cursorColor: RColors.teal,
            style: GoogleFonts.plusJakartaSans(fontSize: 14, color: RColors.ink),
            decoration: InputDecoration(
              isCollapsed: true,
              border: InputBorder.none,
              hintText: widget.placeholder,
              hintStyle: GoogleFonts.plusJakartaSans(fontSize: 14, color: RColors.inkSoft),
            ),
          )),
          if (widget.password)
            GestureDetector(
              onTap: () => setState(() => _show = !_show),
              child: Icon(_show ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 17, color: RColors.inkSoft),
            ),
        ]),
      ),
    ]);
  }
}

class _OrDivider extends StatelessWidget {
  const _OrDivider();
  @override
  Widget build(BuildContext context) => Row(children: [
        const Expanded(child: Divider(color: RColors.border, thickness: 0.8)),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: Text('or', style: GoogleFonts.plusJakartaSans(fontSize: 12, color: RColors.inkSoft))),
        const Expanded(child: Divider(color: RColors.border, thickness: 0.8)),
      ]);
}

class _GoogleButton extends StatelessWidget {
  const _GoogleButton({required this.onTap});
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => SizedBox(
        width: double.infinity,
        child: OutlinedButton(
          onPressed: onTap,
          style: OutlinedButton.styleFrom(
            foregroundColor: RColors.ink,
            side: const BorderSide(color: RColors.border, width: 0.8),
            padding: const EdgeInsets.symmetric(vertical: 13),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text('G', style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w700, color: const Color(0xFF4285F4))),
            const SizedBox(width: 10),
            Text('Continue with Google', style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w600, color: RColors.ink)),
          ]),
        ),
      );
}

class _FooterLink extends StatelessWidget {
  const _FooterLink({required this.prompt, required this.action, required this.onTap});
  final String prompt, action;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Center(
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(prompt, style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w500, color: RColors.inkMuted)),
          const SizedBox(width: 4),
          GestureDetector(onTap: onTap, child: Text(action, style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w600, color: RColors.tealDeep))),
        ]),
      );
}

import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';

import 'async.dart';
import 'auth.dart';
import 'session.dart';
import 'theme.dart';
import 'widgets.dart';

/// The root of each Redefine app: restores the session, then shows the login
/// screens or [home] depending on it.
///
/// The whole `MaterialApp` is keyed on [SessionController.epoch], so signing
/// in, signing out or an expired session drops every pushed route and all
/// per-user widget state.
class RedefineApp extends StatefulWidget {
  const RedefineApp({
    super.key,
    required this.title,
    required this.persona,
    required this.session,
    required this.home,
  });

  final String title;
  final AuthPersona persona;
  final SessionController session;

  /// Builds the signed-in app. Only called while the session is signed in.
  final WidgetBuilder home;

  @override
  State<RedefineApp> createState() => _RedefineAppState();
}

class _RedefineAppState extends State<RedefineApp> {
  late final ThemeData _theme = redefineTheme();

  @override
  void initState() {
    super.initState();
    _restore();
  }

  @override
  void didUpdateWidget(RedefineApp oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session != widget.session) _restore();
  }

  // A session that has already left `restoring` was restored by its owner.
  void _restore() {
    if (widget.session.status == SessionStatus.restoring) widget.session.restore();
  }

  @override
  Widget build(BuildContext context) {
    return SessionScope(
      session: widget.session,
      child: Builder(
        builder: (context) => MaterialApp(
          key: ValueKey(SessionScope.of(context).epoch),
          title: widget.title,
          theme: _theme,
          debugShowCheckedModeBanner: false,
          scrollBehavior: const _RScrollBehavior(),
          builder: (_, child) => RPhoneFrame(child: child!),
          home: AuthGate(persona: widget.persona, home: widget.home),
        ),
      ),
    );
  }
}

/// Web and Windows are mouse first: lists must also scroll, and pull to
/// refresh, by dragging with a mouse or trackpad.
class _RScrollBehavior extends MaterialScrollBehavior {
  const _RScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => const {
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.trackpad,
    PointerDeviceKind.stylus,
    PointerDeviceKind.invertedStylus,
    PointerDeviceKind.unknown,
  };
}

/// Picks the screen for the current [SessionStatus]: a splash while the
/// stored session is checked, a retry page when the server cannot be reached,
/// the login screen when signed out, [home] when signed in.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key, required this.persona, required this.home});
  final AuthPersona persona;
  final WidgetBuilder home;

  @override
  Widget build(BuildContext context) {
    final session = SessionScope.of(context);
    return switch (session.status) {
      SessionStatus.restoring => const _Splash(),
      SessionStatus.offline => Scaffold(
        backgroundColor: RColors.surface,
        body: SafeArea(
          child: RErrorView(
            message:
                session.notice ?? "Couldn't reach the server. Check your connection and try again.",
            onRetry: session.restore,
            secondaryLabel: 'Sign out',
            onSecondary: session.signOut,
          ),
        ),
      ),
      SessionStatus.signedOut => LoginScreen(persona: persona),
      SessionStatus.signedIn => Builder(builder: home),
    };
  }
}

class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) => const Scaffold(
    backgroundColor: RColors.surface,
    body: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          RWordmark(size: 26),
          SizedBox(height: 22),
          SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2.4, color: RColors.teal),
          ),
        ],
      ),
    ),
  );
}

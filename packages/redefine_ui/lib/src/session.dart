import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:redefine_core/redefine_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'async.dart';
import 'report.dart';

/// Keeps the session token in the platform's key-value store (localStorage on
/// web, a file on Windows) under `redefine.<namespace>.token`, so the three
/// apps never read each other's session.
///
/// When the plugin is unavailable the token lives in memory for this run.
class SharedPrefsTokenStore implements TokenStore {
  SharedPrefsTokenStore(String namespace) : _key = 'redefine.$namespace.token';

  final String _key;
  String? _memory;

  @override
  Future<String?> read() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_key) ?? _memory;
    } catch (_) {
      return _memory;
    }
  }

  @override
  Future<void> write(String token) async {
    _memory = token;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, token);
    } catch (_) {}
  }

  @override
  Future<void> clear() async {
    _memory = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key);
    } catch (_) {}
  }
}

enum SessionStatus {
  /// Checking the stored token; nothing is known yet.
  restoring,
  signedOut,
  signedIn,

  /// The stored session could not be confirmed, typically because the server
  /// could not be reached. The token is kept for a retry.
  offline,
}

/// Owns the signed-in state of one app and gates it to [requiredRole].
class SessionController extends ChangeNotifier {
  SessionController({required this.api, required this.requiredRole}) {
    api.onSessionExpired = _onExpired;
  }

  final ApiClient api;

  /// `admin` | `crew` | `customer`: the only role this app lets in.
  final String requiredRole;

  SessionStatus _status = SessionStatus.restoring;
  AuthUser? _user;
  String? _notice;
  int _epoch = 0;
  Future<void>? _restoring;
  bool _disposed = false;

  SessionStatus get status => _status;

  /// The signed-in user; null unless [status] is [SessionStatus.signedIn].
  AuthUser? get user => _user;

  /// Why the session is in its current state, when there is something to
  /// tell the user (expired session, wrong app, server unreachable).
  String? get notice => _notice;

  /// Increments on every sign-in and sign-out. Keying the app on it drops all
  /// routes and per-user state.
  int get epoch => _epoch;

  /// Resumes the stored session. Never throws: any failure, such as a server
  /// that cannot be reached, leaves the token in place and the status
  /// [SessionStatus.offline].
  Future<void> restore() => _restoring ??= _restore().whenComplete(() => _restoring = null);

  Future<void> _restore() async {
    if (_status != SessionStatus.restoring) {
      _status = SessionStatus.restoring;
      _user = null;
      _notice = null;
      _notify();
    }
    final epoch = _epoch;
    try {
      final user = await api.restoreSession();
      if (epoch != _epoch) return;
      if (user == null) {
        _enter(SessionStatus.signedOut);
      } else if (user.role != requiredRole) {
        unawaited(api.logout());
        _enter(SessionStatus.signedOut, notice: _wrongRoleMessage(user.role));
      } else {
        _enter(SessionStatus.signedIn, user: user);
      }
    } catch (e, stack) {
      // Nothing awaits restore(), so even a bug must not strand the app on
      // the splash: log it and offer Retry like any other failure.
      if (e is! ApiException) reportBug(e, stack, 'while restoring the session');
      if (epoch != _epoch) return;
      _status = SessionStatus.offline;
      _notice = friendlyError(e);
      _notify();
    }
  }

  /// Throws [ApiException]; an account for another app is signed straight
  /// back out and reported with code `wrong_role`.
  Future<void> login(String email, String password) async {
    final result = await api.login(email, password);
    _accept(result.user);
  }

  /// Creates an account with this app's role and signs it in.
  Future<void> signup({
    required String name,
    required String email,
    required String password,
    String? phone,
    String? inviteCode,
  }) async {
    final result = await api.signup(
      name: name,
      email: email,
      password: password,
      role: requiredRole,
      phone: phone,
      inviteCode: inviteCode,
    );
    _accept(result.user);
  }

  /// Re-reads the user from the server (e.g. to see a crew approval land).
  Future<void> refreshUser() async {
    final epoch = _epoch;
    final user = await api.me();
    if (epoch != _epoch || _status != SessionStatus.signedIn) return;
    _user = user;
    _notify();
  }

  /// Signs out on this device at once; the server is told in the background
  /// and the returned future completes when that has finished.
  Future<void> signOut() async {
    final serverLogout = api.logout();
    _enter(SessionStatus.signedOut);
    await serverLogout;
  }

  void _accept(AuthUser user) {
    if (user.role != requiredRole) {
      unawaited(api.logout());
      throw ApiException(403, 'wrong_role', _wrongRoleMessage(user.role));
    }
    _enter(SessionStatus.signedIn, user: user);
  }

  void _onExpired() {
    if (_status == SessionStatus.signedOut) return;
    _enter(SessionStatus.signedOut, notice: 'Your session expired. Please sign in again.');
  }

  void _enter(SessionStatus status, {AuthUser? user, String? notice}) {
    _status = status;
    _user = user;
    _notice = notice;
    _epoch++;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  String _wrongRoleMessage(String role) => switch (role) {
    'admin' => 'This is an admin account. Please sign in with the Redefine Admin app instead.',
    'crew' => 'This is a crew account. Please sign in with the Redefine Crew app instead.',
    'customer' =>
      'This is a customer account. Please sign in with the Redefine customer app instead.',
    _ => "This account can't be used in this app.",
  };

  @override
  void dispose() {
    _disposed = true;
    if (api.onSessionExpired == _onExpired) api.onSessionExpired = null;
    super.dispose();
  }
}

/// Exposes the app's [SessionController] to the widget tree.
class SessionScope extends InheritedNotifier<SessionController> {
  const SessionScope({super.key, required SessionController session, required super.child})
    : super(notifier: session);

  /// The session above [context]. With [listen] (the default) the caller
  /// rebuilds whenever the session changes; pass `listen: false` to read it
  /// from `initState` or a callback.
  static SessionController of(BuildContext context, {bool listen = true}) {
    final session = maybeOf(context, listen: listen);
    assert(session != null, 'No SessionScope above this widget. Wrap the app in RedefineApp.');
    return session!;
  }

  static SessionController? maybeOf(BuildContext context, {bool listen = true}) {
    final scope = listen
        ? context.dependOnInheritedWidgetOfExactType<SessionScope>()
        : context.getInheritedWidgetOfExactType<SessionScope>();
    return scope?.notifier;
  }
}

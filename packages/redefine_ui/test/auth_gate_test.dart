import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:redefine_ui/redefine_ui.dart';

const _persona = AuthPersona(
  role: 'customer',
  label: 'CUSTOMER',
  icon: Icons.home_outlined,
  loginSubtitle: 'Sign in to request a plough.',
  signupTitle: 'Create your account',
  signupSubtitle: 'Add your driveway and get a quote.',
  demoEmail: 'sarah.m@gmail.com',
  demoPassword: 'redefine',
  extra: AuthExtraField(
    key: 'phone',
    label: 'Phone',
    icon: Icons.phone_outlined,
    placeholder: '(807) 555-0100',
  ),
);

const _crewMessage = 'This is a crew account. Please sign in with the Redefine Crew app instead.';

Map<String, Object?> _user(String role, {String name = 'Sarah Mitchell'}) => {
  'id': 'user_$role',
  'name': name,
  'email': '$role@example.com',
  'role': role,
  'initials': 'SM',
  'color': 'teal',
  'phone': '',
  'linkedId': role == 'admin' ? null : '${role}_1',
  'crewStatus': role == 'crew' ? 'active' : null,
};

http.Response _json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

http.Response _error(int status, String code, String message) =>
    _json({'error': message, 'code': code}, status);

/// A stand-in API: `tokens` maps a bearer token to the role it belongs to,
/// `accounts` maps an email to its role (every password is `redefine`).
class FakeServer {
  FakeServer({Map<String, String>? tokens, Map<String, String>? accounts})
    : tokens = {...?tokens},
      accounts = {...?accounts};

  final Map<String, String> tokens;
  final Map<String, String> accounts;
  final requests = <String>[];
  final bodies = <Map<String, dynamic>>[];
  bool down = false;

  late final client = MockClient((request) async {
    final route = '${request.method} ${request.url.path}';
    requests.add(route);
    if (down) throw http.ClientException('Connection refused');
    final bearer = request.headers['authorization']?.replaceFirst('Bearer ', '');
    final body = request.body.isEmpty
        ? const <String, dynamic>{}
        : jsonDecode(request.body) as Map<String, dynamic>;
    switch (route) {
      case 'POST /auth/login':
        final role = accounts[body['email']];
        if (role == null || body['password'] != 'redefine') {
          return _error(401, 'invalid_credentials', 'Wrong email or password.');
        }
        return _json({'token': _issue(role), 'user': _user(role)});
      case 'POST /auth/signup':
        bodies.add(body);
        final role = body['role'] as String;
        return _json({
          'token': _issue(role),
          'user': _user(role, name: body['name'] as String),
        }, 201);
    }
    final role = tokens[bearer];
    if (role == null) return _error(401, 'unauthorized', 'Please sign in again.');
    switch (route) {
      case 'GET /auth/me':
        return _json(_user(role));
      case 'POST /auth/logout':
        tokens.remove(bearer);
        return _json({'ok': true});
      case 'GET /settings':
        return _json({'shovelPrice': 20, 'currency': 'cad', 'paymentsMode': 'manual'});
    }
    return _error(404, 'not_found', 'Not found.');
  });

  String _issue(String role) {
    final token = 'token_${tokens.length + 1}';
    tokens[token] = role;
    return token;
  }
}

/// An ApiClient that breaks its promise to fail only with an ApiException.
class _BuggyApi extends ApiClient {
  _BuggyApi({this.restoreFails = false})
    : super(baseUrl: 'http://api.test', httpClient: FakeServer().client);

  final bool restoreFails;

  @override
  Future<AuthUser?> restoreSession() =>
      restoreFails ? Future.error(StateError('restore')) : super.restoreSession();

  @override
  Future<AuthResult> login(String email, String password) => Future.error(StateError('login'));

  @override
  Future<AuthResult> signup({
    required String name,
    required String email,
    required String password,
    required String role,
    String? phone,
    String? inviteCode,
  }) => Future.error(StateError('signup'));
}

class _Home extends StatelessWidget {
  const _Home();

  @override
  Widget build(BuildContext context) => const Scaffold(
    body: Padding(
      padding: EdgeInsets.all(16),
      child: Column(children: [RAppHeader(), Text('HOME')]),
    ),
  );
}

/// Pumps the app against [server] with [token] already stored (if any).
Future<({SessionController session, MemoryTokenStore store})> _pumpApp(
  WidgetTester tester,
  FakeServer server, {
  String? token,
  AuthPersona persona = _persona,
  WidgetBuilder? home,
  ApiClient? api,
}) async {
  // Tall enough that no control of the auth screens is scrolled off screen.
  tester.view.physicalSize = const Size(1000, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final store = MemoryTokenStore(token);
  api ??= ApiClient(baseUrl: 'http://api.test', httpClient: server.client, tokenStore: store);
  final session = SessionController(api: api, requiredRole: persona.role);
  addTearDown(session.dispose);
  await tester.pumpWidget(
    RedefineApp(
      title: 'Redefine',
      persona: persona,
      session: session,
      home: home ?? (_) => const _Home(),
    ),
  );
  return (session: session, store: store);
}

/// Lets in-flight requests finish and the resulting frames build.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Finder get _emailField => find.byType(TextField).at(0);
Finder get _passwordField => find.byType(TextField).at(1);

void main() {
  testWidgets('shows a splash while the stored session is checked', (tester) async {
    final server = FakeServer(tokens: {'stored': 'customer'});
    await _pumpApp(tester, server, token: 'stored');
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('HOME'), findsNothing);
    expect(find.byType(LoginScreen), findsNothing);
    await _settle(tester);
  });

  testWidgets('no token -> login, without asking the server', (tester) async {
    final server = FakeServer();
    final app = await _pumpApp(tester, server);
    await _settle(tester);

    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.text('Sign in to request a plough.'), findsOneWidget);
    expect(find.text('HOME'), findsNothing);
    expect(server.requests, isEmpty);
    expect(app.session.status, SessionStatus.signedOut);
    expect(app.session.notice, isNull);
  });

  testWidgets('valid token -> home, with the user in scope', (tester) async {
    final server = FakeServer(tokens: {'stored': 'customer'});
    final app = await _pumpApp(tester, server, token: 'stored');
    await _settle(tester);

    expect(find.text('HOME'), findsOneWidget);
    expect(find.text('Hi Sarah!'), findsOneWidget);
    expect(find.byType(LoginScreen), findsNothing);
    expect(server.requests, ['GET /auth/me']);
    expect(app.session.status, SessionStatus.signedIn);
    expect(app.session.user?.name, 'Sarah Mitchell');
  });

  testWidgets('expired stored token -> login', (tester) async {
    final server = FakeServer();
    final app = await _pumpApp(tester, server, token: 'expired');
    await _settle(tester);

    expect(find.byType(LoginScreen), findsOneWidget);
    expect(await app.store.read(), isNull);
  });

  testWidgets('wrong role -> login with a message, and the session is dropped', (tester) async {
    final server = FakeServer(tokens: {'stored': 'crew'});
    final app = await _pumpApp(tester, server, token: 'stored');
    await _settle(tester);

    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.text(_crewMessage), findsOneWidget);
    expect(find.text('HOME'), findsNothing);
    expect(app.session.status, SessionStatus.signedOut);
    expect(app.session.api.isSignedIn, isFalse);
    expect(await app.store.read(), isNull);
    expect(server.requests, ['GET /auth/me', 'POST /auth/logout']);
    expect(server.tokens, isEmpty);
  });

  testWidgets('logging in with another app\'s account is refused with a message', (tester) async {
    final server = FakeServer(accounts: {'marcus@redefine.co': 'crew'});
    final app = await _pumpApp(tester, server);
    await _settle(tester);

    await tester.enterText(_emailField, 'marcus@redefine.co');
    await tester.enterText(_passwordField, 'redefine');
    await tester.tap(find.text('Log in'));
    await _settle(tester);

    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.text(_crewMessage), findsOneWidget);
    expect(find.text('HOME'), findsNothing);
    expect(app.session.status, SessionStatus.signedOut);
    expect(await app.store.read(), isNull);
    expect(server.tokens, isEmpty);
  });

  testWidgets('demo credentials are prefilled in debug builds and log in', (tester) async {
    final server = FakeServer(accounts: {'sarah.m@gmail.com': 'customer'});
    final app = await _pumpApp(tester, server);
    await _settle(tester);
    final epoch = app.session.epoch;

    expect(find.text('sarah.m@gmail.com'), findsOneWidget);
    await tester.tap(find.text('Log in'));
    await _settle(tester);

    expect(find.text('HOME'), findsOneWidget);
    expect(find.byType(LoginScreen), findsNothing);
    expect(app.session.epoch, epoch + 1);
    expect(await app.store.read(), isNotNull);
  });

  testWidgets('Enter in the password field submits the form', (tester) async {
    final server = FakeServer(accounts: {'sarah.m@gmail.com': 'customer'});
    await _pumpApp(tester, server);
    await _settle(tester);

    await tester.tap(_passwordField);
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await _settle(tester);

    expect(find.text('HOME'), findsOneWidget);
  });

  testWidgets('validates before calling the server and shows server errors inline', (tester) async {
    final server = FakeServer(accounts: {'sarah.m@gmail.com': 'customer'});
    await _pumpApp(tester, server);
    await _settle(tester);

    await tester.enterText(_emailField, 'not-an-email');
    await tester.enterText(_passwordField, '');
    await tester.tap(find.text('Log in'));
    await _settle(tester);
    expect(find.text("That doesn't look like an email address."), findsOneWidget);
    expect(find.text('Enter your password.'), findsOneWidget);
    expect(server.requests, isEmpty);

    await tester.enterText(_emailField, 'sarah.m@gmail.com');
    await tester.enterText(_passwordField, 'wrong-password');
    await tester.tap(find.text('Log in'));
    await _settle(tester);
    expect(find.text('Wrong email or password.'), findsOneWidget);
    expect(find.text("That doesn't look like an email address."), findsNothing);
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(server.requests, ['POST /auth/login']);
  });

  testWidgets('has no Google or forgot-password controls', (tester) async {
    await _pumpApp(tester, FakeServer());
    await _settle(tester);
    expect(find.textContaining('Google'), findsNothing);
    expect(find.textContaining('Forgot'), findsNothing);
    expect(find.text('Sign up'), findsOneWidget);
  });

  testWidgets('allowSignup: false hides the sign-up link', (tester) async {
    const adminOnly = AuthPersona(
      role: 'admin',
      label: 'ADMIN',
      icon: Icons.shield_outlined,
      loginSubtitle: 'Run the ploughing operation.',
      signupTitle: 'Create an admin account',
      signupSubtitle: 'Invite only.',
      allowSignup: false,
    );
    await _pumpApp(tester, FakeServer(), persona: adminOnly);
    await _settle(tester);
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.text('Sign up'), findsNothing);
  });

  testWidgets('sign-up validates, creates the account for this app and lands on home', (
    tester,
  ) async {
    final server = FakeServer();
    final app = await _pumpApp(tester, server);
    await _settle(tester);

    await tester.tap(find.text('Sign up'));
    await _settle(tester);
    expect(find.byType(SignupScreen), findsOneWidget);
    expect(find.text('Create your account'), findsOneWidget);

    await tester.tap(find.text('Create account'));
    await _settle(tester);
    expect(find.text('Enter your name.'), findsOneWidget);
    expect(find.text('Enter your email.'), findsOneWidget);
    expect(find.text('Use at least 8 characters.'), findsOneWidget);
    expect(server.requests, isEmpty);

    await tester.enterText(find.byType(TextField).at(0), 'Nora Field');
    await tester.enterText(find.byType(TextField).at(1), '(807) 555-0199');
    await tester.enterText(find.byType(TextField).at(2), 'nora@example.com');
    await tester.enterText(find.byType(TextField).at(3), 'snowplough');
    await tester.tap(find.text('Create account'));
    await _settle(tester);

    expect(server.bodies.single, {
      'name': 'Nora Field',
      'email': 'nora@example.com',
      'password': 'snowplough',
      'role': 'customer',
      'phone': '(807) 555-0199',
    });
    expect(find.text('HOME'), findsOneWidget);
    expect(find.text('Hi Nora!'), findsOneWidget);
    expect(find.byType(SignupScreen), findsNothing);
    expect(app.session.status, SessionStatus.signedIn);
  });

  testWidgets('server unreachable -> retry page that keeps the token; Retry recovers', (
    tester,
  ) async {
    final server = FakeServer(tokens: {'stored': 'customer'})..down = true;
    final app = await _pumpApp(tester, server, token: 'stored');
    await _settle(tester);

    expect(app.session.status, SessionStatus.offline);
    expect(find.byType(RErrorView), findsOneWidget);
    expect(find.textContaining("Couldn't reach the server"), findsOneWidget);
    expect(find.text('Sign out'), findsOneWidget);
    expect(await app.store.read(), 'stored');

    server.down = false;
    await tester.tap(find.text('Retry'));
    await _settle(tester);
    expect(find.text('HOME'), findsOneWidget);
    expect(app.session.status, SessionStatus.signedIn);
  });

  testWidgets('the retry page can sign out instead', (tester) async {
    final server = FakeServer(tokens: {'stored': 'customer'})..down = true;
    final app = await _pumpApp(tester, server, token: 'stored');
    await _settle(tester);

    await tester.tap(find.text('Sign out'));
    await _settle(tester);
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(await app.store.read(), isNull);
  });

  testWidgets('a restore that fails with a bug leaves the splash for the retry page', (
    tester,
  ) async {
    final app = await _pumpApp(tester, FakeServer(), api: _BuggyApi(restoreFails: true));
    await _settle(tester);

    expect(tester.takeException(), isStateError);
    expect(app.session.status, SessionStatus.offline);
    expect(find.byType(RErrorView), findsOneWidget);
    expect(find.text('Something went wrong. Please try again.'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);

    await tester.tap(find.text('Sign out'));
    await _settle(tester);
    expect(find.byType(LoginScreen), findsOneWidget);
  });

  testWidgets('a login that fails with a bug says so instead of doing nothing', (tester) async {
    await _pumpApp(tester, FakeServer(), api: _BuggyApi());
    await _settle(tester);

    await tester.tap(find.text('Log in'));
    await _settle(tester);

    expect(tester.takeException(), isStateError);
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.text('Something went wrong. Please try again.'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('a sign-up that fails with a bug says so instead of doing nothing', (tester) async {
    await _pumpApp(tester, FakeServer(), api: _BuggyApi());
    await _settle(tester);
    await tester.tap(find.text('Sign up'));
    await _settle(tester);

    // Scoped: the login screen underneath is still on stage as the push ends.
    final fields = find.descendant(of: find.byType(SignupScreen), matching: find.byType(TextField));
    await tester.enterText(fields.at(0), 'Nora Field');
    await tester.enterText(fields.at(2), 'nora@example.com');
    await tester.enterText(fields.at(3), 'snowplough');
    await tester.tap(find.text('Create account'));
    await _settle(tester);

    expect(tester.takeException(), isStateError);
    expect(find.byType(SignupScreen), findsOneWidget);
    expect(find.text('Something went wrong. Please try again.'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('signing out from the header menu returns to login and drops the token', (
    tester,
  ) async {
    final server = FakeServer(tokens: {'stored': 'customer'});
    final app = await _pumpApp(tester, server, token: 'stored');
    await _settle(tester);
    final epoch = app.session.epoch;

    await tester.tap(find.byType(RAvatar));
    await _settle(tester);
    expect(find.text('Sarah Mitchell'), findsOneWidget);
    expect(find.text('customer@example.com'), findsOneWidget);

    await tester.tap(find.text('Sign out'));
    await _settle(tester);
    expect(find.text('Sign out?'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Sign out'));
    await _settle(tester);

    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.text('HOME'), findsNothing);
    expect(app.session.epoch, epoch + 1);
    expect(app.session.user, isNull);
    expect(await app.store.read(), isNull);
    expect(server.requests.last, 'POST /auth/logout');
    expect(server.tokens, isEmpty);
  });

  testWidgets('an expired session returns to login with a notice', (tester) async {
    final server = FakeServer(tokens: {'stored': 'customer'});
    final app = await _pumpApp(tester, server, token: 'stored');
    await _settle(tester);
    expect(find.text('HOME'), findsOneWidget);
    final epoch = app.session.epoch;

    // The server forgets the token; the next call of any screen finds out.
    server.tokens.clear();
    Object? failure;
    app.session.api.settings().then<void>(
      (_) {},
      onError: (Object e) {
        failure = e;
      },
    );
    await _settle(tester);

    expect(failure, isA<ApiException>().having((e) => e.isUnauthorized, 'isUnauthorized', isTrue));
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.text('Your session expired. Please sign in again.'), findsOneWidget);
    expect(app.session.epoch, epoch + 1);
    expect(await app.store.read(), isNull);
  });

  testWidgets('framed like a phone on a wide window, with screens seeing the frame size', (
    tester,
  ) async {
    final server = FakeServer();
    await _pumpApp(tester, server);
    await _settle(tester);

    final screen = tester.element(find.byType(LoginScreen));
    expect(MediaQuery.sizeOf(screen), const Size(412, 1400 - 32));
    expect(tester.getSize(find.byType(LoginScreen)).width, 412);
  });

  testWidgets('a mouse drag pulls a live list to refresh', (tester) async {
    var loads = 0;
    final controller = RLiveController<int>(() async => ++loads);
    addTearDown(controller.dispose);
    await _pumpApp(
      tester,
      FakeServer(tokens: {'stored': 'customer'}),
      token: 'stored',
      home: (_) => Scaffold(
        body: RLive<int>(
          controller: controller,
          builder: (_, load) => Column(children: [Text('load $load')]),
        ),
      ),
    );
    await _settle(tester);
    expect(find.text('load 1'), findsOneWidget);

    await tester.drag(
      find.text('load 1'),
      const Offset(0, 300),
      kind: PointerDeviceKind.mouse,
      touchSlopY: 0,
    );
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('load 2'), findsOneWidget);
  });

  testWidgets('lists can be dragged with a mouse', (tester) async {
    await _pumpApp(tester, FakeServer());
    await _settle(tester);
    final behavior = ScrollConfiguration.of(tester.element(find.byType(LoginScreen)));
    expect(
      behavior.dragDevices,
      containsAll([PointerDeviceKind.mouse, PointerDeviceKind.trackpad, PointerDeviceKind.touch]),
    );
  });
}

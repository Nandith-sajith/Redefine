import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:redefine_ui/redefine_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

Map<String, Object?> _user(String role, {String? crewStatus}) => {
  'id': 'user_1',
  'name': 'Marcus Reid',
  'email': 'marcus@redefine.co',
  'role': role,
  'initials': 'MR',
  'color': 'lime',
  'phone': '',
  'linkedId': 'crew_marcus',
  'crewStatus': crewStatus,
};

http.Response _json(Object body, [int status = 200]) => http.Response(jsonEncode(body), status);

/// A plugin that fails every call, as when no implementation is registered.
class _BrokenStore extends SharedPreferencesStorePlatform {
  Never _fail() => throw PlatformException(code: 'unavailable');

  @override
  Future<bool> clear() async => _fail();

  @override
  Future<Map<String, Object>> getAll() async => _fail();

  @override
  Future<bool> remove(String key) async => _fail();

  @override
  Future<bool> setValue(String valueType, String key, Object value) async => _fail();
}

/// An ApiClient that breaks its promise to fail only with an ApiException.
class _BuggyApi extends ApiClient {
  _BuggyApi() : super(baseUrl: 'http://api.test', httpClient: MockClient((_) async => _json({})));

  @override
  Future<AuthUser?> restoreSession() async => throw StateError('boom');
}

void main() {
  group('SessionController', () {
    late String crewStatus;
    late bool tokenValid;
    late List<String> requests;
    late ApiClient api;
    late MemoryTokenStore store;
    late SessionController session;
    late List<SessionStatus> seen;

    void start({String? token, String role = 'crew'}) {
      store = MemoryTokenStore(token);
      api = ApiClient(
        baseUrl: 'http://api.test',
        tokenStore: store,
        httpClient: MockClient((request) async {
          requests.add('${request.method} ${request.url.path}');
          switch (request.url.path) {
            case '/auth/login' || '/auth/signup':
              final body = jsonDecode(request.body) as Map<String, dynamic>;
              final role = body['role'] as String? ?? 'crew';
              return _json({'token': 'fresh', 'user': _user(role, crewStatus: crewStatus)});
            case '/auth/logout':
              return _json({'ok': true});
            case '/auth/me' when tokenValid:
              return _json(_user('crew', crewStatus: crewStatus));
          }
          return _json({'error': 'Please sign in again.', 'code': 'unauthorized'}, 401);
        }),
      );
      session = SessionController(api: api, requiredRole: role);
      seen = [];
      session.addListener(() => seen.add(session.status));
      addTearDown(session.dispose);
    }

    setUp(() {
      crewStatus = 'pending';
      tokenValid = true;
      requests = [];
    });

    test('starts restoring and bumps epoch on every sign-in and sign-out', () async {
      start(token: 'stored');
      expect(session.status, SessionStatus.restoring);
      expect(session.epoch, 0);
      expect(session.user, isNull);

      await session.restore();
      expect(session.status, SessionStatus.signedIn);
      expect(session.user?.name, 'Marcus Reid');
      expect(session.epoch, 1);

      await session.signOut();
      expect(session.status, SessionStatus.signedOut);
      expect(session.user, isNull);
      expect(session.epoch, 2);
      expect(await store.read(), isNull);

      await session.login('marcus@redefine.co', 'redefine');
      expect(session.status, SessionStatus.signedIn);
      expect(session.epoch, 3);
      expect(await store.read(), 'fresh');
      expect(seen, [SessionStatus.signedIn, SessionStatus.signedOut, SessionStatus.signedIn]);
    });

    test('restore with no token signs out without a notice', () async {
      start();
      await session.restore();
      expect(session.status, SessionStatus.signedOut);
      expect(session.notice, isNull);
      expect(session.epoch, 1);
      expect(requests, isEmpty);
    });

    test('concurrent restores share one request', () async {
      start(token: 'stored');
      await Future.wait([session.restore(), session.restore()]);
      expect(requests, ['GET /auth/me']);
      expect(session.epoch, 1);
    });

    test('signup creates an account with the app\'s role', () async {
      start();
      await session.restore();
      await session.signup(name: 'Marcus Reid', email: 'marcus@redefine.co', password: 'redefine');
      expect(session.status, SessionStatus.signedIn);
      expect(session.user?.role, 'crew');
      expect(session.user?.crewStatus, CrewStatus.pending);
    });

    test('login to the wrong app throws wrong_role and leaves no session behind', () async {
      start(role: 'admin');
      await session.restore();
      final epoch = session.epoch;

      await expectLater(
        session.login('marcus@redefine.co', 'redefine'),
        throwsA(
          isA<ApiException>()
              .having((e) => e.code, 'code', 'wrong_role')
              .having((e) => e.statusCode, 'statusCode', 403)
              .having((e) => e.message, 'message', contains('Redefine Crew app')),
        ),
      );
      await pumpEventQueue();
      expect(session.status, SessionStatus.signedOut);
      expect(session.epoch, epoch);
      expect(api.isSignedIn, isFalse);
      expect(await store.read(), isNull);
      expect(requests, contains('POST /auth/logout'));
    });

    test('refreshUser picks up a crew approval and notifies without a new epoch', () async {
      start(token: 'stored');
      await session.restore();
      expect(session.user?.crewStatus, CrewStatus.pending);
      final epoch = session.epoch;
      seen.clear();

      crewStatus = 'active';
      await session.refreshUser();
      expect(session.user?.crewStatus, CrewStatus.active);
      expect(session.epoch, epoch);
      expect(seen, [SessionStatus.signedIn]);
    });

    test('an expired token signs out with a notice, once', () async {
      start(token: 'stored');
      await session.restore();
      final epoch = session.epoch;
      seen.clear();

      tokenValid = false;
      final results = await Future.wait([
        for (var i = 0; i < 3; i++)
          session.refreshUser().then<Object?>((_) => null, onError: (e) => e),
      ]);
      expect(results, everyElement(isA<ApiException>()));
      expect(session.status, SessionStatus.signedOut);
      expect(session.notice, 'Your session expired. Please sign in again.');
      expect(session.epoch, epoch + 1);
      expect(seen, [SessionStatus.signedOut]);
    });

    test('a failed login changes nothing', () async {
      final offline = SessionController(
        requiredRole: 'crew',
        api: ApiClient(
          baseUrl: 'http://api.test',
          httpClient: MockClient((_) async => throw http.ClientException('down')),
        ),
      );
      addTearDown(offline.dispose);
      await offline.restore();
      final epoch = offline.epoch;

      await expectLater(
        offline.login('marcus@redefine.co', 'redefine'),
        throwsA(isA<ApiException>().having((e) => e.isNetwork, 'isNetwork', isTrue)),
      );
      expect(offline.status, SessionStatus.signedOut);
      expect(offline.epoch, epoch);
    });

    test('restore goes offline, keeps the token, and recovers on retry', () async {
      var down = true;
      store = MemoryTokenStore('stored');
      final flaky = SessionController(
        requiredRole: 'crew',
        api: ApiClient(
          baseUrl: 'http://api.test',
          tokenStore: store,
          httpClient: MockClient((_) async {
            if (down) throw http.ClientException('down');
            return _json(_user('crew', crewStatus: 'active'));
          }),
        ),
      );
      addTearDown(flaky.dispose);
      final statuses = <SessionStatus>[];
      flaky.addListener(() => statuses.add(flaky.status));

      await flaky.restore();
      expect(flaky.status, SessionStatus.offline);
      expect(flaky.notice, contains("Couldn't reach the server"));
      expect(flaky.epoch, 0);
      expect(await store.read(), 'stored');

      down = false;
      await flaky.restore();
      expect(flaky.status, SessionStatus.signedIn);
      expect(flaky.notice, isNull);
      expect(flaky.epoch, 1);
      expect(statuses, [SessionStatus.offline, SessionStatus.restoring, SessionStatus.signedIn]);
    });

    test('restore never throws: a bug is logged and ends on offline, not restoring', () async {
      final reported = <Object>[];
      final previous = FlutterError.onError;
      FlutterError.onError = (details) => reported.add(details.exception);
      addTearDown(() => FlutterError.onError = previous);

      final broken = SessionController(api: _BuggyApi(), requiredRole: 'crew');
      addTearDown(broken.dispose);

      await broken.restore();
      expect(broken.status, SessionStatus.offline);
      expect(broken.notice, 'Something went wrong. Please try again.');
      expect(broken.user, isNull);
      expect(broken.epoch, 0);
      expect(reported.single, isStateError);
    });

    test('dispose detaches from the ApiClient unless a newer controller took over', () {
      final api = ApiClient(
        baseUrl: 'http://api.test',
        httpClient: MockClient((_) async => _json({})),
      );
      final first = SessionController(api: api, requiredRole: 'crew');
      final second = SessionController(api: api, requiredRole: 'crew');
      first.dispose();
      expect(api.onSessionExpired, isNotNull);
      second.dispose();
      expect(api.onSessionExpired, isNull);
    });
  });

  testWidgets('SessionScope.of rebuilds dependents; listen: false works in initState', (
    tester,
  ) async {
    final session = SessionController(
      requiredRole: 'crew',
      api: ApiClient(
        baseUrl: 'http://api.test',
        tokenStore: MemoryTokenStore('stored'),
        httpClient: MockClient((_) async => _json(_user('crew', crewStatus: 'active'))),
      ),
    );
    addTearDown(session.dispose);

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: SessionScope(session: session, child: const _Probe()),
      ),
    );
    expect(find.text('restoring'), findsOneWidget);
    expect(_ProbeState.readInInitState, same(session));

    session.restore();
    await tester.pump();
    await tester.pump();
    expect(find.text('signedIn'), findsOneWidget);

    await tester.pumpWidget(
      const Directionality(textDirection: TextDirection.ltr, child: _Orphan()),
    );
    expect(find.text('no session'), findsOneWidget);
  });

  group('SharedPrefsTokenStore', () {
    setUp(SharedPreferences.resetStatic);

    test('persists under a per-app key', () async {
      SharedPreferences.setMockInitialValues({});
      final store = SharedPrefsTokenStore('customer');
      expect(await store.read(), isNull);

      await store.write('tok_1');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('redefine.customer.token'), 'tok_1');
      expect(await store.read(), 'tok_1');
      expect(await SharedPrefsTokenStore('crew').read(), isNull);

      await store.clear();
      expect(prefs.getString('redefine.customer.token'), isNull);
      expect(await store.read(), isNull);
    });

    test('reads a token saved by an earlier run', () async {
      SharedPreferences.setMockInitialValues({'redefine.admin.token': 'tok_old'});
      expect(await SharedPrefsTokenStore('admin').read(), 'tok_old');
    });

    test('falls back to memory when the plugin fails', () async {
      SharedPreferencesStorePlatform.instance = _BrokenStore();
      final store = SharedPrefsTokenStore('customer');
      expect(await store.read(), isNull);
      await store.write('tok_1');
      expect(await store.read(), 'tok_1');
      await store.clear();
      expect(await store.read(), isNull);
    });
  });
}

class _Probe extends StatefulWidget {
  const _Probe();

  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  static SessionController? readInInitState;

  @override
  void initState() {
    super.initState();
    readInInitState = SessionScope.of(context, listen: false);
  }

  @override
  Widget build(BuildContext context) => Text(SessionScope.of(context).status.name);
}

class _Orphan extends StatelessWidget {
  const _Orphan();

  @override
  Widget build(BuildContext context) =>
      Text(SessionScope.maybeOf(context) == null ? 'no session' : 'session');
}

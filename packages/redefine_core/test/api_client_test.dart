import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:redefine_core/redefine_core.dart';
import 'package:test/test.dart';

const base = 'https://api.test';

const sarah = <String, dynamic>{
  'id': 'user_sarah',
  'name': 'Sarah Mitchell',
  'email': 'sarah.m@gmail.com',
  'role': 'customer',
  'initials': 'SM',
  'color': 'lime',
  'phone': '(807) 555-0142',
  'linkedId': 'cust_sarah',
  'crewStatus': null,
};

http.Response jsonRes(Object? body, [int status = 200]) => http.Response.bytes(
  utf8.encode(jsonEncode(body)),
  status,
  headers: {'content-type': 'application/json'},
);

http.Response errorRes(
  int status,
  String code,
  String message, [
  Map<String, dynamic> extra = const {},
]) => jsonRes({'error': message, 'code': code, ...extra}, status);

Map<String, dynamic> bodyOf(http.Request r) =>
    jsonDecode(r.body) as Map<String, dynamic>;

/// Answers every request with [handler] and records what was sent.
class Server {
  Server(this.handler);

  FutureOr<http.Response> Function(http.Request request) handler;
  final requests = <http.Request>[];

  late final client = MockClient((request) async {
    requests.add(request);
    return handler(request);
  });

  http.Request get last => requests.last;
}

ApiClient clientFor(Server server, {TokenStore? store}) =>
    ApiClient(baseUrl: base, httpClient: server.client, tokenStore: store);

/// A client that already holds a session (token `tok` unless [store] says
/// otherwise).
Future<ApiClient> signedIn(
  Server server, {
  MemoryTokenStore? store,
  Duration timeout = const Duration(seconds: 20),
}) async {
  final previous = server.handler;
  server.handler = (_) => jsonRes(sarah);
  final api = ApiClient(
    baseUrl: base,
    httpClient: server.client,
    tokenStore: store ?? MemoryTokenStore('tok'),
    timeout: timeout,
  );
  await api.restoreSession();
  server.handler = previous;
  server.requests.clear();
  return api;
}

Future<ApiException> failureOf(Future<Object?> call) async {
  try {
    await call;
  } on ApiException catch (e) {
    return e;
  }
  fail('expected an ApiException');
}

void main() {
  group('session', () {
    test(
      'login sends the credentials without a bearer and keeps the token',
      () async {
        final store = MemoryTokenStore();
        final server = Server(
          (_) => jsonRes({'token': 'tok_1', 'user': sarah}),
        );
        final api = clientFor(server, store: store);
        expect(api.isSignedIn, isFalse);

        final result = await api.login('sarah.m@gmail.com', 'redefine');

        final req = server.last;
        expect(req.method, 'POST');
        expect(req.url.toString(), '$base/auth/login');
        expect(req.headers.containsKey('authorization'), isFalse);
        expect(req.headers['content-type'], 'application/json');
        expect(bodyOf(req), {
          'email': 'sarah.m@gmail.com',
          'password': 'redefine',
        });

        expect(result.token, 'tok_1');
        expect(result.user.linkedId, 'cust_sarah');
        expect(api.isSignedIn, isTrue);
        expect(api.currentUser!.id, 'user_sarah');
        expect(await store.read(), 'tok_1');
      },
    );

    test('authenticated calls carry the bearer token', () async {
      final server = Server((_) => jsonRes({'token': 'tok_1', 'user': sarah}));
      final api = clientFor(server);
      await api.login('sarah.m@gmail.com', 'redefine');

      server.handler = (_) => jsonRes({
        'shovelPrice': 20,
        'currency': 'cad',
        'paymentsMode': 'manual',
      });
      final settings = await api.settings();

      expect(server.last.method, 'GET');
      expect(server.last.url.toString(), '$base/settings');
      expect(server.last.headers['authorization'], 'Bearer tok_1');
      expect(server.last.bodyBytes, isEmpty);
      expect(settings.shovelPrice, 20);
      expect(settings.paymentsMode, PaymentMode.manual);
    });

    test('signup sends only the optional fields that were given', () async {
      final store = MemoryTokenStore();
      final server = Server(
        (_) => jsonRes({'token': 'tok_2', 'user': sarah}, 201),
      );
      final api = clientFor(server, store: store);

      await api.signup(
        name: 'Tasha Rivera',
        email: 'tasha@redefine.co',
        password: 'longenough',
        role: 'crew',
        phone: '(807) 555-0199',
      );
      expect(server.last.url.path, '/auth/signup');
      expect(server.last.headers.containsKey('authorization'), isFalse);
      expect(bodyOf(server.last), {
        'name': 'Tasha Rivera',
        'email': 'tasha@redefine.co',
        'password': 'longenough',
        'role': 'crew',
        'phone': '(807) 555-0199',
      });
      expect(await store.read(), 'tok_2');
      expect(api.isSignedIn, isTrue);

      await api.signup(
        name: 'Lia',
        email: 'lia@redefine.co',
        password: 'longenough',
        role: 'admin',
        phone: '',
        inviteCode: 'LET-ME-IN',
      );
      expect(bodyOf(server.last), {
        'name': 'Lia',
        'email': 'lia@redefine.co',
        'password': 'longenough',
        'role': 'admin',
        'inviteCode': 'LET-ME-IN',
      });
    });

    test('a login reply without a token is a bad response', () async {
      final store = MemoryTokenStore();
      final api = clientFor(
        Server((_) => jsonRes({'user': sarah})),
        store: store,
      );
      final e = await failureOf(api.login('a@b.co', 'password1'));
      expect(e.code, 'bad_response');
      expect(api.isSignedIn, isFalse);
      expect(await store.read(), isNull);
    });

    test('restoreSession with a valid token', () async {
      final store = MemoryTokenStore('tok');
      final server = Server((_) => jsonRes(sarah));
      final api = clientFor(server, store: store);

      final user = await api.restoreSession();

      expect(server.last.method, 'GET');
      expect(server.last.url.path, '/auth/me');
      expect(server.last.headers['authorization'], 'Bearer tok');
      expect(user!.id, 'user_sarah');
      expect(api.currentUser!.name, 'Sarah Mitchell');
      expect(api.isSignedIn, isTrue);
      expect(await store.read(), 'tok');
    });

    test(
      'restoreSession without a stored token stays off the network',
      () async {
        final server = Server((_) => jsonRes(sarah));
        final api = clientFor(server, store: MemoryTokenStore());
        expect(await api.restoreSession(), isNull);
        expect(server.requests, isEmpty);
        expect(api.isSignedIn, isFalse);
      },
    );

    test(
      'restoreSession on 401 clears the token without the expiry callback',
      () async {
        final store = MemoryTokenStore('stale');
        final server = Server(
          (_) => errorRes(401, 'unauthorized', 'Sign in again.'),
        );
        final api = clientFor(server, store: store);
        var expired = 0;
        api.onSessionExpired = () => expired++;

        expect(await api.restoreSession(), isNull);

        expect(expired, 0);
        expect(api.isSignedIn, isFalse);
        expect(api.currentUser, isNull);
        expect(await store.read(), isNull);
      },
    );

    test(
      'restoreSession on a network error rethrows and keeps the token',
      () async {
        final store = MemoryTokenStore('tok');
        final server = Server((_) => throw http.ClientException('offline'));
        final api = clientFor(server, store: store);
        var expired = 0;
        api.onSessionExpired = () => expired++;

        final e = await failureOf(api.restoreSession());

        expect(e.isNetwork, isTrue);
        expect(e.code, 'network');
        expect(e.statusCode, 0);
        expect(expired, 0);
        expect(await store.read(), 'tok');

        // Back online: the same stored token restores the session.
        server.handler = (_) => jsonRes(sarah);
        expect((await api.restoreSession())!.id, 'user_sarah');
        expect(api.isSignedIn, isTrue);
      },
    );

    test(
      'restoreSession on a server error rethrows and keeps the token',
      () async {
        final store = MemoryTokenStore('tok');
        final api = clientFor(
          Server((_) => errorRes(503, 'storage_unavailable', 'Try again.')),
          store: store,
        );
        final e = await failureOf(api.restoreSession());
        expect(e.statusCode, 503);
        expect(e.code, 'storage_unavailable');
        expect(await store.read(), 'tok');
      },
    );

    test('me refreshes currentUser', () async {
      final server = Server((_) => jsonRes(sarah));
      final api = await signedIn(server);
      server.handler = (_) => jsonRes({...sarah, 'name': 'Sarah M. Mitchell'});

      final user = await api.me();

      expect(server.last.url.path, '/auth/me');
      expect(user.name, 'Sarah M. Mitchell');
      expect(api.currentUser!.name, 'Sarah M. Mitchell');
    });

    test('without a token an authenticated call fails locally', () async {
      final server = Server((_) => jsonRes(const {}));
      final api = clientFor(server);
      var expired = 0;
      api.onSessionExpired = () => expired++;

      final e = await failureOf(api.jobs());

      expect(e.code, 'unauthorized');
      expect(e.isUnauthorized, isTrue);
      expect(e.statusCode, 401);
      expect(server.requests, isEmpty);
      expect(expired, 0);
    });

    test('logout tells the server and clears the session', () async {
      final store = MemoryTokenStore('tok');
      final server = Server((_) => jsonRes({'ok': true}));
      final api = await signedIn(server, store: store);

      await api.logout();

      expect(server.last.method, 'POST');
      expect(server.last.url.path, '/auth/logout');
      expect(server.last.headers['authorization'], 'Bearer tok');
      expect(api.isSignedIn, isFalse);
      expect(api.currentUser, isNull);
      expect(await store.read(), isNull);
    });

    test('logout clears locally even when the server call fails', () async {
      for (final FutureOr<http.Response> Function(http.Request) failure in [
        (_) => throw http.ClientException('offline'),
        (_) => errorRes(401, 'unauthorized', 'Sign in again.'),
        (_) => http.Response('<html>Bad Gateway</html>', 502),
      ]) {
        final store = MemoryTokenStore('tok');
        final server = Server((_) => jsonRes(sarah));
        final api = await signedIn(server, store: store);
        var expired = 0;
        api.onSessionExpired = () => expired++;
        server.handler = failure;

        await api.logout();

        expect(server.requests, hasLength(1));
        expect(api.isSignedIn, isFalse);
        expect(api.currentUser, isNull);
        expect(await store.read(), isNull);
        expect(expired, 0);
      }
    });

    test('logout when signed out does nothing on the network', () async {
      final server = Server((_) => jsonRes({'ok': true}));
      final api = clientFor(server);
      await api.logout();
      expect(server.requests, isEmpty);
    });

    test('a failing token store does not break the session', () async {
      final server = Server((_) => jsonRes({'token': 'tok_1', 'user': sarah}));
      final api = clientFor(server, store: _BrokenStore());

      expect(await api.restoreSession(), isNull);
      await api.login('sarah.m@gmail.com', 'redefine');
      expect(api.isSignedIn, isTrue);
      await api.logout();
      expect(api.isSignedIn, isFalse);
    });
  });

  group('session expiry', () {
    test(
      'a 401 fires onSessionExpired once across 3 concurrent calls',
      () async {
        final store = MemoryTokenStore('tok');
        final server = Server((_) => jsonRes(sarah));
        final api = await signedIn(server, store: store);
        var expired = 0;
        api.onSessionExpired = () => expired++;

        final gate = Completer<void>();
        server.handler = (_) async {
          await gate.future;
          return errorRes(401, 'unauthorized', 'Your session expired.');
        };
        final calls = [
          failureOf(api.settings()),
          failureOf(api.jobs()),
          failureOf(api.billing()),
        ];
        await pumpEventQueue();
        expect(server.requests, hasLength(3));
        gate.complete();
        final errors = await Future.wait(calls);

        expect(errors.map((e) => e.statusCode), everyElement(401));
        expect(errors.map((e) => e.isUnauthorized), everyElement(isTrue));
        expect(errors.first.message, 'Your session expired.');
        expect(expired, 1);
        expect(api.isSignedIn, isFalse);
        expect(api.currentUser, isNull);
        expect(await store.read(), isNull);

        // Later calls fail locally and stay quiet.
        await failureOf(api.settings());
        expect(server.requests, hasLength(3));
        expect(expired, 1);
      },
    );

    test('the session is already cleared when the callback runs', () async {
      final store = MemoryTokenStore('tok');
      final server = Server((_) => jsonRes(sarah));
      final api = await signedIn(server, store: store);
      bool? signedInAtCallback;
      String? storedAtCallback = 'unset';
      api.onSessionExpired = () {
        signedInAtCallback = api.isSignedIn;
        store.read().then((v) => storedAtCallback = v);
      };
      server.handler = (_) => errorRes(401, 'unauthorized', 'Expired.');

      await failureOf(api.settings());
      await pumpEventQueue();

      expect(signedInAtCallback, isFalse);
      expect(storedAtCallback, isNull);
    });

    test('a 401 from login does not fire it', () async {
      final server = Server((_) => jsonRes(sarah));
      final api = await signedIn(server);
      var expired = 0;
      api.onSessionExpired = () => expired++;
      server.handler = (_) =>
          errorRes(401, 'invalid_credentials', 'Wrong email or password.');

      final e = await failureOf(api.login('sarah.m@gmail.com', 'wrong-pass'));

      expect(e.statusCode, 401);
      expect(e.code, 'invalid_credentials');
      expect(e.isUnauthorized, isFalse);
      expect(e.message, 'Wrong email or password.');
      expect(expired, 0);
      expect(api.isSignedIn, isTrue);
    });

    test('a 401 from signup does not fire it', () async {
      final server = Server((_) => jsonRes(sarah));
      final api = await signedIn(server);
      var expired = 0;
      api.onSessionExpired = () => expired++;
      server.handler = (_) => errorRes(401, 'unauthorized', 'No.');

      await failureOf(
        api.signup(
          name: 'A',
          email: 'a@b.co',
          password: 'longenough',
          role: 'crew',
        ),
      );

      expect(expired, 0);
      expect(api.isSignedIn, isTrue);
    });

    test('a late 401 for an old token leaves the new session alone', () async {
      final store = MemoryTokenStore('old');
      final server = Server((_) => jsonRes(sarah));
      final api = await signedIn(server, store: store);
      var expired = 0;
      api.onSessionExpired = () => expired++;

      final gate = Completer<void>();
      server.handler = (request) async {
        if (request.url.path == '/auth/login') {
          return jsonRes({'token': 'new', 'user': sarah});
        }
        await gate.future;
        return errorRes(401, 'unauthorized', 'Expired.');
      };
      final stale = failureOf(api.settings());
      await pumpEventQueue();
      await api.login('sarah.m@gmail.com', 'redefine');
      gate.complete();
      await stale;

      expect(expired, 0);
      expect(api.isSignedIn, isTrue);
      expect(await store.read(), 'new');
    });
  });

  group('errors', () {
    late Server server;
    late ApiClient api;

    setUp(() async {
      server = Server((_) => jsonRes(sarah));
      api = await signedIn(server);
    });

    test('402 card_declined', () async {
      server.handler = (_) =>
          errorRes(402, 'card_declined', 'Your card was declined.');
      final e = await failureOf(api.requestJob(propertyId: 'prop_maple'));
      expect(e.statusCode, 402);
      expect(e.code, 'card_declined');
      expect(e.message, 'Your card was declined.');
      expect(e.toString(), 'Your card was declined.');
      expect(e.extra, isEmpty);
      expect(e.isNetwork, isFalse);
      expect(e.isUnauthorized, isFalse);
      expect(api.isSignedIn, isTrue);
    });

    test('409 job_active keeps the extra jobId', () async {
      server.handler = (_) => errorRes(
        409,
        'job_active',
        'This property already has a plough on the way.',
        {'jobId': 'job_9'},
      );
      final e = await failureOf(api.requestJob(propertyId: 'prop_maple'));
      expect(e.statusCode, 409);
      expect(e.code, 'job_active');
      expect(e.message, 'This property already has a plough on the way.');
      expect(e.extra, {'jobId': 'job_9'});
    });

    test('an HTML 502 gets a readable message', () async {
      server.handler = (_) => http.Response(
        '<html><body><h1>502 Bad Gateway</h1></body></html>',
        502,
        headers: {'content-type': 'text/html'},
      );
      final e = await failureOf(api.jobs());
      expect(e.statusCode, 502);
      expect(e.code, 'bad_response');
      expect(e.message, isNot(contains('<')));
      expect(e.message, contains('temporarily unavailable'));
      expect(e.extra, isEmpty);
      expect(e.isNetwork, isFalse);
    });

    test('a plain-text 404 gets a readable message', () async {
      server.handler = (_) => http.Response('Route not found', 404);
      final e = await failureOf(api.job('nope'));
      expect(e.statusCode, 404);
      expect(e.code, 'bad_response');
      expect(e.message, isNot('Route not found'));
      expect(e.message, isNotEmpty);
    });

    test(
      'an error object without a message or code uses the defaults',
      () async {
        server.handler = (_) => jsonRes({'error': '  ', 'detail': 7}, 500);
        final e = await failureOf(api.settings());
        expect(e.statusCode, 500);
        expect(e.code, 'bad_response');
        expect(e.message, 'Something went wrong. Please try again.');
        expect(e.extra, {'detail': 7});
      },
    );

    test('invalid JSON with a 200 is a bad response', () async {
      server.handler = (_) => http.Response('{"id": "job_1", ', 200);
      final e = await failureOf(api.job('job_1'));
      expect(e.statusCode, 200);
      expect(e.code, 'bad_response');
      expect(e.isNetwork, isFalse);
      expect(api.isSignedIn, isTrue);
    });

    test('an empty 200 body is a bad response', () async {
      server.handler = (_) => http.Response('', 200);
      expect((await failureOf(api.settings())).code, 'bad_response');
    });

    test('the wrong top-level JSON type is a bad response', () async {
      server.handler = (_) => jsonRes({'jobs': []});
      expect((await failureOf(api.jobs())).code, 'bad_response');
      server.handler = (_) => jsonRes([]);
      expect((await failureOf(api.settings())).code, 'bad_response');
      server.handler = (_) => jsonRes(null);
      expect((await failureOf(api.billing())).code, 'bad_response');
    });

    test('a timeout', () async {
      final impatient = await signedIn(
        server,
        timeout: const Duration(milliseconds: 30),
      );
      var expired = 0;
      impatient.onSessionExpired = () => expired++;
      server.handler = (_) => Future.delayed(
        const Duration(milliseconds: 300),
        () => jsonRes(const {}),
      );

      final e = await failureOf(impatient.settings());

      expect(e.statusCode, 0);
      expect(e.code, 'timeout');
      expect(e.isNetwork, isTrue);
      expect(e.message, isNotEmpty);
      expect(impatient.isSignedIn, isTrue);
      expect(expired, 0);
    });

    test('a connection failure', () async {
      server.handler = (_) => throw http.ClientException('Connection refused');
      final e = await failureOf(api.properties());
      expect(e.statusCode, 0);
      expect(e.code, 'network');
      expect(e.isNetwork, isTrue);
      expect(
        e.message,
        "Couldn't reach the server. Check your connection and try again.",
      );
      expect(api.isSignedIn, isTrue);
    });

    test('an Error from the HTTP client is a network failure too', () async {
      for (final Object error in [
        ArgumentError('No host specified in URI localhost:8080/settings'),
        StateError('Client is closed'),
      ]) {
        server.handler = (_) => throw error;
        final e = await failureOf(api.settings());
        expect(e.statusCode, 0);
        expect(e.code, 'network');
        expect(api.isSignedIn, isTrue);
      }

      final throwing = ApiClient(baseUrl: base, httpClient: _ThrowingClient());
      expect((await failureOf(throwing.login('a@b.co', 'pw'))).code, 'network');
    });

    test('a base URL without a scheme fails as a network error', () async {
      // The real client: dart:io rejects the URL before opening a socket.
      final store = MemoryTokenStore('tok');
      final api = ApiClient(baseUrl: 'localhost:8080', tokenStore: store);

      final login = await failureOf(api.login('sarah.m@gmail.com', 'redefine'));
      expect(login.code, 'network');
      expect(login.isNetwork, isTrue);

      expect((await failureOf(api.restoreSession())).code, 'network');
      expect(await store.read(), 'tok');
    }, testOn: 'vm');

    test('a base URL that does not parse fails as a network error', () async {
      final unreachable = <http.Request>[];
      final api = ApiClient(
        baseUrl: 'http://localhost:port',
        tokenStore: MemoryTokenStore('tok'),
        httpClient: MockClient((request) async {
          unreachable.add(request);
          return jsonRes(sarah);
        }),
      );

      final e = await failureOf(api.restoreSession());
      expect(e.statusCode, 0);
      expect(e.code, 'network');
      expect((await failureOf(api.jobs(scope: 'open'))).code, 'network');
      expect(unreachable, isEmpty);
    });

    test('bodies are decoded as UTF-8 whatever the headers say', () async {
      server.handler = (_) => http.Response.bytes(
        utf8.encode(
          jsonEncode({
            'id': 'job_1',
            'customerName': 'Zoë Brontë',
            'note': 'Entrée côté garage — merci',
          }),
        ),
        200,
      );
      final job = await api.job('job_1');
      expect(job.customerName, 'Zoë Brontë');
      expect(job.note, 'Entrée côté garage — merci');

      server.handler = (_) => http.Response.bytes(
        utf8.encode(
          jsonEncode({'error': 'Propriété introuvable', 'code': 'not_found'}),
        ),
        404,
      );
      expect((await failureOf(api.job('x'))).message, 'Propriété introuvable');
    });
  });

  group('requests', () {
    late Server server;
    late ApiClient api;

    setUp(() async {
      server = Server((_) => jsonRes(const <String, dynamic>{}));
      api = await signedIn(server);
    });

    test('a trailing slash on the base URL is ignored', () async {
      final other = ApiClient(
        baseUrl: 'http://localhost:8080/',
        httpClient: server.client,
        tokenStore: MemoryTokenStore('tok'),
      );
      expect(other.baseUrl, 'http://localhost:8080');
      await other.restoreSession();
      expect(server.last.url.toString(), 'http://localhost:8080/auth/me');
    });

    test('requestJob', () async {
      server.handler = (_) => jsonRes({
        'id': 'job_new',
        'status': 'open',
        'shovel': true,
        'price': 45,
        'shovelPrice': 20,
        'total': 65,
        'payment': {'mode': 'stripe', 'status': 'authorized'},
      }, 201);

      final job = await api.requestJob(
        propertyId: 'prop_maple',
        shovel: true,
        note: 'Gate code 4411',
      );

      expect(server.last.method, 'POST');
      expect(server.last.url.toString(), '$base/jobs');
      expect(server.last.headers['content-type'], 'application/json');
      expect(bodyOf(server.last), {
        'propertyId': 'prop_maple',
        'shovel': true,
        'note': 'Gate code 4411',
      });
      expect(job.id, 'job_new');
      expect(job.total, 65);
      expect(job.payment.status, PaymentStatus.authorized);

      await api.requestJob(propertyId: 'prop_cedar');
      expect(bodyOf(server.last), {
        'propertyId': 'prop_cedar',
        'shovel': false,
      });

      await api.requestJob(
        propertyId: 'prop_cedar',
        note: '',
        payment: 'manual',
      );
      expect(bodyOf(server.last), {
        'propertyId': 'prop_cedar',
        'shovel': false,
        'payment': 'manual',
      });
    });

    test('requestJob and completeJob wait at least 30 s', () async {
      final impatient = await signedIn(
        server,
        timeout: const Duration(milliseconds: 30),
      );
      server.handler = (_) => Future.delayed(
        const Duration(milliseconds: 200),
        () => jsonRes({'id': 'job_1', 'status': 'done'}),
      );

      expect(
        (await impatient.requestJob(propertyId: 'prop_maple')).id,
        'job_1',
      );
      expect((await impatient.completeJob('job_1')).status, JobStatus.done);
      expect((await failureOf(impatient.startJob('job_1'))).code, 'timeout');
    });

    test('jobs sends scope and comma-separated statuses', () async {
      server.handler = (_) => jsonRes([
        {'id': 'job_1', 'status': 'open'},
        'junk',
        {'id': 'job_2', 'status': 'claimed'},
      ]);

      final jobs = await api.jobs(
        scope: 'open',
        status: [JobStatus.open, JobStatus.claimed],
      );

      expect(server.last.method, 'GET');
      expect(server.last.url.path, '/jobs');
      expect(server.last.url.queryParameters, {
        'scope': 'open',
        'status': 'open,claimed',
      });
      expect(jobs.map((j) => j.id), ['job_1', 'job_2']);

      await api.jobs();
      expect(server.last.url.toString(), '$base/jobs');
      expect(server.last.url.hasQuery, isFalse);

      await api.jobs(
        scope: 'mine',
        status: [JobStatus.unknown],
        propertyId: '',
      );
      expect(server.last.url.queryParameters, {'scope': 'mine'});
    });

    test('jobs sends every admin filter', () async {
      server.handler = (_) => jsonRes([]);
      final from = DateTime.utc(2026, 1, 1);
      final to = DateTime.utc(2026, 1, 8, 12, 30);

      await api.jobs(
        status: [JobStatus.done],
        propertyId: 'prop_maple',
        customerId: 'cust_sarah',
        crewId: 'crew_marcus',
        payment: [PaymentStatus.due, PaymentStatus.failed],
        from: from.toLocal(),
        to: to,
      );

      expect(server.last.url.queryParameters, {
        'status': 'done',
        'propertyId': 'prop_maple',
        'customerId': 'cust_sarah',
        'crewId': 'crew_marcus',
        'payment': 'due,failed',
        'from': '2026-01-01T00:00:00.000Z',
        'to': '2026-01-08T12:30:00.000Z',
      });
    });

    test('sendQuote', () async {
      server.handler = (_) => jsonRes({
        'id': 'quote_cabin',
        'status': 'sent',
        'price': 80,
        'crewPay': 45,
      });

      final quote = await api.sendQuote('quote_cabin', price: 80, crewPay: 45);

      expect(server.last.method, 'POST');
      expect(server.last.url.toString(), '$base/quotes/quote_cabin/send');
      expect(bodyOf(server.last), {'price': 80, 'crewPay': 45});
      expect(quote.status, QuoteStatus.sent);
      expect(quote.price, 80);
      expect(quote.crewPay, 45);
    });

    test('completeJob', () async {
      server.handler = (_) => jsonRes({
        'id': 'job_1',
        'status': 'done',
        'crewNote': 'Salted the steps',
      });

      final job = await api.completeJob('job_1', crewNote: 'Salted the steps');

      expect(server.last.method, 'POST');
      expect(server.last.url.toString(), '$base/jobs/job_1/complete');
      expect(bodyOf(server.last), {'crewNote': 'Salted the steps'});
      expect(job.status, JobStatus.done);
      expect(job.crewNote, 'Salted the steps');

      await api.completeJob('job_1');
      expect(server.last.body, '{}');
    });

    test('path ids are percent-encoded', () async {
      await api.job('a/b c?d#e');
      expect(server.last.url.toString(), '$base/jobs/a%2Fb%20c%3Fd%23e');
      await api.claimJob('../settings');
      expect(server.last.url.toString(), '$base/jobs/..%2Fsettings/claim');
      await api.crewPay('crew:id');
      expect(server.last.url.path, '/crew/crew%3Aid/pay');
    });

    test('ids that cannot name a resource fail locally as not_found', () async {
      for (final id in ['', '.', '..']) {
        for (final call in [
          () => api.job(id),
          () => api.cancelJob(id),
          () => api.quote(id),
          () => api.customer(id),
          () => api.crewPay(id),
          () => api.recordPayout(id),
        ]) {
          final e = await failureOf(call());
          expect(e.statusCode, 404, reason: '"$id"');
          expect(e.code, 'not_found', reason: '"$id"');
          expect(e.message, isNotEmpty);
        }
      }
      expect(server.requests, isEmpty);
    });

    test('job actions post an empty object to their route', () async {
      final actions = <String, Future<Job> Function()>{
        '/jobs/job_1/cancel': () => api.cancelJob('job_1'),
        '/jobs/job_1/claim': () => api.claimJob('job_1'),
        '/jobs/job_1/unclaim': () => api.unclaimJob('job_1'),
        '/jobs/job_1/start': () => api.startJob('job_1'),
        '/jobs/job_1/mark-paid': () => api.markJobPaid('job_1'),
        '/jobs/job_1/retry-payment': () => api.retryJobPayment('job_1'),
      };
      server.handler = (_) => jsonRes({'id': 'job_1', 'status': 'claimed'});
      for (final MapEntry(key: path, value: call) in actions.entries) {
        final job = await call();
        expect(server.last.method, 'POST', reason: path);
        expect(server.last.url.toString(), '$base$path');
        expect(server.last.body, '{}', reason: path);
        expect(server.last.headers['authorization'], 'Bearer tok');
        expect(job.id, 'job_1');
      }
    });

    test('properties and createProperty', () async {
      server.handler = (_) => jsonRes([
        {'id': 'prop_maple', 'status': 'active', 'price': 45},
      ]);
      final list = await api.properties();
      expect(server.last.url.toString(), '$base/properties');
      expect(list.single.price, 45);

      await api.properties(customerId: 'cust_sarah', status: 'active');
      expect(server.last.url.queryParameters, {
        'customerId': 'cust_sarah',
        'status': 'active',
      });

      server.handler = (_) => jsonRes({
        'property': {'id': 'prop_new', 'status': 'quoteRequested'},
        'quote': {'id': 'quote_new', 'status': 'pending'},
      }, 201);
      final created = await api.createProperty(
        name: 'Cabin',
        address: '88 Lakeside Rd',
      );
      expect(server.last.method, 'POST');
      expect(server.last.url.path, '/properties');
      expect(bodyOf(server.last), {
        'name': 'Cabin',
        'address': '88 Lakeside Rd',
        'illustration': 'house',
      });
      expect(created.property.id, 'prop_new');
      expect(created.property.status, PropertyStatus.quoteRequested);
      expect(created.quote.id, 'quote_new');
      expect(created.quote.status, QuoteStatus.pending);

      await api.createProperty(
        name: 'Cabin',
        address: '88 Lakeside Rd',
        illustration: 'cabin',
        note: 'Long gravel driveway',
        customerId: 'cust_sarah',
      );
      expect(bodyOf(server.last), {
        'name': 'Cabin',
        'address': '88 Lakeside Rd',
        'illustration': 'cabin',
        'note': 'Long gravel driveway',
        'customerId': 'cust_sarah',
      });
    });

    test('quote routes', () async {
      server.handler = (_) => jsonRes({
        'property': {'id': 'prop_birch', 'status': 'active'},
        'quote': {'id': 'quote_birch', 'status': 'accepted'},
      });
      final accepted = await api.acceptQuote('quote_birch');
      expect(server.last.method, 'POST');
      expect(server.last.url.path, '/quotes/quote_birch/accept');
      expect(accepted.quote.status, QuoteStatus.accepted);
      expect(accepted.property.status, PropertyStatus.active);

      final declined = await api.declineQuote('quote_birch');
      expect(server.last.url.path, '/quotes/quote_birch/decline');
      expect(declined.quote.id, 'quote_birch');

      final again = await api.requestQuoteAgain('prop_birch');
      expect(server.last.method, 'POST');
      expect(server.last.url.path, '/properties/prop_birch/request-quote');
      expect(again.property.id, 'prop_birch');

      server.handler = (_) => jsonRes({'id': 'quote_birch', 'status': 'sent'});
      expect((await api.quote('quote_birch')).status, QuoteStatus.sent);
      expect(server.last.method, 'GET');
      expect(server.last.url.toString(), '$base/quotes/quote_birch');

      server.handler = (_) => jsonRes([
        {'id': 'quote_cabin', 'status': 'pending'},
      ]);
      expect((await api.quotes(status: 'pending')).single.id, 'quote_cabin');
      expect(server.last.url.toString(), '$base/quotes?status=pending');
      await api.quotes();
      expect(server.last.url.toString(), '$base/quotes');
    });

    test('setPropertyPrice and updateSettings', () async {
      server.handler = (_) =>
          jsonRes({'id': 'prop_maple', 'price': 50, 'crewPay': 28});
      final p = await api.setPropertyPrice(
        'prop_maple',
        price: 50,
        crewPay: 28,
      );
      expect(server.last.method, 'POST');
      expect(server.last.url.path, '/properties/prop_maple/price');
      expect(bodyOf(server.last), {'price': 50, 'crewPay': 28});
      expect(p.crewPay, 28);

      server.handler = (_) => jsonRes({'shovelPrice': 25});
      final s = await api.updateSettings(shovelPrice: 25);
      expect(server.last.method, 'POST');
      expect(server.last.url.path, '/settings');
      expect(bodyOf(server.last), {'shovelPrice': 25});
      expect(s.shovelPrice, 25);

      await api.updateSettings(
        shovelPrice: 0,
        crewShovelBonus: 0,
        openJobExpiryHours: 72,
      );
      expect(bodyOf(server.last), {
        'shovelPrice': 0,
        'crewShovelBonus': 0,
        'openJobExpiryHours': 72,
      });
    });

    test('billing routes', () async {
      server.handler = (_) => jsonRes({'mode': 'stripe', 'card': null});
      expect((await api.billing()).needsCard, isTrue);
      expect(server.last.method, 'GET');
      expect(server.last.url.toString(), '$base/billing');

      expect((await api.refreshBilling()).mode, PaymentMode.stripe);
      expect(server.last.method, 'POST');
      expect(server.last.url.path, '/billing/refresh');

      server.handler = (_) =>
          jsonRes({'url': 'https://checkout.stripe.com/c/pay/cs_test_1'});
      final url = await api.createCardSetupSession();
      expect(server.last.method, 'POST');
      expect(server.last.url.path, '/billing/setup-session');
      expect(url.toString(), 'https://checkout.stripe.com/c/pay/cs_test_1');

      for (final bad in [null, '', 'not a url', 'javascript:alert(1)', 42]) {
        server.handler = (_) => jsonRes({'url': bad});
        final e = await failureOf(api.createCardSetupSession());
        expect(e.code, 'bad_response', reason: '$bad');
      }
    });

    test('tz is sent where the server computes today / this week', () async {
      final tz = '${DateTime.now().timeZoneOffset.inMinutes}';

      await api.crewPay('me');
      expect(server.last.method, 'GET');
      expect(server.last.url.path, '/crew/me/pay');
      expect(server.last.url.queryParameters, {'tz': tz});

      await api.crewPay('crew_marcus');
      expect(server.last.url.path, '/crew/crew_marcus/pay');

      await api.adminDashboard();
      expect(server.last.url.path, '/dashboard/admin');
      expect(server.last.url.queryParameters, {'tz': tz});

      server.handler = (_) => jsonRes({
        'active': [
          {'id': 'crew_marcus', 'status': 'active'},
          {'id': 'crew_jordan', 'status': 'active'},
        ],
        'pending': [
          {'id': 'crew_tasha', 'status': 'pending'},
        ],
        'rejected': [],
      });
      final crew = await api.crew();
      expect(server.last.url.path, '/crew');
      expect(server.last.url.queryParameters, {'tz': tz});
      expect(crew.active.map((c) => c.id), ['crew_marcus', 'crew_jordan']);
      expect(crew.pending.single.status, CrewStatus.pending);
      expect(crew.rejected, isEmpty);
    });

    test('crew admin routes', () async {
      server.handler = (_) => jsonRes({'id': 'crew_tasha', 'status': 'active'});
      // The answers carry this-week figures, so the caller's offset goes along.
      final tz = {'tz': '${DateTime.now().timeZoneOffset.inMinutes}'};
      expect((await api.approveCrew('crew_tasha')).status, CrewStatus.active);
      expect(server.last.method, 'POST');
      expect(server.last.url.path, '/crew/crew_tasha/approve');
      expect(server.last.url.queryParameters, tz);

      await api.rejectCrew('crew_tasha');
      expect(server.last.url.path, '/crew/crew_tasha/reject');
      expect(server.last.url.queryParameters, tz);

      server.handler = (_) => jsonRes({
        'payout': {'id': 'payout_2', 'amount': 60, 'jobCount': 2},
        'pay': {'crewId': 'crew_marcus', 'unpaidTotal': 0},
      });
      final paid = await api.recordPayout('crew_marcus', note: 'e-transfer');
      expect(server.last.method, 'POST');
      expect(server.last.url.path, '/crew/crew_marcus/payouts');
      expect(server.last.url.queryParameters, tz);
      expect(bodyOf(server.last), {'note': 'e-transfer'});
      expect(paid.payout.amount, 60);
      expect(paid.payout.jobCount, 2);
      expect(paid.pay.unpaidTotal, 0);

      await api.recordPayout('crew_marcus');
      expect(server.last.body, '{}');
    });

    test('customers', () async {
      server.handler = (_) => jsonRes([
        {'id': 'cust_anna', 'name': 'Anna Tomlinson'},
        {'id': 'cust_sarah', 'name': 'Sarah Mitchell'},
      ]);
      final list = await api.customers();
      expect(server.last.method, 'GET');
      expect(server.last.url.toString(), '$base/customers');
      expect(list.map((c) => c.id), ['cust_anna', 'cust_sarah']);

      server.handler = (_) => jsonRes({
        'id': 'cust_sarah',
        'name': 'Sarah Mitchell',
        'card': null,
        'properties': [
          {'id': 'prop_maple'},
        ],
        'jobs': [],
        'totals': {'billed': 155, 'outstanding': 0},
      });
      final detail = await api.customer('cust_sarah');
      expect(server.last.url.toString(), '$base/customers/cust_sarah');
      expect(detail.customer.name, 'Sarah Mitchell');
      expect(detail.card, isNull);
      expect(detail.properties.single.id, 'prop_maple');
      expect(detail.billed, 155);
    });
  });
}

class _BrokenStore implements TokenStore {
  @override
  Future<String?> read() => Future.error(StateError('storage unavailable'));

  @override
  Future<void> write(String token) =>
      Future.error(StateError('storage unavailable'));

  @override
  Future<void> clear() => Future.error(StateError('storage unavailable'));
}

/// Fails before any request is made, the way dart:io does for a URL it
/// cannot open.
class _ThrowingClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      throw ArgumentError('No host specified in URI ${request.url}');
}

import 'dart:convert';

import 'package:redefine_api/api.dart';
import 'package:redefine_api/src/auth/sessions.dart';
import 'package:redefine_api/src/data/persistence.dart';
import 'package:redefine_api/src/data/seed.dart';
import 'package:redefine_api/src/data/store.dart';
import 'package:redefine_api/src/payments/fake_gateway.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

/// A response of the app under test, read to the end.
class Reply {
  final int status;
  final Map<String, String> headers;
  final String text;

  Reply(this.status, this.headers, this.text);

  Object? get json => jsonDecode(text);
  Map<String, dynamic> get map => json as Map<String, dynamic>;
  List<Map<String, dynamic>> get list =>
      (json as List).cast<Map<String, dynamic>>();

  /// The machine code of an error body.
  String? get code => map['code'] as String?;

  @override
  String toString() => 'Reply($status $text)';
}

/// The real API (`createApp`) over a [MemoryPersistence], a
/// [FakePaymentGateway] (unless manual mode), a clock the test controls and
/// cheap password hashing. Nothing touches the network.
class TestApp {
  /// A Wednesday afternoon (UTC); the week began on Monday 2026-01-05.
  static final startTime = DateTime.utc(2026, 1, 7, 15);

  final MemoryPersistence persistence;
  final Store store;
  final App app;
  final Handler handler;

  /// Null in manual mode.
  final FakePaymentGateway? payments;

  /// Everything the server logged.
  final List<String> logs;

  /// The server's clock; move it with [advance] or by assignment.
  DateTime now;

  final Map<String, String> _tokens = {};

  TestApp._(
    this.persistence,
    this.store,
    this.app,
    this.handler,
    this.payments,
    this.logs,
    this.now,
  );

  /// [stripe] false gives manual mode. [seed] loads the demo accounts and the
  /// sample data into an empty database. Pass a [persistence] to boot a second server over the
  /// same database. With [behindProxy] the app takes the caller's address
  /// from `X-Forwarded-For`, as on Cloud Run (see [from]).
  static Future<TestApp> start({
    bool stripe = true,
    bool seed = true,
    bool behindProxy = false,
    String? adminInviteCode,
    String demoPassword = 'redefine',
    MemoryPersistence? persistence,
    DateTime? now,
  }) async {
    final logs = <String>[];
    final db = persistence ?? MemoryPersistence();
    final store = await Store.open(
      db,
      flushRetries: 0,
      retryDelay: Duration.zero,
      log: logs.add,
    );
    final gateway = stripe ? FakePaymentGateway() : null;
    late final TestApp t;
    final app = App(
      config: Config(
        pbkdf2Iterations: 1,
        adminInviteCode: adminInviteCode,
        demoPassword: demoPassword,
        publicBaseUrl: 'https://api.test',
        onCloudRun: behindProxy,
      ),
      store: store,
      payments: gateway,
      logRequests: false,
      clock: () => t.now,
      log: logs.add,
    );
    t = TestApp._(
      db,
      store,
      app,
      createApp(app),
      gateway,
      logs,
      now ?? startTime,
    );
    ensureSettings(store);
    if (seed) {
      await seedDemo(store, config: app.config, now: t.now, sampleData: true);
    }
    await store.flush();
    return t;
  }

  /// The gateway of a stripe-mode app.
  FakePaymentGateway get gateway => payments!;

  void advance(Duration by) => now = now.add(by);

  Future<Reply> call(
    String method,
    String path, {
    Object? body,
    String? token,
    Map<String, String> headers = const {},
  }) async {
    final response = await handler(
      Request(
        method,
        Uri.parse('http://localhost$path'),
        headers: {
          ...headers,
          if (token != null) 'authorization': 'Bearer $token',
        },
        body: body == null || body is String ? body : jsonEncode(body),
      ),
    );
    return Reply(
      response.statusCode,
      response.headers,
      await response.readAsString(),
    );
  }

  Future<Reply> get(String path, {String? token}) =>
      call('GET', path, token: token);

  Future<Reply> post(
    String path, {
    Object? body,
    String? token,
    Map<String, String> headers = const {},
  }) => call('POST', path, body: body, token: token, headers: headers);

  /// Headers that make a request arrive from [address] when the app was
  /// started with `behindProxy`.
  static Map<String, String> from(String address) => {
    'x-forwarded-for': address,
  };

  /// A session token for [userId], minted directly in the store.
  String tokenFor(String userId) => _tokens[userId] ??= store.tx(
    (tx) => createSession(tx, userId, now: now, ttl: const Duration(days: 30)),
  );

  // Tokens of the demo accounts.
  String get lia => tokenFor('user_lia');
  String get marcus => tokenFor('user_marcus');
  String get jordan => tokenFor('user_jordan');
  String get tasha => tokenFor('user_tasha');
  String get sarah => tokenFor('user_sarah');
  String get anna => tokenFor('user_anna');
  String get paul => tokenFor('user_paul');

  /// Logs in over HTTP and returns the token.
  Future<String> login(String email, {String password = 'redefine'}) async {
    final reply = await post(
      '/auth/login',
      body: {'email': email, 'password': password},
    );
    expect(reply.status, 200, reason: reply.text);
    return reply.map['token'] as String;
  }

  /// Saves a card for the customer behind [token] through the hosted setup
  /// flow (the fake completes the session at once).
  Future<void> saveCard(String token) async {
    final session = await post('/billing/setup-session', token: token);
    expect(session.status, 200, reason: session.text);
    final billing = await post('/billing/refresh', token: token);
    expect(billing.map['card'], isNotNull, reason: billing.text);
  }

  /// Requests a plough and returns the created job (caller's view).
  Future<Map<String, dynamic>> requestPlough(
    String token,
    String propertyId, {
    bool shovel = false,
    String? payment,
  }) async {
    final reply = await post(
      '/jobs',
      token: token,
      body: {'propertyId': propertyId, 'shovel': shovel, 'payment': ?payment},
    );
    expect(reply.status, 201, reason: reply.text);
    return reply.map;
  }

  /// Takes job [id] from open to done as the crew member behind [crewToken].
  Future<Map<String, dynamic>> plough(String crewToken, String id) async {
    for (final step in ['claim', 'start', 'complete']) {
      final reply = await post('/jobs/$id/$step', token: crewToken);
      expect(reply.status, 200, reason: '$step: ${reply.text}');
    }
    return (await get('/jobs/$id', token: lia)).map;
  }

  /// The stored job document, private fields included.
  Doc jobDoc(String id) => store.require(Collections.jobs, id);
}

/// Expects an error response with [status] and machine [code].
void expectError(Reply reply, int status, String code) {
  expect(
    (reply.status, reply.code),
    (status, code),
    reason: 'unexpected response: ${reply.text}',
  );
  expect(
    reply.map['error'],
    isA<String>().having((s) => s, 'text', isNotEmpty),
  );
}

/// Every map key that occurs anywhere inside [json].
Set<String> keysIn(Object? json) => switch (json) {
  Map<String, dynamic> m => {...m.keys, for (final v in m.values) ...keysIn(v)},
  List<dynamic> l => {for (final v in l) ...keysIn(v)},
  _ => const {},
};

/// Lets pending microtasks and zero-length timers run.
Future<void> pump([int turns = 5]) async {
  for (var i = 0; i < turns; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

/// Waits (up to about a second) until [condition] holds.
Future<void> until(bool Function() condition) async {
  for (var i = 0; i < 500 && !condition(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 2));
  }
  expect(condition(), isTrue, reason: 'condition not reached in time');
}

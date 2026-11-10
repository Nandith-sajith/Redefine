/// The real Redefine API on a local HTTP port, for tests that drive it
/// through `redefine_core`'s `ApiClient`.
library;

import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:redefine_api/testing.dart';
import 'package:redefine_core/redefine_core.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

export 'package:redefine_api/testing.dart'
    show FakeIntent, FakePaymentGateway, GatewayCall, PaymentOutcome;

/// `createApp` served over HTTP from an in-memory database, with a clock
/// and (in stripe mode) a fake payment gateway the test controls.
class TestServer {
  /// A Wednesday, seven minutes past the hour (UTC). Time-zone offsets are
  /// multiples of 15 minutes, so for the next eight minutes of server time
  /// "today" and "this week" mean the same in whatever zone the tests run.
  static final startTime = DateTime.utc(2026, 1, 7, 15, 7);

  /// The invite code that admin signup requires on this server.
  static const adminInviteCode = 'e2e-invite';

  /// Password of the demo accounts on a seeded server.
  static const demoPassword = 'redefine';

  final HttpServer _server;
  final http.Client _http;
  final MemoryPersistence _database;
  final FakePaymentGateway? _gateway;

  /// Everything the server logged.
  final List<String> logs;

  /// The origin the API is served from, without a trailing slash.
  late final String baseUrl = Uri(
    scheme: 'http',
    host: _server.address.address,
    port: _server.port,
  ).toString();

  DateTime _now = startTime;

  TestServer._(
    this._server,
    this._http,
    this._database,
    this._gateway,
    this.logs,
  );

  /// [stripe] false gives manual mode. [seed] loads the demo accounts and
  /// the sample data, dated relative to [startTime].
  static Future<TestServer> start({
    bool stripe = true,
    bool seed = false,
  }) async {
    final logs = <String>[];
    final gateway = stripe ? FakePaymentGateway() : null;
    final database = MemoryPersistence();
    final socket = await HttpServer.bind('localhost', 0);
    final server = TestServer._(socket, http.Client(), database, gateway, logs);
    final config = Config(
      port: socket.port,
      publicBaseUrl: server.baseUrl,
      adminInviteCode: adminInviteCode,
      demoPassword: demoPassword,
      pbkdf2Iterations: 1,
    );
    final store = await Store.open(database, log: logs.add);
    ensureSettings(store);
    if (seed) {
      await seedDemo(store, config: config, now: startTime, sampleData: true);
    }
    await store.flush();
    shelf_io.serveRequests(
      socket,
      createApp(
        App(
          config: config,
          store: store,
          payments: gateway,
          logRequests: false,
          clock: server._tick,
          log: logs.add,
        ),
      ),
    );
    return server;
  }

  /// The payment gateway of a stripe-mode server.
  FakePaymentGateway get gateway =>
      _gateway ?? (throw StateError('This server runs in manual mode.'));

  /// The server's clock.
  DateTime get now => _now;

  /// Moves the server's clock forward.
  void advance(Duration by) => _now = _now.add(by);

  /// A signed-out client of this server, as one app installation would hold.
  /// Pass the [tokens] of an earlier client to act as the same installation
  /// after a restart.
  ApiClient client([TokenStore? tokens]) => ApiClient(
    baseUrl: baseUrl,
    httpClient: _http,
    tokenStore: tokens ?? MemoryTokenStore(),
  );

  /// Fills in the hosted card page at [setupUrl] (the result of
  /// `createCardSetupSession`) as the customer would in their browser.
  /// Returns the id of the completed setup session.
  String completeCardSetup(Uri setupUrl, {String last4 = '4242'}) {
    final sessionId = setupUrl.pathSegments.last;
    gateway.completeSetup(sessionId, last4: last4);
    return sessionId;
  }

  /// Follows the redirect the hosted card page sends the customer's browser
  /// on after setup session [sessionId]: the return URL this server gave the
  /// payment provider. Returns the page the customer sees.
  Future<http.Response> returnFromCardSetup(String sessionId) {
    final successUrl =
        gateway.callsTo('createSetupSession').last.args['successUrl'] as String;
    return _http.get(
      Uri.parse(successUrl.replaceFirst('{CHECKOUT_SESSION_ID}', sessionId)),
    );
  }

  /// Makes the server's next database write fail, as a storage outage
  /// would.
  void failNextSave() => _database.failNextCommits(1, transient: false);

  /// Stops answering: open connections are dropped and new ones refused, as
  /// when the API cannot be reached. Clients stay usable.
  Future<void> shutDown() => _server.close(force: true);

  /// Shuts the server down and releases the clients' connections.
  Future<void> close() async {
    _http.close();
    await shutDown();
  }

  // One millisecond per reading, so no two events share a timestamp and
  // everything the server sorts by time has a definite order.
  DateTime _tick() => _now = _now.add(const Duration(milliseconds: 1));
}

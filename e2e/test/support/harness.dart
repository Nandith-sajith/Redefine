import 'package:redefine_core/redefine_core.dart';
import 'package:redefine_e2e/redefine_e2e.dart';
import 'package:test/test.dart';

/// Starts a server for the running test. It is shut down when the test
/// ends; what it logged is printed if the test fails.
Future<TestServer> startServer({bool stripe = true, bool seed = false}) async {
  final server = await TestServer.start(stripe: stripe, seed: seed);
  addTearDown(() async {
    if (server.logs.isNotEmpty) {
      printOnFailure('Server log:\n${server.logs.join('\n')}');
    }
    await server.close();
  });
  return server;
}

/// Password of every account a test signs up.
const password = 'plough-the-drive-1';

/// The email a test account called [name] signs up with.
String emailOf(String name) =>
    '${name.toLowerCase().replaceAll(' ', '.')}@example.com';

/// Creates an account through the API and returns its signed-in client.
Future<ApiClient> signUp(
  TestServer server,
  String name, {
  String role = 'customer',
  String? phone,
}) async {
  final client = server.client();
  await client.signup(
    name: name,
    email: emailOf(name),
    password: password,
    role: role,
    phone: phone,
    inviteCode: role == 'admin' ? TestServer.adminInviteCode : null,
  );
  return client;
}

/// Signs in as one of the demo accounts of a seeded server.
Future<ApiClient> signIn(TestServer server, String email) async {
  final client = server.client();
  await client.login(email, TestServer.demoPassword);
  return client;
}

/// Signs up a crew member and has [admin] approve them.
Future<ApiClient> hireCrew(
  TestServer server,
  ApiClient admin,
  String name,
) async {
  final crew = await signUp(server, name, role: 'crew');
  await admin.approveCrew(crew.currentUser!.linkedId!);
  return crew;
}

/// Adds a property for [customer] and takes it through the quote: [admin]
/// offers [price] and [crewPay], the customer accepts.
Future<Property> activeProperty(
  ApiClient customer,
  ApiClient admin, {
  String name = 'Home',
  String address = '12 Frost Lane',
  int price = 45,
  int crewPay = 25,
}) async {
  final requested = await customer.createProperty(name: name, address: address);
  await admin.sendQuote(requested.quote.id, price: price, crewPay: crewPay);
  return (await customer.acceptQuote(requested.quote.id)).property;
}

/// Saves a card for [customer]; the fake hosted page completes at once.
Future<void> saveCard(ApiClient customer) async {
  await customer.createCardSetupSession();
  expect((await customer.refreshBilling()).card, isNotNull);
}

/// Takes an open job to done as [crew].
Future<Job> plough(ApiClient crew, String jobId, {String? crewNote}) async {
  await crew.claimJob(jobId);
  await crew.startJob(jobId);
  return crew.completeJob(jobId, crewNote: crewNote);
}

/// Reads with [read] until [done] accepts the result (for about a second),
/// for what the server finishes after it has answered.
Future<T> eventually<T>(
  Future<T> Function() read,
  bool Function(T value) done,
) async {
  for (var tries = 0; ; tries++) {
    final value = await read();
    if (done(value)) return value;
    if (tries == 100) fail('Still not there: $value');
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

/// Expects [call] to fail with an [ApiException] carrying [status] and
/// [code]; returns it for further checks.
Future<ApiException> expectApiError(
  Future<Object?> call,
  int status,
  String code,
) async {
  try {
    await call;
  } on ApiException catch (e) {
    expect((e.statusCode, e.code), (status, code), reason: e.message);
    expect(e.message, isNotEmpty);
    return e;
  }
  fail('Expected $status $code, but the call succeeded.');
}

/// Matches a parsed (local) timestamp at the same instant as [expected].
Matcher isMoment(DateTime expected) =>
    isA<DateTime>().having((t) => t.toUtc(), 'instant', expected.toUtc());

import 'package:redefine_core/redefine_core.dart';
import 'package:redefine_e2e/redefine_e2e.dart';
import 'package:test/test.dart';

import 'support/harness.dart';

void main() {
  late TestServer server;

  setUp(() async => server = await startServer(stripe: false, seed: true));

  test('customers see only their own properties, quotes and jobs', () async {
    final sarah = await signIn(server, 'sarah.m@gmail.com');
    final anna = await signIn(server, 'anna.t@gmail.com');

    expect((await anna.job('job_cedar_2')).id, 'job_cedar_2');
    await expectApiError(sarah.job('job_cedar_2'), 404, 'not_found');
    await expectApiError(sarah.cancelJob('job_cedar_2'), 404, 'not_found');
    await expectApiError(sarah.quote('quote_cedar'), 404, 'not_found');
    await expectApiError(sarah.acceptQuote('quote_birch'), 404, 'not_found');
    await expectApiError(
      sarah.requestJob(propertyId: 'prop_cedar'),
      404,
      'not_found',
    );
    await expectApiError(
      sarah.requestQuoteAgain('prop_cedar'),
      404,
      'not_found',
    );

    expect((await sarah.properties()).map((p) => p.id), [
      'prop_maple',
      'prop_cabin',
    ]);
    expect((await sarah.quotes()).map((q) => q.id), [
      'quote_cabin',
      'quote_maple',
    ]);
    final jobs = await sarah.jobs();
    expect(jobs.map((j) => j.id), [
      'job_maple_3',
      'job_maple_2',
      'job_maple_1',
    ]);
    expect(jobs.map((j) => j.customerId).toSet(), {'cust_sarah'});
    expect((await anna.job('job_cedar_2')).status, JobStatus.open);
  });

  test('every role is kept to its own routes', () async {
    final lia = await signIn(server, 'lia@redefine.co');
    final sarah = await signIn(server, 'sarah.m@gmail.com');
    final marcus = await signIn(server, 'marcus@redefine.co');

    final denied = <Future<Object?> Function()>[
      sarah.adminDashboard,
      sarah.customers,
      () => sarah.customer('cust_sarah'),
      sarah.crew,
      () => sarah.crewPay('me'),
      () => sarah.claimJob('job_cedar_2'),
      () => sarah.markJobPaid('job_maple_3'),
      () => sarah.sendQuote('quote_cabin', price: 1, crewPay: 0),
      () => sarah.updateSettings(shovelPrice: 0),
      marcus.adminDashboard,
      marcus.properties,
      marcus.quotes,
      marcus.billing,
      () => marcus.requestJob(propertyId: 'prop_maple'),
      () => marcus.cancelJob('job_cedar_2'),
      () => marcus.recordPayout('crew_marcus'),
      lia.billing,
      () => lia.claimJob('job_cedar_2'),
      () => lia.startJob('job_cedar_2'),
      () => lia.acceptQuote('quote_birch'),
      () => lia.requestQuoteAgain('prop_birch'),
    ];
    for (final call in denied) {
      await expectApiError(call(), 403, 'forbidden');
    }

    // Crew see the open jobs and their own, nobody else's.
    await expectApiError(marcus.job('job_cedar_1'), 404, 'not_found');
    await expectApiError(marcus.startJob('job_cedar_1'), 404, 'not_found');
    await expectApiError(marcus.crewPay('crew_jordan'), 404, 'not_found');
    await expectApiError(lia.job('job_nowhere'), 404, 'not_found');
    await expectApiError(lia.customer('cust_nobody'), 404, 'not_found');
    expect(sarah.isSignedIn && marcus.isSignedIn && lia.isSignedIn, isTrue);
  });

  test('crew work only once approved', () async {
    final lia = await signIn(server, 'lia@redefine.co');
    final tasha = await signIn(server, 'tasha@redefine.co');
    expect(tasha.currentUser!.crewStatus, CrewStatus.pending);
    expect(tasha.currentUser!.linkedId, 'crew_tasha');

    await expectApiError(tasha.jobs(scope: 'open'), 403, 'crew_pending');
    await expectApiError(tasha.job('job_cedar_2'), 403, 'crew_pending');
    await expectApiError(tasha.claimJob('job_cedar_2'), 403, 'crew_pending');
    await expectApiError(tasha.crewPay('me'), 403, 'crew_pending');
    expect((await tasha.settings()).crewShovelBonus, 10);

    final rejected = await lia.rejectCrew('crew_tasha');
    expect(rejected.status, CrewStatus.rejected);
    await expectApiError(tasha.jobs(), 403, 'crew_rejected');
    expect((await tasha.me()).crewStatus, CrewStatus.rejected);
    final lists = await lia.crew();
    expect(lists.pending, isEmpty);
    expect(lists.rejected.single.id, 'crew_tasha');

    final approved = await lia.approveCrew('crew_tasha');
    expect(approved.status, CrewStatus.active);
    expect((await tasha.jobs(scope: 'open')).single.id, 'job_cedar_2');
    expect((await tasha.crewPay('me')).earnedAllTime, 0);
  });

  test('rejecting a crew member reopens the jobs they had accepted', () async {
    final lia = await signIn(server, 'lia@redefine.co');
    final anna = await signIn(server, 'anna.t@gmail.com');
    final jordan = await signIn(server, 'jordan@redefine.co');
    final marcus = await signIn(server, 'marcus@redefine.co');

    await jordan.claimJob('job_cedar_2');
    expect((await anna.job('job_cedar_2')).crewName, 'Jordan Park');
    expect(await marcus.jobs(scope: 'open'), isEmpty);

    await lia.rejectCrew('crew_jordan');
    final reopened = await anna.job('job_cedar_2');
    expect((reopened.status, reopened.crewName), (JobStatus.open, ''));
    expect(reopened.claimedAt, isNull);
    expect((await marcus.jobs(scope: 'open')).single.id, 'job_cedar_2');
    await expectApiError(jordan.jobs(), 403, 'crew_rejected');
  });

  test('a session survives a restart and ends with logout', () async {
    final tokens = MemoryTokenStore();
    final app = server.client(tokens);
    final signedIn = await app.login(
      'Sarah.M@gmail.com',
      TestServer.demoPassword,
    );
    final user = signedIn.user;
    expect(
      (user.id, user.role, user.linkedId),
      ('user_sarah', 'customer', 'cust_sarah'),
    );
    expect((user.name, user.initials), ('Sarah Mitchell', 'SM'));
    expect((user.phone, user.crewStatus), ('(807) 555-0142', null));
    expect(await tokens.read(), signedIn.token);

    final relaunched = server.client(tokens);
    expect(relaunched.isSignedIn, isFalse);
    expect((await relaunched.restoreSession())?.id, 'user_sarah');
    expect(relaunched.isSignedIn, isTrue);
    expect(relaunched.currentUser?.email, 'sarah.m@gmail.com');
    expect(await relaunched.properties(), hasLength(2));

    var expired = 0;
    relaunched.onSessionExpired = () => expired++;
    await app.logout();
    expect(app.isSignedIn, isFalse);
    expect(app.currentUser, isNull);
    expect(await tokens.read(), isNull);
    await expectApiError(app.me(), 401, 'unauthorized');

    // The other client still holds the token; the server no longer does.
    final refused = await expectApiError(
      relaunched.properties(),
      401,
      'unauthorized',
    );
    expect(refused.isUnauthorized, isTrue);
    expect(expired, 1);
    expect(relaunched.isSignedIn, isFalse);
    expect(await server.client(tokens).restoreSession(), isNull);
  });

  test(
    'an unreachable server is a network error and keeps the session',
    () async {
      final tokens = MemoryTokenStore();
      final signedIn = await server
          .client(tokens)
          .login('sarah.m@gmail.com', TestServer.demoPassword);
      await server.shutDown();

      final relaunched = server.client(tokens);
      final offline = await expectApiError(
        relaunched.restoreSession(),
        0,
        'network',
      );
      expect(offline.isNetwork, isTrue);
      expect(relaunched.isSignedIn, isTrue);
      expect(relaunched.currentUser, isNull);
      expect(await tokens.read(), signedIn.token);
    },
  );

  test('a stored token the server does not know is dropped', () async {
    final tokens = MemoryTokenStore('not-a-session');
    final app = server.client(tokens);
    var expired = 0;
    app.onSessionExpired = () => expired++;

    expect(await app.restoreSession(), isNull);
    expect(app.isSignedIn, isFalse);
    expect(await tokens.read(), isNull);
    expect(expired, 0);
  });

  test('sign-in and sign-up failures carry their codes', () async {
    final app = server.client();
    final wrong = await expectApiError(
      app.login('sarah.m@gmail.com', 'not-the-password'),
      401,
      'invalid_credentials',
    );
    expect(wrong.isUnauthorized, isFalse);
    await expectApiError(
      app.login('nobody@example.com', 'not-the-password'),
      401,
      'invalid_credentials',
    );
    await expectApiError(
      app.signup(
        name: 'Sarah Again',
        email: 'Sarah.M@gmail.com',
        password: password,
        role: 'customer',
      ),
      409,
      'email_taken',
    );
    final tooShort = await expectApiError(
      app.signup(
        name: 'New Person',
        email: emailOf('New Person'),
        password: 'short',
        role: 'customer',
      ),
      400,
      'validation',
    );
    expect(tooShort.message, contains('password'));
    for (final inviteCode in [null, 'not-the-code']) {
      await expectApiError(
        app.signup(
          name: 'New Person',
          email: emailOf('New Person'),
          password: password,
          role: 'admin',
          inviteCode: inviteCode,
        ),
        403,
        'invite_required',
      );
    }
    expect(app.isSignedIn, isFalse);

    final invited = await app.signup(
      name: 'New Person',
      email: emailOf('New Person'),
      password: password,
      role: 'admin',
      inviteCode: TestServer.adminInviteCode,
    );
    expect((invited.user.role, invited.user.linkedId), ('admin', null));
    expect((await app.adminDashboard()).counts.pendingCrew, 1);
  });

  test('repeated wrong passwords lock the login for a minute', () async {
    final app = server.client();
    for (var attempt = 0; attempt < 5; attempt++) {
      await expectApiError(
        app.login('sarah.m@gmail.com', 'not-the-password'),
        401,
        'invalid_credentials',
      );
    }
    await expectApiError(
      app.login('sarah.m@gmail.com', TestServer.demoPassword),
      429,
      'rate_limited',
    );

    server.advance(const Duration(seconds: 61));
    final signedIn = await app.login(
      'sarah.m@gmail.com',
      TestServer.demoPassword,
    );
    expect(signedIn.user.id, 'user_sarah');
  });
}

import 'package:test/test.dart';

import 'support/harness.dart';

/// Every route of the contract that needs a token: (method, path, roles
/// that may use it).
const _routes = [
  ('POST', '/auth/logout', 'ACW'),
  ('GET', '/auth/me', 'ACW'),
  ('GET', '/settings', 'ACW'),
  ('POST', '/settings', 'A'),
  ('GET', '/properties', 'AC'),
  ('POST', '/properties', 'AC'),
  ('POST', '/properties/prop_maple/request-quote', 'C'),
  ('POST', '/properties/prop_maple/price', 'A'),
  ('GET', '/quotes', 'AC'),
  ('GET', '/quotes/quote_birch', 'AC'),
  ('POST', '/quotes/quote_birch/send', 'A'),
  ('POST', '/quotes/quote_birch/accept', 'C'),
  ('POST', '/quotes/quote_birch/decline', 'C'),
  ('POST', '/jobs', 'AC'),
  ('GET', '/jobs', 'ACW'),
  ('GET', '/jobs/job_cedar_2', 'ACW'),
  ('POST', '/jobs/job_cedar_2/claim', 'W'),
  ('POST', '/jobs/job_cedar_2/unclaim', 'AW'),
  ('POST', '/jobs/job_cedar_2/start', 'W'),
  ('POST', '/jobs/job_cedar_2/complete', 'AW'),
  ('POST', '/jobs/job_cedar_2/cancel', 'AC'),
  ('POST', '/jobs/job_cedar_1/mark-paid', 'A'),
  ('POST', '/jobs/job_cedar_1/retry-payment', 'A'),
  ('GET', '/billing', 'C'),
  ('POST', '/billing/setup-session', 'C'),
  ('POST', '/billing/refresh', 'C'),
  ('GET', '/crew', 'A'),
  ('POST', '/crew/crew_tasha/approve', 'A'),
  ('POST', '/crew/crew_tasha/reject', 'A'),
  ('GET', '/crew/crew_marcus/pay', 'AW'),
  ('POST', '/crew/crew_marcus/payouts', 'A'),
  ('GET', '/customers', 'A'),
  ('GET', '/customers/cust_sarah', 'A'),
  ('GET', '/dashboard/admin', 'A'),
];

void main() {
  late TestApp t;

  setUp(() async => t = await TestApp.start());

  group('without a token', () {
    test('every protected route answers 401 unauthorized', () async {
      for (final (method, path, _) in _routes) {
        expectError(await t.call(method, path), 401, 'unauthorized');
        expectError(
          await t.call(method, path, token: 'rdf_not-a-session'),
          401,
          'unauthorized',
        );
      }
    });

    test('an expired session is 401', () async {
      final token = t.sarah;
      t.advance(const Duration(days: 29));
      expect((await t.get('/auth/me', token: token)).status, 200);
      t.advance(const Duration(days: 2));
      expectError(await t.get('/auth/me', token: token), 401, 'unauthorized');
    });

    test('the public routes work', () async {
      final health = await t.get('/health');
      expect(health.status, 200);
      expect(health.map, {
        'status': 'ok',
        'service': 'redefine-api',
        'persistence': 'memory',
        'payments': 'stripe-test',
      });
      expect((await t.get('/billing/return')).status, 200);
      expect((await t.call('OPTIONS', '/jobs/anything/claim')).status, 200);
      // Reached the handlers: a validation error, not a 401.
      expectError(await t.post('/auth/login'), 400, 'validation');
      expectError(await t.post('/auth/signup'), 400, 'validation');
    });
  });

  test('a role that a route is not listed for gets 403 forbidden', () async {
    final tokens = {'A': t.lia, 'C': t.sarah, 'W': t.marcus};
    for (final (method, path, allowed) in _routes) {
      for (final role in tokens.keys) {
        if (allowed.contains(role)) continue;
        expectError(
          await t.call(method, path, token: tokens[role]),
          403,
          'forbidden',
        );
      }
    }
    // Nothing was changed by the refused calls.
    expect(t.jobDoc('job_cedar_2')['status'], 'open');
    expect((t.jobDoc('job_cedar_1')['payment'] as Map)['status'], 'due');
  });

  group('a customer and other customers\' data', () {
    test('lists only contain their own records', () async {
      final properties = await t.get('/properties', token: t.sarah);
      expect(properties.list.map((p) => p['id']), ['prop_maple', 'prop_cabin']);
      // The admin-only customerId filter is ignored for customers.
      final filtered = await t.get(
        '/properties?customerId=cust_anna',
        token: t.sarah,
      );
      expect(filtered.list.map((p) => p['id']), ['prop_maple', 'prop_cabin']);

      final quotes = await t.get('/quotes', token: t.paul);
      expect(quotes.list.map((q) => q['id']), ['quote_birch']);

      final jobs = await t.get('/jobs', token: t.anna);
      expect(jobs.list.map((j) => j['id']), ['job_cedar_2', 'job_cedar_1']);
      final none = await t.get('/jobs?propertyId=prop_cedar', token: t.sarah);
      expect(none.list, isEmpty);
    });

    test('reading or acting on someone else\'s records is 404', () async {
      // Sarah against Paul's quote and Anna's property and jobs.
      final attempts = [
        ('GET', '/quotes/quote_birch', null),
        ('POST', '/quotes/quote_birch/accept', null),
        ('POST', '/quotes/quote_birch/decline', null),
        ('POST', '/properties/prop_cedar/request-quote', null),
        ('POST', '/jobs', {'propertyId': 'prop_cedar'}),
        ('GET', '/jobs/job_cedar_2', null),
        ('POST', '/jobs/job_cedar_2/cancel', null),
      ];
      for (final (method, path, body) in attempts) {
        expectError(
          await t.call(method, path, token: t.sarah, body: body),
          404,
          'not_found',
        );
      }
      expect(t.jobDoc('job_cedar_2')['status'], 'open');
      expect(
        (await t.get('/quotes/quote_birch', token: t.paul)).map['status'],
        'sent',
      );
    });

    test('unknown ids are 404 for the owner role and the admin', () async {
      for (final (method, path, token) in [
        ('GET', '/quotes/quote_nope', t.sarah),
        ('GET', '/quotes/quote_nope', t.lia),
        ('POST', '/quotes/quote_nope/send', t.lia),
        ('POST', '/quotes/quote_nope/accept', t.sarah),
        ('POST', '/properties/prop_nope/price', t.lia),
        ('POST', '/properties/prop_nope/request-quote', t.sarah),
        ('GET', '/jobs/job_nope', t.lia),
        ('GET', '/jobs/job_nope', t.sarah),
        ('GET', '/jobs/job_nope', t.marcus),
        ('POST', '/jobs/job_nope/claim', t.marcus),
        ('POST', '/jobs/job_nope/unclaim', t.lia),
        ('POST', '/jobs/job_nope/start', t.marcus),
        ('POST', '/jobs/job_nope/complete', t.lia),
        ('POST', '/jobs/job_nope/cancel', t.lia),
        ('POST', '/jobs/job_nope/mark-paid', t.lia),
        ('POST', '/jobs/job_nope/retry-payment', t.lia),
        ('POST', '/crew/crew_nope/approve', t.lia),
        ('POST', '/crew/crew_nope/reject', t.lia),
        ('GET', '/crew/crew_nope/pay', t.lia),
        ('POST', '/crew/crew_nope/payouts', t.lia),
        ('GET', '/customers/cust_nope', t.lia),
      ]) {
        expectError(await t.call(method, path, token: token), 404, 'not_found');
      }
      expectError(
        await t.post('/jobs', token: t.lia, body: {'propertyId': 'prop_nope'}),
        404,
        'not_found',
      );
      expectError(
        await t.post(
          '/properties',
          token: t.lia,
          body: {'customerId': 'cust_nope', 'name': 'X', 'address': 'Y'},
        ),
        404,
        'not_found',
      );
    });
  });

  group('crew', () {
    test('a pending crew member is kept off the job and pay routes', () async {
      for (final (method, path) in [
        ('GET', '/jobs'),
        ('GET', '/jobs?scope=open'),
        ('GET', '/jobs/job_cedar_2'),
        ('POST', '/jobs/job_cedar_2/claim'),
        ('POST', '/jobs/job_cedar_2/unclaim'),
        ('POST', '/jobs/job_cedar_2/start'),
        ('POST', '/jobs/job_cedar_2/complete'),
        ('GET', '/crew/me/pay'),
      ]) {
        expectError(
          await t.call(method, path, token: t.tasha),
          403,
          'crew_pending',
        );
      }
      // Their own account and the settings stay readable.
      final me = await t.get('/auth/me', token: t.tasha);
      expect(me.map['crewStatus'], 'pending');
      expect((await t.get('/settings', token: t.tasha)).status, 200);

      await t.post('/crew/crew_tasha/approve', token: t.lia);
      expect(
        (await t.get('/auth/me', token: t.tasha)).map['crewStatus'],
        'active',
      );
      expect((await t.get('/jobs?scope=open', token: t.tasha)).status, 200);
    });

    test('a rejected crew member gets crew_rejected', () async {
      await t.post('/crew/crew_tasha/reject', token: t.lia);
      expectError(
        await t.get('/jobs?scope=open', token: t.tasha),
        403,
        'crew_rejected',
      );
      expectError(
        await t.post('/jobs/job_cedar_2/claim', token: t.tasha),
        403,
        'crew_rejected',
      );
      expectError(
        await t.get('/crew/me/pay', token: t.tasha),
        403,
        'crew_rejected',
      );
    });

    test('cannot see or act on a job another crew member took', () async {
      await t.post('/jobs/job_cedar_2/claim', token: t.marcus);
      for (final (method, path) in [
        ('GET', '/jobs/job_cedar_2'),
        ('POST', '/jobs/job_cedar_2/unclaim'),
        ('POST', '/jobs/job_cedar_2/start'),
        ('POST', '/jobs/job_cedar_2/complete'),
      ]) {
        expectError(
          await t.call(method, path, token: t.jordan),
          404,
          'not_found',
        );
      }
      expect((await t.get('/jobs?scope=open', token: t.jordan)).list, isEmpty);
      expect((await t.get('/jobs', token: t.jordan)).list.map((j) => j['id']), [
        'job_cedar_1',
      ]);
      expect(t.jobDoc('job_cedar_2')['crewId'], 'crew_marcus');
    });

    test('can only read their own pay', () async {
      expect(
        (await t.get('/crew/crew_marcus/pay', token: t.marcus)).map['crewId'],
        'crew_marcus',
      );
      expect(
        (await t.get('/crew/me/pay', token: t.jordan)).map['crewId'],
        'crew_jordan',
      );
      expectError(
        await t.get('/crew/crew_jordan/pay', token: t.marcus),
        404,
        'not_found',
      );
      // The admin has no pay of their own.
      expectError(await t.get('/crew/me/pay', token: t.lia), 404, 'not_found');
    });
  });

  group('signup roles', () {
    Future<Reply> signup(
      String role, {
      String? inviteCode,
      String? email,
      String? from,
    }) => t.post(
      '/auth/signup',
      body: {
        'name': 'Robin Vale',
        'email': email ?? 'robin@example.com',
        'password': 'long-enough',
        'role': role,
        'inviteCode': ?inviteCode,
      },
      headers: from == null ? const {} : TestApp.from(from),
    );

    test(
      'admin signup is refused when the server has no invite code',
      () async {
        expectError(await signup('admin'), 403, 'invite_required');
        expectError(
          await signup('admin', inviteCode: 'guess'),
          403,
          'invite_required',
        );
        expectError(
          await signup('admin', inviteCode: ''),
          403,
          'invite_required',
        );
      },
    );

    test('admin signup needs the exact invite code', () async {
      t = await TestApp.start(adminInviteCode: 'plough-2026');
      expectError(await signup('admin'), 403, 'invite_required');
      expectError(
        await signup('admin', inviteCode: 'plough-2025'),
        403,
        'invite_required',
      );
      expectError(
        await signup('admin', inviteCode: 'plough-2026-and-more'),
        403,
        'invite_required',
      );
      final ok = await signup('admin', inviteCode: 'plough-2026');
      expect(ok.status, 201, reason: ok.text);
      final user = ok.map['user'] as Map;
      expect(user['role'], 'admin');
      expect(user['linkedId'], isNull);
      expect(user['crewStatus'], isNull);
      final token = ok.map['token'] as String;
      expect((await t.get('/dashboard/admin', token: token)).status, 200);
      // The invite code plays no part for the other roles.
      expect((await signup('customer', email: 'c@example.com')).status, 201);
    });

    test('a client gets five wrong invite codes a minute', () async {
      t = await TestApp.start(adminInviteCode: 'plough-2026');
      for (var i = 0; i < 5; i++) {
        expectError(
          await signup('admin', inviteCode: 'guess-$i'),
          403,
          'invite_required',
        );
        t.advance(const Duration(seconds: 5));
      }
      expectError(
        await signup('admin', inviteCode: 'guess-5'),
        429,
        'rate_limited',
      );
      // While the limit holds even the right code is refused, so a guesser
      // learns nothing from it.
      expectError(
        await signup('admin', inviteCode: 'plough-2026'),
        429,
        'rate_limited',
      );
      expect(t.store.userByEmail('robin@example.com'), isNull);
      // The other roles are not held up.
      expect((await signup('customer', email: 'c@example.com')).status, 201);

      t.advance(const Duration(seconds: 36));
      final ok = await signup('admin', inviteCode: 'plough-2026');
      expect(ok.status, 201, reason: ok.text);
      expect((ok.map['user'] as Map)['role'], 'admin');
    });

    test('all clients together get twenty wrong codes a minute', () async {
      t = await TestApp.start(
        adminInviteCode: 'plough-2026',
        behindProxy: true,
      );
      for (var i = 0; i < 20; i++) {
        expectError(
          await signup('admin', inviteCode: 'guess', from: '198.51.100.$i'),
          403,
          'invite_required',
        );
      }
      expectError(
        await signup('admin', inviteCode: 'plough-2026', from: '203.0.113.9'),
        429,
        'rate_limited',
      );
      t.advance(const Duration(seconds: 61));
      expect(
        (await signup(
          'admin',
          inviteCode: 'plough-2026',
          from: '203.0.113.9',
        )).status,
        201,
      );
    });

    test('without an invite code on the server nothing is counted', () async {
      for (var i = 0; i < 8; i++) {
        expectError(
          await signup('admin', inviteCode: 'guess-$i'),
          403,
          'invite_required',
        );
      }
    });

    test('crew signup creates a pending crew member', () async {
      final reply = await signup('crew');
      expect(reply.status, 201, reason: reply.text);
      final user = reply.map['user'] as Map;
      expect(user['role'], 'crew');
      expect(user['crewStatus'], 'pending');
      expect(user['linkedId'], startsWith('crew_'));
      final token = reply.map['token'] as String;
      expectError(await t.get('/jobs', token: token), 403, 'crew_pending');

      final crew = await t.get('/crew', token: t.lia);
      final pending = (crew.map['pending'] as List).cast<Map>();
      expect(pending.map((c) => c['name']), ['Tasha Rivera', 'Robin Vale']);
      expect(pending.last['id'], user['linkedId']);
      expect(pending.last['userId'], user['id']);
    });

    test('customer is the default role', () async {
      final reply = await t.post(
        '/auth/signup',
        body: {
          'name': 'Dana',
          'email': 'dana@example.com',
          'password': 'long-enough',
        },
      );
      final user = reply.map['user'] as Map;
      expect(user['role'], 'customer');
      expect(user['initials'], 'DA');
      expect(user['phone'], '');
      final customers = await t.get('/customers', token: t.lia);
      expect(customers.list.map((c) => c['id']), contains(user['linkedId']));
    });
  });

  group('role-shaped views', () {
    // A job in every interesting state, so each view has something to leak.
    late String liveJob;

    setUp(() async {
      await t.saveCard(t.sarah);
      final job = await t.requestPlough(t.sarah, 'prop_maple', shovel: true);
      liveJob = job['id'] as String;
      await t.post('/jobs/$liveJob/claim', token: t.marcus);
    });

    Future<List<Object?>> bodies(
      String token,
      List<String> gets, [
      List<(String, Object?)> posts = const [],
    ]) async {
      final out = <Object?>[];
      for (final path in gets) {
        final reply = await t.get(path, token: token);
        expect(reply.status, 200, reason: '$path: ${reply.text}');
        out.add(reply.json);
      }
      for (final (path, body) in posts) {
        final reply = await t.post(path, token: token, body: body);
        expect(reply.status, lessThan(300), reason: '$path: ${reply.text}');
        out.add(reply.json);
      }
      return out;
    }

    const private = {
      'passwordHash',
      'stripeCustomerId',
      'stripePaymentMethodId',
      'pendingSetupSessionId',
      'pendingSetupAt',
      'paymentIntentId',
      'paymentMethodId',
      'attempts',
      'payoutId',
    };

    test('a customer never receives crew pay or payout details', () async {
      final seen = await bodies(
        t.sarah,
        [
          '/auth/me',
          '/settings',
          '/properties',
          '/quotes',
          '/quotes/quote_maple',
          '/jobs',
          '/jobs/$liveJob',
          '/jobs/job_maple_1',
          '/billing',
        ],
        [
          ('/billing/refresh', null),
          (
            '/properties',
            {
              'name': 'Shed',
              'address': '1 Back Lane',
              'illustration': 'garage',
            },
          ),
          ('/jobs/$liveJob/cancel', null),
          ('/jobs', {'propertyId': 'prop_maple'}),
        ],
      );
      final keys = keysIn(seen);
      expect(
        keys.intersection({
          'paidOut',
          'crewId',
          'crewShovelBonus',
          'openJobExpiryHours',
          ...private,
        }),
        isEmpty,
      );
      // `crewPay` exists only as the always-null field of the Quote shape.
      Iterable<Object?> crewPays(Object? json) sync* {
        if (json is Map<String, dynamic>) {
          if (json.containsKey('crewPay')) yield json['crewPay'];
          yield* json.values.expand(crewPays);
        } else if (json is List) {
          yield* json.expand(crewPays);
        }
      }

      expect(crewPays(seen), isNotEmpty);
      expect(crewPays(seen), everyElement(isNull));
      final job = (await t.get('/jobs/job_maple_1', token: t.sarah)).map;
      expect(job.containsKey('crewPay'), isFalse);
      expect(job['crewName'], 'Marcus Reid');
      expect(job['total'], 65);
      expect((job['payment'] as Map)['status'], 'paid');
    });

    test('crew never receive prices, totals or payment details', () async {
      final seen = await bodies(
        t.marcus,
        [
          '/auth/me',
          '/settings',
          '/jobs',
          '/jobs?scope=open',
          '/jobs/$liveJob',
          '/jobs/job_cedar_2',
          '/crew/me/pay',
        ],
        [
          ('/jobs/$liveJob/unclaim', null),
          ('/jobs/$liveJob/claim', null),
          ('/jobs/$liveJob/start', null),
          ('/jobs/$liveJob/complete', {'crewNote': 'Done.'}),
        ],
      );
      expect(
        keysIn(seen).intersection({
          'price',
          'shovelPrice',
          'total',
          'payment',
          'paymentsMode',
          'openJobExpiryHours',
          'card',
          ...private,
        }),
        isEmpty,
      );
      expect((await t.get('/settings', token: t.marcus)).map, {
        'crewShovelBonus': 10,
        'currency': 'cad',
      });
      // An open job tells the crew where, not who.
      final open = (await t.get('/jobs/job_cedar_2', token: t.marcus)).map;
      expect(open['address'], '78 Cedar Ave, Thunder Bay, ON');
      expect(open['crewPay'], 40);
      expect(
        [open['customerName'], open['customerInitials'], open['customerPhone']],
        ['', '', ''],
      );
      final mine = (await t.get('/jobs/$liveJob', token: t.marcus)).map;
      expect(mine['customerName'], 'Sarah Mitchell');
      expect(mine['customerPhone'], '(807) 555-0142');
    });

    test('nobody receives the server\'s private fields', () async {
      final seen = await bodies(
        t.lia,
        [
          '/auth/me',
          '/settings',
          '/properties',
          '/quotes',
          '/quotes/quote_birch',
          '/jobs',
          '/jobs/$liveJob',
          '/crew',
          '/crew/crew_marcus/pay',
          '/customers',
          '/customers/cust_sarah',
          '/dashboard/admin',
        ],
        [
          ('/jobs/$liveJob/unclaim', null),
          ('/crew/crew_marcus/payouts', null),
          ('/crew/crew_tasha/approve', null),
          ('/settings', {'shovelPrice': 25}),
          ('/properties/prop_maple/price', {'price': 48, 'crewPay': 26}),
          ('/quotes/quote_cabin/send', {'price': 90, 'crewPay': 50}),
        ],
      );
      expect(keysIn(seen).intersection(private), isEmpty);
      // ...although the store does hold them.
      expect(
        (t.jobDoc(liveJob)['payment'] as Map)['paymentIntentId'],
        startsWith('pi_'),
      );
      final login = await t.post(
        '/auth/login',
        body: {'email': 'lia@redefine.co', 'password': 'redefine'},
      );
      expect(keysIn(login.json).intersection(private), isEmpty);
      expect(login.text, isNot(contains('pbkdf2')));

      final admin = (await t.get('/jobs/$liveJob', token: t.lia)).map;
      expect(admin['crewPay'], 35);
      expect(admin['total'], 65);
      expect(admin['paidOut'], isFalse);
      expect(admin.containsKey('crewId'), isTrue);
      expect((admin['payment'] as Map).keys, [
        'mode',
        'status',
        'error',
        'holdExpiresAt',
        'capturedAt',
      ]);
    });
  });
}

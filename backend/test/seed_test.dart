import 'package:redefine_api/src/data/persistence.dart';
import 'package:redefine_api/src/data/seed.dart';
import 'package:redefine_api/src/model.dart';
import 'package:redefine_api/testing.dart' as testing;
import 'package:test/test.dart';

import 'support/harness.dart';

void main() {
  late TestApp t;

  setUp(() async => t = await TestApp.start(stripe: false));

  Doc doc(String collection, String id) => t.store.require(collection, id);

  test('every demo account of the contract can sign in', () async {
    const accounts = {
      'lia@redefine.co': ('user_lia', 'Lia Robinson', 'admin', null, null),
      'marcus@redefine.co': (
        'user_marcus',
        'Marcus Reid',
        'crew',
        'crew_marcus',
        'active',
      ),
      'jordan@redefine.co': (
        'user_jordan',
        'Jordan Park',
        'crew',
        'crew_jordan',
        'active',
      ),
      'tasha@redefine.co': (
        'user_tasha',
        'Tasha Rivera',
        'crew',
        'crew_tasha',
        'pending',
      ),
      'sarah.m@gmail.com': (
        'user_sarah',
        'Sarah Mitchell',
        'customer',
        'cust_sarah',
        null,
      ),
      'anna.t@gmail.com': (
        'user_anna',
        'Anna Tomlinson',
        'customer',
        'cust_anna',
        null,
      ),
      'paul.l@gmail.com': (
        'user_paul',
        'Paul Larson',
        'customer',
        'cust_paul',
        null,
      ),
    };
    for (final MapEntry(key: email, value: expected) in accounts.entries) {
      final reply = await t.post(
        '/auth/login',
        body: {'email': email, 'password': 'redefine'},
      );
      expect(reply.status, 200, reason: '$email: ${reply.text}');
      final user = reply.map['user'] as Map;
      expect((
        user['id'],
        user['name'],
        user['role'],
        user['linkedId'],
        user['crewStatus'],
      ), expected);
      expect(user['email'], email);
      expect(avatarColors, contains(user['color']));
    }
    expect(doc(Collections.users, 'user_lia')['initials'], 'LR');
    expect(doc(Collections.crew, 'crew_marcus')['phone'], '(807) 555-0111');
    expect(doc(Collections.customers, 'cust_sarah')['phone'], '(807) 555-0142');
    expect(t.store.count(Collections.users), accounts.length);
  });

  test('the demo password comes from the configuration', () async {
    t = await TestApp.start(demoPassword: 'let-it-snow');
    await t.login('lia@redefine.co', password: 'let-it-snow');
    await t.login('paul.l@gmail.com', password: 'let-it-snow');
    expectError(
      await t.post(
        '/auth/login',
        body: {'email': 'lia@redefine.co', 'password': 'redefine'},
      ),
      401,
      'invalid_credentials',
    );
    final hash = doc(Collections.users, 'user_lia')['passwordHash'] as String;
    expect(hash, startsWith(r'pbkdf2-sha256$1$'));
    expect(hash, isNot(contains('let-it-snow')));
    expect(
      await seedDemo(t.store, config: t.app.config, now: t.now),
      isFalse,
      reason: 'only an empty database is seeded',
    );
    expect(t.store.count(Collections.users), 7);
  });

  test('properties and quotes match the contract', () {
    final expected = {
      'prop_maple': (
        'cust_sarah',
        'Maple Street home',
        '412 Maple St, Thunder Bay, ON',
        'active',
        45,
        25,
        'accepted',
      ),
      'prop_cabin': (
        'cust_sarah',
        'Cabin',
        '88 Lakeside Rd, Thunder Bay, ON',
        'quoteRequested',
        null,
        null,
        'pending',
      ),
      'prop_cedar': (
        'cust_anna',
        'Cedar Ave home',
        '78 Cedar Ave, Thunder Bay, ON',
        'active',
        55,
        30,
        'accepted',
      ),
      'prop_birch': (
        'cust_paul',
        'Birch Road home',
        '21 Birch Rd, Thunder Bay, ON',
        'quoted',
        60,
        35,
        'sent',
      ),
    };
    expect(t.store.count(Collections.properties), expected.length);
    expect(t.store.count(Collections.quotes), expected.length);
    expected.forEach((id, e) {
      final p = doc(Collections.properties, id);
      final quoteId = id.replaceFirst('prop_', 'quote_');
      final q = doc(Collections.quotes, quoteId);
      expect(
        (
          p['customerId'],
          p['name'],
          p['address'],
          p['status'],
          p['price'],
          p['crewPay'],
          q['status'],
        ),
        e,
        reason: id,
      );
      expect(p['quoteId'], quoteId);
      expect([q['propertyId'], q['customerId']], [id, p['customerId']]);
      expect([q['price'], q['crewPay']], [p['price'], p['crewPay']]);
      expect(illustrations, contains(p['illustration']));
    });
    expect(
      doc(Collections.quotes, 'quote_cabin')['note'],
      contains('gravel driveway'),
    );
  });

  test('jobs, payout and settings match the contract', () {
    DateTime ago({int days = 0, int minutes = 0}) =>
        TestApp.startTime.subtract(Duration(days: days, minutes: minutes));
    String iso(DateTime time) => time.toIso8601String();

    expect(t.store.count(Collections.jobs), 5);
    // (property, crew, status, completed days ago, shovel, payment, payout)
    final done = {
      'job_maple_1': (
        'prop_maple',
        'crew_marcus',
        16,
        true,
        'paid',
        'payout_1',
      ),
      'job_maple_2': ('prop_maple', 'crew_marcus', 9, false, 'paid', null),
      'job_maple_3': ('prop_maple', 'crew_marcus', 2, false, 'paid', null),
      'job_cedar_1': ('prop_cedar', 'crew_jordan', 3, false, 'due', null),
    };
    done.forEach((id, e) {
      final j = doc(Collections.jobs, id);
      final payment = j['payment'] as Map;
      expect(
        (
          j['propertyId'],
          j['crewId'],
          DateTime.parse(j['completedAt'] as String) == ago(days: e.$3)
              ? e.$3
              : -1,
          j['shovel'],
          payment['status'],
          j['payoutId'],
        ),
        e,
        reason: id,
      );
      expect(j['status'], 'done');
      expect(payment['mode'], 'manual');
      expect(payment['paymentIntentId'], isNull);
      final times = [
        for (final f in [
          'requestedAt',
          'claimedAt',
          'startedAt',
          'completedAt',
        ])
          j[f] as String,
      ];
      expect(times, [...times]..sort(), reason: '$id happened in order');
    });
    final shovelled = doc(Collections.jobs, 'job_maple_1');
    expect(
      [
        shovelled['price'],
        shovelled['shovelPrice'],
        shovelled['total'],
        shovelled['crewPay'],
      ],
      [45, 20, 65, 35],
    );
    final plain = doc(Collections.jobs, 'job_cedar_1');
    expect(
      [plain['price'], plain['shovelPrice'], plain['total'], plain['crewPay']],
      [55, 0, 55, 30],
    );

    final open = doc(Collections.jobs, 'job_cedar_2');
    expect(
      [open['propertyId'], open['status'], open['shovel'], open['crewId']],
      ['prop_cedar', 'open', true, null],
    );
    expect(open['requestedAt'], iso(ago(minutes: 10)));
    expect([open['total'], open['crewPay']], [75, 40]);
    expect(
      [(open['payment'] as Map)['mode'], (open['payment'] as Map)['status']],
      ['manual', 'none'],
    );

    expect(doc(Collections.payouts, 'payout_1'), {
      'id': 'payout_1',
      'crewId': 'crew_marcus',
      'amount': 35,
      'jobCount': 1,
      'paidAt': iso(ago(days: 14)),
      'note': 'e-transfer',
    });
    expect(t.store.count(Collections.payouts), 1);
    expect(t.store.settings, {'id': 'main', ...defaultSettings});
    expect(defaultSettings, {
      'shovelPrice': 20,
      'crewShovelBonus': 10,
      'openJobExpiryHours': 48,
    });
  });

  test('lib/testing.dart exports what other packages need', () async {
    final persistence = testing.MemoryPersistence();
    final store = await testing.Store.open(persistence);
    const config = testing.Config(pbkdf2Iterations: 1);
    testing.ensureSettings(store);
    await testing.seedDemo(
      store,
      config: config,
      now: DateTime.utc(2026, 2),
      sampleData: true,
    );
    final gateway = testing.FakePaymentGateway();
    final handler = testing.createApp(
      testing.App(
        config: config,
        store: store,
        payments: gateway,
        logRequests: false,
        log: (_) {},
      ),
    );
    expect(handler, isA<Function>());
    expect(store.count(testing.Collections.users), 7);
    gateway.authorizeOutcomes.add(testing.PaymentOutcome.declined);
    expect(gateway.mode, 'stripe-test');
  });

  test('initials are derived from names', () {
    expect(initialsOf('Lia Robinson'), 'LR');
    expect(initialsOf('  mary  jane   watson '), 'MW');
    expect(initialsOf('Cher'), 'CH');
    expect(initialsOf('q'), 'Q');
    expect(initialsOf('Émile Zola'), 'ÉZ');
    expect(initialsOf('   '), '');
  });
}

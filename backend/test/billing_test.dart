import 'package:redefine_api/src/data/persistence.dart';
import 'package:redefine_api/src/payments/gateway.dart';
import 'package:test/test.dart';

import 'support/harness.dart';

void main() {
  late TestApp t;

  setUp(() async {
    t = await TestApp.start();
    t.gateway.autoCompleteSetup = false;
  });

  Future<String> startSetup(String token) async {
    final reply = await t.post('/billing/setup-session', token: token);
    expect(reply.status, 200, reason: reply.text);
    return (reply.map['url'] as String).split('/').last;
  }

  test('a card is saved once the hosted setup completes', () async {
    final sessionId = await startSetup(t.sarah);
    var billing = await t.post('/billing/refresh', token: t.sarah);
    expect(billing.status, 200, reason: billing.text);
    expect(billing.map['pendingSetup'], isTrue);
    expect(billing.map['card'], isNull);

    t.gateway.completeSetup(sessionId, brand: 'amex', last4: '0005');
    t.advance(const Duration(seconds: 3));
    billing = await t.post('/billing/refresh', token: t.sarah);
    expect(billing.map['pendingSetup'], isFalse);
    expect(billing.map['card'], {
      'brand': 'amex',
      'last4': '0005',
      'expMonth': 12,
      'expYear': 2030,
      'updatedAt': '2026-01-07T15:00:03.000Z',
    });
    expect(billing.map, (await t.get('/billing', token: t.sarah)).map);

    // The Stripe customer is created once and reused.
    await startSetup(t.sarah);
    expect(t.gateway.callsTo('createCustomer'), hasLength(1));
    expect(t.gateway.callsTo('createCustomer').single.args, {
      'appCustomerId': 'cust_sarah',
      'name': 'Sarah Mitchell',
      'email': 'sarah.m@gmail.com',
    });
    expect(
      t.persistence.doc(
        Collections.customers,
        'cust_sarah',
      )!['stripeCustomerId'],
      startsWith('cus_'),
    );
  });

  test('Stripe is asked at most once every two seconds per customer', () async {
    final sarahs = await startSetup(t.sarah);
    await startSetup(t.anna);
    for (var i = 0; i < 3; i++) {
      await t.post('/billing/refresh', token: t.sarah);
    }
    expect(t.gateway.callsTo('fetchSetupResult'), hasLength(1));
    await t.post('/billing/refresh', token: t.anna);
    expect(t.gateway.callsTo('fetchSetupResult'), hasLength(2));

    // The public return page shares the limit: no token, no free lookups.
    t.gateway.completeSetup(sarahs);
    for (var i = 0; i < 50; i++) {
      final page = await t.get('/billing/return?session_id=$sarahs');
      expect(page.status, 200);
      expect(page.text, isNot(contains('Card saved')));
    }
    expect(t.gateway.callsTo('fetchSetupResult'), hasLength(2));
    expect((await t.get('/billing', token: t.sarah)).map['card'], isNull);

    t.advance(const Duration(seconds: 2));
    await t.get('/billing/return?session_id=$sarahs');
    expect(t.gateway.callsTo('fetchSetupResult'), hasLength(3));
    expect((await t.get('/billing', token: t.sarah)).map['card'], isNotNull);
    // Without a pending session there is nothing to ask.
    await t.post('/billing/refresh', token: t.sarah);
    await t.post('/billing/refresh', token: t.paul);
    expect(t.gateway.callsTo('fetchSetupResult'), hasLength(3));
  });

  test(
    'asking for the card page again within ten seconds reuses the session',
    () async {
      final first = await startSetup(t.sarah);
      // Thirty taps, and thirty requests at once: still one session.
      for (var i = 0; i < 30; i++) {
        expect(await startSetup(t.sarah), first);
      }
      final replies = await Future.wait([
        for (var i = 0; i < 30; i++)
          t.post('/billing/setup-session', token: t.anna),
      ]);
      expect(replies.map((r) => r.status).toSet(), {200});
      expect(replies.map((r) => r.map['url']).toSet(), hasLength(1));
      expect(t.gateway.callsTo('createSetupSession'), hasLength(2));
      expect(t.gateway.callsTo('createCustomer'), hasLength(2));

      // Later, or once that session has done its job, a new one is opened.
      t.advance(const Duration(seconds: 10));
      final second = await startSetup(t.sarah);
      expect(second, isNot(first));
      t.gateway.completeSetup(second);
      await t.post('/billing/refresh', token: t.sarah);
      expect(await startSetup(t.sarah), isNot(second));
      expect(t.gateway.callsTo('createSetupSession'), hasLength(4));
    },
  );

  test('a failed card page request does not block the next one', () async {
    t.gateway.unavailable = true;
    final failed = await Future.wait([
      for (var i = 0; i < 3; i++)
        t.post('/billing/setup-session', token: t.sarah),
    ]);
    for (final reply in failed) {
      expectError(reply, 502, 'payment_unavailable');
    }
    t.gateway.unavailable = false;
    await startSetup(t.sarah);
    expect(
      (await t.get('/billing', token: t.sarah)).map['pendingSetup'],
      isTrue,
    );
  });

  test('the return page syncs the card and never needs a token', () async {
    final sessionId = await startSetup(t.sarah);

    final early = await t.get('/billing/return?session_id=$sessionId');
    expect(early.status, 200);
    expect(early.text, isNot(contains('Card saved')));
    expect((await t.get('/billing', token: t.sarah)).map['card'], isNull);

    t.gateway.completeSetup(sessionId);
    t.advance(const Duration(seconds: 2));
    final saved = await t.get('/billing/return?session_id=$sessionId');
    expect(saved.status, 200);
    expect(saved.headers['content-type'], 'text/html; charset=utf-8');
    expect(saved.headers['access-control-allow-origin'], '*');
    expect(
      saved.text,
      contains('Card saved. You can close this tab and return to the app.'),
    );
    expect(saved.text, contains('#0E6D55'));
    expect(saved.text, isNot(contains('<script')));
    final billing = await t.get('/billing', token: t.sarah);
    expect((billing.map['card'] as Map)['last4'], '4242');
    expect(billing.map['pendingSetup'], isFalse);
    expect(
      t.persistence.doc(Collections.customers, 'cust_sarah')!['card'],
      isNotNull,
      reason: 'saved although the request was a GET',
    );

    final cancelled = await t.get('/billing/return?cancelled=1');
    expect(cancelled.status, 200);
    expect(cancelled.text, contains('No card was saved'));
    for (final path in [
      '/billing/return',
      '/billing/return?session_id=cs_unknown',
      '/billing/return?session_id=$sessionId',
      '/billing/return?session_id=${'x' * 500}',
    ]) {
      final page = await t.get(path);
      expect(page.status, 200, reason: path);
      expect(page.text, contains('return to the app'), reason: path);
      expect(page.text, isNot(contains('Card saved')), reason: path);
    }
    expect(t.gateway.callsTo('fetchSetupResult'), hasLength(2));
  });

  test('a Stripe outage is 502 on refresh and a calm page on return', () async {
    final sessionId = await startSetup(t.sarah);
    t.gateway.unavailable = true;
    expectError(
      await t.post('/billing/refresh', token: t.sarah),
      502,
      'payment_unavailable',
    );
    final page = await t.get('/billing/return?session_id=$sessionId');
    expect(page.status, 200);
    expect(page.text, isNot(contains('Card saved')));
    expectError(
      await t.post('/billing/setup-session', token: t.anna),
      502,
      'payment_unavailable',
    );
    expect(t.logs.join('\n'), isNot(contains('sk_')));

    t.gateway.unavailable = false;
    t.gateway.completeSetup(sessionId);
    t.advance(const Duration(seconds: 2));
    final billing = await t.post('/billing/refresh', token: t.sarah);
    expect(billing.map['card'], isNotNull);
    // Anna's failed attempt left nothing half-done behind.
    final anna = await t.get('/billing', token: t.anna);
    expect([anna.map['card'], anna.map['pendingSetup']], [null, false]);
  });

  test('an abandoned setup stops being pending after a day', () async {
    await startSetup(t.sarah);
    t.advance(const Duration(hours: 23));
    expect(
      (await t.get('/billing', token: t.sarah)).map['pendingSetup'],
      isTrue,
    );
    t.advance(const Duration(hours: 2));
    expect(
      (await t.get('/billing', token: t.sarah)).map['pendingSetup'],
      isFalse,
    );
    final calls = t.gateway.callsTo('fetchSetupResult').length;
    final refreshed = await t.post('/billing/refresh', token: t.sarah);
    expect(refreshed.map['pendingSetup'], isFalse);
    expect(t.gateway.callsTo('fetchSetupResult'), hasLength(calls));
    expect(
      t.store.get(
        Collections.customers,
        'cust_sarah',
      )!['pendingSetupSessionId'],
      isNull,
    );
  });

  test(
    'a new card replaces the old one; only the latest session counts',
    () async {
      final first = await startSetup(t.sarah);
      t.gateway.completeSetup(first, last4: '1111');
      await t.post('/billing/refresh', token: t.sarah);
      final job = await t.requestPlough(t.sarah, 'prop_maple');
      final firstCard = t.gateway
          .callsTo('authorize')
          .single
          .args['paymentMethodId'];

      // The old card keeps working while a replacement is pending.
      t.advance(const Duration(minutes: 5));
      final stale = await startSetup(t.sarah);
      t.advance(const Duration(seconds: 10));
      final latest = await startSetup(t.sarah);
      var billing = await t.get('/billing', token: t.sarah);
      expect((billing.map['card'] as Map)['last4'], '1111');
      expect(billing.map['pendingSetup'], isTrue);

      t.gateway.completeSetup(stale, last4: '2222');
      billing = await t.post('/billing/refresh', token: t.sarah);
      expect((billing.map['card'] as Map)['last4'], '1111');
      expect(billing.map['pendingSetup'], isTrue);

      t.gateway.completeSetup(latest, brand: 'mastercard', last4: '3333');
      t.advance(const Duration(seconds: 2));
      billing = await t.post('/billing/refresh', token: t.sarah);
      expect((billing.map['card'] as Map)['last4'], '3333');
      expect((billing.map['card'] as Map)['brand'], 'mastercard');
      expect(billing.map['pendingSetup'], isFalse);

      // New requests are held on the new card.
      await t.post('/jobs/${job['id']}/cancel', token: t.sarah);
      await t.requestPlough(t.sarah, 'prop_maple');
      expect(
        t.gateway.callsTo('authorize').last.args['paymentMethodId'],
        isNot(firstCard),
      );
    },
  );

  test(
    'charges list what was held, charged or is owed, newest first',
    () async {
      t.gateway.autoCompleteSetup = true;
      await t.saveCard(t.sarah);
      // Seeded: three paid manual jobs. Add a captured, a failed, a released
      // and a held one.
      final captured = await t.requestPlough(t.sarah, 'prop_maple');
      await t.plough(t.marcus, captured['id'] as String);

      t.advance(const Duration(hours: 1));
      final failed = await t.requestPlough(t.sarah, 'prop_maple', shovel: true);
      t.gateway.captureOutcomes.add(PaymentOutcome.declined);
      await t.plough(t.marcus, failed['id'] as String);

      t.advance(const Duration(hours: 1));
      final released = await t.requestPlough(t.sarah, 'prop_maple');
      await t.post('/jobs/${released['id']}/cancel', token: t.sarah);

      t.advance(const Duration(hours: 1));
      final held = await t.requestPlough(t.sarah, 'prop_maple');

      final billing = await t.get('/billing', token: t.sarah);
      expect(billing.map['mode'], 'stripe');
      expect(billing.map['balanceDue'], 65);
      final charges = (billing.map['charges'] as List).cast<Map>();
      expect(
        [for (final c in charges) (c['jobId'], c['status'], c['total'])],
        [
          (held['id'], 'authorized', 45),
          (failed['id'], 'failed', 65),
          (captured['id'], 'captured', 45),
          ('job_maple_3', 'paid', 45),
          ('job_maple_2', 'paid', 45),
          ('job_maple_1', 'paid', 65),
        ],
      );
      expect(charges.first['date'], '2026-01-07T18:00:00.000Z');
      expect(charges[1]['date'], '2026-01-07T16:00:00.000Z');
      expect(charges.first['propertyName'], 'Maple Street home');
      expect(charges.map((c) => c['shovel']), [
        false,
        true,
        false,
        false,
        false,
        true,
      ]);
      // Somebody else's billing is somebody else's.
      final anna = await t.get('/billing', token: t.anna);
      expect(anna.map['balanceDue'], 55);
      expect((anna.map['charges'] as List).map((c) => (c as Map)['jobId']), [
        'job_cedar_1',
      ]);
    },
  );
}

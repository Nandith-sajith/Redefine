import 'package:test/test.dart';

import 'support/harness.dart';

void main() {
  late TestApp t;

  // No payment gateway: every job is billed by hand.
  setUp(() async => t = await TestApp.start(stripe: false));

  test('health and settings report manual payments', () async {
    expect((await t.get('/health')).map['payments'], 'manual');
    expect((await t.get('/settings', token: t.sarah)).map, {
      'shovelPrice': 20,
      'currency': 'cad',
      'paymentsMode': 'manual',
    });
    expect((await t.get('/settings', token: t.lia)).map, {
      'shovelPrice': 20,
      'crewShovelBonus': 10,
      'openJobExpiryHours': 48,
      'currency': 'cad',
      'paymentsMode': 'manual',
    });
  });

  test('request -> done -> due -> marked paid, without a card', () async {
    final job = await t.requestPlough(t.sarah, 'prop_maple', shovel: true);
    final id = job['id'] as String;
    expect(job['total'], 65);
    expect(job['payment'], {
      'mode': 'manual',
      'status': 'none',
      'error': null,
      'holdExpiresAt': null,
      'capturedAt': null,
    });
    // Nothing is owed until the work is done.
    var billing = await t.get('/billing', token: t.sarah);
    expect(billing.map['mode'], 'manual');
    expect(billing.map['card'], isNull);
    expect(billing.map['pendingSetup'], isFalse);
    expect(billing.map['balanceDue'], 0);
    expect(
      (billing.map['charges'] as List).map((c) => (c as Map)['jobId']),
      isNot(contains(id)),
    );
    expectError(
      await t.post('/jobs/$id/mark-paid', token: t.lia),
      409,
      'invalid_state',
    );

    t.advance(const Duration(hours: 1));
    final done = await t.plough(t.marcus, id);
    expect(done['status'], 'done');
    expect((done['payment'] as Map)['status'], 'due');
    expect((done['payment'] as Map)['capturedAt'], isNull);

    billing = await t.get('/billing', token: t.sarah);
    expect(billing.map['balanceDue'], 65);
    expect((billing.map['charges'] as List).first, {
      'jobId': id,
      'propertyName': 'Maple Street home',
      'date': '2026-01-07T16:00:00.000Z',
      'total': 65,
      'shovel': true,
      'status': 'due',
    });
    final dashboard = await t.get('/dashboard/admin', token: t.lia);
    final counts = dashboard.map['counts'] as Map;
    expect(counts['paymentIssues'], 2);
    expect(counts['doneToday'], 1);
    expect(counts['revenueToday'], 65);

    expectError(
      await t.post('/jobs/$id/retry-payment', token: t.lia),
      409,
      'invalid_state',
    );
    t.advance(const Duration(days: 2));
    final paid = await t.post('/jobs/$id/mark-paid', token: t.lia);
    expect(paid.status, 200, reason: paid.text);
    expect(paid.map['payment'], {
      'mode': 'manual',
      'status': 'paid',
      'error': null,
      'holdExpiresAt': null,
      'capturedAt': '2026-01-09T16:00:00.000Z',
    });
    final again = await t.post('/jobs/$id/mark-paid', token: t.lia);
    expect(again.status, 200);
    expect(again.map, paid.map);

    billing = await t.get('/billing', token: t.sarah);
    expect(billing.map['balanceDue'], 0);
    expect(((billing.map['charges'] as List).first as Map)['status'], 'paid');
    final detail = await t.get('/customers/cust_sarah', token: t.lia);
    expect(detail.map['totals'], {'billed': 220, 'outstanding': 0});
  });

  test('card setup is refused with payments_manual', () async {
    expectError(
      await t.post('/billing/setup-session', token: t.sarah),
      409,
      'payments_manual',
    );
    // Refreshing is harmless and just returns the billing page.
    final refreshed = await t.post('/billing/refresh', token: t.sarah);
    expect(refreshed.status, 200);
    expect(refreshed.map['mode'], 'manual');
    expect(refreshed.map['card'], isNull);
    // The admin cannot force a card either.
    expectError(
      await t.post(
        '/jobs',
        token: t.lia,
        body: {'propertyId': 'prop_maple', 'payment': 'card'},
      ),
      409,
      'payments_manual',
    );
    final manual = await t.requestPlough(t.lia, 'prop_maple');
    expect((manual['payment'] as Map)['mode'], 'manual');
  });

  test('cancelling a manual job leaves nothing to release', () async {
    final job = await t.requestPlough(t.sarah, 'prop_maple');
    final reply = await t.post('/jobs/${job['id']}/cancel', token: t.sarah);
    expect(reply.status, 200, reason: reply.text);
    expect(reply.map['status'], 'cancelled');
    expect(reply.map['cancelledBy'], 'customer');
    expect((reply.map['payment'] as Map)['status'], 'none');
    expect((await t.get('/billing', token: t.sarah)).map['balanceDue'], 0);
  });

  test(
    'a card job from stripe days is settled by hand once the key is gone',
    () async {
      // The same database, first with payments, then without.
      final stripe = await TestApp.start();
      await stripe.saveCard(stripe.sarah);
      final job = await stripe.requestPlough(stripe.sarah, 'prop_maple');
      final id = job['id'] as String;
      await stripe.post('/jobs/$id/claim', token: stripe.marcus);
      await stripe.post('/jobs/$id/start', token: stripe.marcus);

      final manual = await TestApp.start(
        stripe: false,
        persistence: stripe.persistence,
      );
      final done = await manual.post(
        '/jobs/$id/complete',
        token: manual.marcus,
      );
      expect(done.status, 200, reason: done.text);
      final view = (await manual.get('/jobs/$id', token: manual.lia)).map;
      expect(view['status'], 'done');
      expect((view['payment'] as Map)['status'], 'failed');
      expect(
        (view['payment'] as Map)['error'],
        contains('mark the job as paid'),
      );
      expectError(
        await manual.post('/jobs/$id/retry-payment', token: manual.lia),
        409,
        'invalid_state',
      );
      final paid = await manual.post('/jobs/$id/mark-paid', token: manual.lia);
      expect((paid.map['payment'] as Map)['status'], 'paid');
    },
  );
}

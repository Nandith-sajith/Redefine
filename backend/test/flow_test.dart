import 'package:redefine_api/src/data/persistence.dart';
import 'package:test/test.dart';

import 'support/harness.dart';

void main() {
  test('a new customer goes from signup to a paid plough and a crew payout', () async {
    final t = await TestApp.start();
    t.gateway.autoCompleteSetup = false;

    // --- signup ---------------------------------------------------------
    final signup = await t.post(
      '/auth/signup',
      body: {
        'name': 'Nora Quinn',
        'email': ' Nora.Quinn@Example.com ',
        'password': 'snowfall-1',
        'phone': '(807) 555-0199',
      },
    );
    expect(signup.status, 201, reason: signup.text);
    final nora = signup.map['token'] as String;
    final user = signup.map['user'] as Map<String, dynamic>;
    expect(user, {
      'id': startsWith('user_'),
      'name': 'Nora Quinn',
      'email': 'nora.quinn@example.com',
      'role': 'customer',
      'initials': 'NQ',
      'color': isIn(['lime', 'teal', 'paper']),
      'phone': '(807) 555-0199',
      'linkedId': startsWith('cust_'),
      'crewStatus': null,
    });
    expect((await t.get('/auth/me', token: nora)).map, user);
    expect(
      await t.login('nora.quinn@example.com', password: 'snowfall-1'),
      isNot(nora),
    );
    expect((await t.get('/settings', token: nora)).map, {
      'shovelPrice': 20,
      'currency': 'cad',
      'paymentsMode': 'stripe',
    });

    // --- property and quote ---------------------------------------------
    final added = await t.post(
      '/properties',
      token: nora,
      body: {
        'name': 'Pine Lane cottage',
        'address': '9 Pine Lane, Thunder Bay, ON',
        'illustration': 'cottage',
        'note': 'Steep driveway.',
      },
    );
    expect(added.status, 201, reason: added.text);
    final propertyId = (added.map['property'] as Map)['id'] as String;
    final quoteId = (added.map['quote'] as Map)['id'] as String;
    expect(added.map['property'], {
      'id': propertyId,
      'name': 'Pine Lane cottage',
      'address': '9 Pine Lane, Thunder Bay, ON',
      'illustration': 'cottage',
      'note': 'Steep driveway.',
      'status': 'quoteRequested',
      'price': null,
      'quoteId': quoteId,
      'createdAt': '2026-01-07T15:00:00.000Z',
      'activeJob': null,
    });
    expect(added.map['quote'], {
      'id': quoteId,
      'propertyId': propertyId,
      'customerId': user['linkedId'],
      'status': 'pending',
      'note': 'Steep driveway.',
      'price': null,
      'crewPay': null,
      'createdAt': '2026-01-07T15:00:00.000Z',
      'sentAt': null,
      'decidedAt': null,
      'customerName': 'Nora Quinn',
      'customerInitials': 'NQ',
      'customerColor': user['color'],
      'email': 'nora.quinn@example.com',
      'phone': '(807) 555-0199',
      'propertyName': 'Pine Lane cottage',
      'address': '9 Pine Lane, Thunder Bay, ON',
      'illustration': 'cottage',
    });

    // Not requestable before the quote is accepted.
    expectError(
      await t.post('/jobs', token: nora, body: {'propertyId': propertyId}),
      409,
      'invalid_state',
    );

    final dashboard = await t.get('/dashboard/admin', token: t.lia);
    expect(
      (dashboard.map['pendingQuotes'] as List).map((q) => (q as Map)['id']),
      contains(quoteId),
    );
    final pending = await t.get('/quotes?status=pending', token: t.lia);
    expect(pending.list.first['id'], quoteId, reason: 'newest first');

    t.advance(const Duration(hours: 2));
    final sent = await t.post(
      '/quotes/$quoteId/send',
      token: t.lia,
      body: {'price': 50, 'crewPay': 28},
    );
    expect(sent.status, 200, reason: sent.text);
    expect(sent.map['status'], 'sent');
    expect(sent.map['price'], 50);
    expect(sent.map['crewPay'], 28);
    expect(sent.map['sentAt'], '2026-01-07T17:00:00.000Z');

    final offered = await t.get('/quotes/$quoteId', token: nora);
    expect(offered.map['price'], 50);
    expect(offered.map['crewPay'], isNull);
    final quoted = (await t.get('/properties', token: nora)).list.single;
    expect(quoted['status'], 'quoted');
    expect(quoted['price'], 50);
    expect(quoted.containsKey('crewPay'), isFalse);

    final accepted = await t.post('/quotes/$quoteId/accept', token: nora);
    expect(accepted.status, 200, reason: accepted.text);
    expect((accepted.map['quote'] as Map)['status'], 'accepted');
    expect((accepted.map['property'] as Map)['status'], 'active');
    expect((accepted.map['property'] as Map)['price'], 50);

    // --- card -------------------------------------------------------------
    expectError(
      await t.post('/jobs', token: nora, body: {'propertyId': propertyId}),
      402,
      'card_required',
    );
    expect((await t.get('/billing', token: nora)).map, {
      'mode': 'stripe',
      'card': null,
      'pendingSetup': false,
      'balanceDue': 0,
      'charges': <Object>[],
    });

    final setup = await t.post('/billing/setup-session', token: nora);
    expect(setup.status, 200, reason: setup.text);
    expect(setup.map.keys, ['url']);
    expect(setup.map['url'], startsWith('https://checkout.fake/setup/'));
    final created = t.gateway.callsTo('createSetupSession').single.args;
    expect(created['appCustomerId'], user['linkedId']);
    expect(
      created['successUrl'],
      'https://api.test/billing/return?session_id={CHECKOUT_SESSION_ID}',
    );
    expect(created['cancelUrl'], 'https://api.test/billing/return?cancelled=1');
    expect(
      (await t.post('/billing/refresh', token: nora)).map['pendingSetup'],
      isTrue,
    );

    // A minute on the hosted page, then the browser comes back.
    final sessionId = (setup.map['url'] as String).split('/').last;
    t.advance(const Duration(minutes: 1));
    t.gateway.completeSetup(sessionId, brand: 'mastercard', last4: '4444');
    final back = await t.get('/billing/return?session_id=$sessionId');
    expect(back.status, 200);
    expect(back.headers['content-type'], startsWith('text/html'));
    expect(back.text, contains('Card saved'));
    final billing = await t.get('/billing', token: nora);
    expect(billing.map['pendingSetup'], isFalse);
    expect(billing.map['card'], {
      'brand': 'mastercard',
      'last4': '4444',
      'expMonth': 12,
      'expYear': 2030,
      'updatedAt': '2026-01-07T17:01:00.000Z',
    });

    // --- request with shovelling: a hold is placed -------------------------
    t.advance(const Duration(minutes: 29));
    final requested = await t.post(
      '/jobs',
      token: nora,
      body: {
        'propertyId': propertyId,
        'shovel': true,
        'note': 'Gate code 4411',
      },
    );
    expect(requested.status, 201, reason: requested.text);
    final jobId = requested.map['id'] as String;
    expect(requested.map, {
      'id': jobId,
      'propertyId': propertyId,
      'customerId': user['linkedId'],
      'propertyName': 'Pine Lane cottage',
      'address': '9 Pine Lane, Thunder Bay, ON',
      'illustration': 'cottage',
      'customerName': 'Nora Quinn',
      'customerInitials': 'NQ',
      'customerPhone': '(807) 555-0199',
      'shovel': true,
      'price': 50,
      'shovelPrice': 20,
      'total': 70,
      'status': 'open',
      'crewName': '',
      'crewInitials': '',
      'crewColor': '',
      'note': 'Gate code 4411',
      'crewNote': '',
      'source': 'customer',
      'requestedAt': '2026-01-07T17:30:00.000Z',
      'claimedAt': null,
      'startedAt': null,
      'completedAt': null,
      'cancelledAt': null,
      'cancelledBy': null,
      'payment': {
        'mode': 'stripe',
        'status': 'authorized',
        'error': null,
        'holdExpiresAt': '2026-01-12T11:30:00.000Z',
        'capturedAt': null,
      },
    });
    final hold = t.gateway.callsTo('authorize').single.args;
    expect(hold['jobId'], jobId);
    expect(hold['amountDollars'], 70);
    expect(t.gateway.intentForJob(jobId)!.status, 'requires_capture');
    final active = (await t.get('/properties', token: nora)).list.single;
    expect((active['activeJob'] as Map)['id'], jobId);

    // --- crew: accept, start, complete --------------------------------------
    final open = await t.get('/jobs?scope=open', token: t.marcus);
    final offer = open.list.singleWhere((j) => j['id'] == jobId);
    expect(offer['crewPay'], 38);
    expect(offer['customerName'], '');
    expect(offer['customerPhone'], '');
    expect(offer['address'], '9 Pine Lane, Thunder Bay, ON');
    for (final hidden in ['price', 'shovelPrice', 'total', 'payment']) {
      expect(offer.containsKey(hidden), isFalse, reason: hidden);
    }

    t.advance(const Duration(minutes: 5));
    final claimed = await t.post('/jobs/$jobId/claim', token: t.marcus);
    expect(claimed.status, 200, reason: claimed.text);
    expect(claimed.map['status'], 'claimed');
    expect(claimed.map['crewId'], 'crew_marcus');
    expect(claimed.map['claimedAt'], '2026-01-07T17:35:00.000Z');
    expect(claimed.map['customerName'], 'Nora Quinn');
    expect(claimed.map['customerPhone'], '(807) 555-0199');
    final assigned = await t.get('/jobs/$jobId', token: nora);
    expect(assigned.map['status'], 'claimed');
    expect(assigned.map['crewName'], 'Marcus Reid');
    expect(assigned.map['crewInitials'], 'MR');
    expect(assigned.map.containsKey('crewId'), isFalse);

    t.advance(const Duration(minutes: 20));
    final started = await t.post('/jobs/$jobId/start', token: t.marcus);
    expect(started.map['status'], 'inProgress');
    expect(started.map['startedAt'], '2026-01-07T17:55:00.000Z');

    t.advance(const Duration(minutes: 40));
    final completed = await t.post(
      '/jobs/$jobId/complete',
      token: t.marcus,
      body: {'crewNote': 'Salted the steps.'},
    );
    expect(completed.status, 200, reason: completed.text);
    expect(completed.map['status'], 'done');
    expect(completed.map['completedAt'], '2026-01-07T18:35:00.000Z');
    expect(completed.map['crewNote'], 'Salted the steps.');
    expect(completed.map['paidOut'], isFalse);
    expect(t.gateway.callsTo('capture').single.args['jobId'], jobId);
    expect(t.gateway.intentForJob(jobId)!.status, 'succeeded');

    // --- customer sees the finished job and the charge ----------------------
    final done = await t.get('/jobs/$jobId', token: nora);
    expect(done.map['status'], 'done');
    expect(done.map['crewNote'], 'Salted the steps.');
    expect(done.map['payment'], {
      'mode': 'stripe',
      'status': 'captured',
      'error': null,
      'holdExpiresAt': '2026-01-12T11:30:00.000Z',
      'capturedAt': '2026-01-07T18:35:00.000Z',
    });
    final after = await t.get('/billing', token: nora);
    expect(after.map['balanceDue'], 0);
    expect(after.map['charges'], [
      {
        'jobId': jobId,
        'propertyName': 'Pine Lane cottage',
        'date': '2026-01-07T18:35:00.000Z',
        'total': 70,
        'shovel': true,
        'status': 'captured',
      },
    ]);
    expect(
      (await t.get('/properties', token: nora)).list.single['activeJob'],
      isNull,
    );
    expect(
      (await t.get('/jobs?status=done', token: nora)).list.single['id'],
      jobId,
    );

    // --- crew pay and payout --------------------------------------------------
    final pay = await t.get('/crew/me/pay', token: t.marcus);
    expect(pay.status, 200, reason: pay.text);
    expect(pay.map['crewId'], 'crew_marcus');
    expect(pay.map['earnedToday'], 38);
    expect(pay.map['jobsToday'], 1);
    // Plus the two seeded jobs that were never paid out (25 each).
    expect(pay.map['unpaidTotal'], 88);
    final unpaid = (pay.map['unpaidJobs'] as List).cast<Map<String, dynamic>>();
    expect(unpaid.map((j) => j['id']), [jobId, 'job_maple_3', 'job_maple_2']);
    expect(unpaid.first['crewPay'], 38);
    expect(unpaid.first.containsKey('total'), isFalse);

    t.advance(const Duration(hours: 1));
    final payout = await t.post(
      '/crew/crew_marcus/payouts',
      token: t.lia,
      body: {'note': 'e-transfer #88'},
    );
    expect(payout.status, 200, reason: payout.text);
    expect(payout.map['payout'], {
      'id': startsWith('payout_'),
      'crewId': 'crew_marcus',
      'amount': 88,
      'jobCount': 3,
      'paidAt': '2026-01-07T19:35:00.000Z',
      'note': 'e-transfer #88',
    });
    final paid = payout.map['pay'] as Map<String, dynamic>;
    expect(paid['unpaidTotal'], 0);
    expect(paid['unpaidJobs'], isEmpty);
    expect(paid['earnedAllTime'], 123);
    expect((paid['payouts'] as List).map((p) => (p as Map)['amount']), [
      88,
      35,
    ]);
    expectError(
      await t.post('/crew/crew_marcus/payouts', token: t.lia),
      409,
      'nothing_to_pay',
    );
    final adminJob = await t.get('/jobs/$jobId', token: t.lia);
    expect(adminJob.map['paidOut'], isTrue);
    expect(adminJob.map['crewPay'], 38);
    expect(adminJob.map['total'], 70);

    // --- everything above reached the database --------------------------------
    expect(t.store.isDirty, isFalse);
    final stored = t.persistence.doc(Collections.jobs, jobId)!;
    expect(stored['status'], 'done');
    expect(stored['payoutId'], (payout.map['payout'] as Map)['id']);
    expect((stored['payment'] as Map)['paymentIntentId'], startsWith('pi_'));

    // --- logout -----------------------------------------------------------------
    expect((await t.post('/auth/logout', token: nora)).map, {'ok': true});
    expectError(await t.get('/auth/me', token: nora), 401, 'unauthorized');
  });
}

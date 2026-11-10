import 'package:redefine_api/src/data/persistence.dart';
import 'package:redefine_api/src/payments/gateway.dart';
import 'package:test/test.dart';

import 'support/harness.dart';

void main() {
  late TestApp t;

  // Stripe mode; Sarah has a saved card and one active property
  // (prop_maple: price 45, crew pay 25).
  setUp(() async {
    t = await TestApp.start();
    await t.saveCard(t.sarah);
  });

  Future<String> requested({bool shovel = false}) async =>
      (await t.requestPlough(t.sarah, 'prop_maple', shovel: shovel))['id']
          as String;

  Map<String, dynamic> payment(String jobId) =>
      t.jobDoc(jobId)['payment'] as Map<String, dynamic>;

  Future<Map<String, dynamic>> adminView(String jobId) async =>
      (await t.get('/jobs/$jobId', token: t.lia)).map;

  group('requesting a plough', () {
    test('a refused or unreachable card creates no job', () async {
      final before = t.store.count(Collections.jobs);
      for (final (outcome, status, code) in [
        (PaymentOutcome.declined, 402, 'card_declined'),
        (PaymentOutcome.authRequired, 402, 'card_auth_required'),
        (PaymentOutcome.unavailable, 502, 'payment_unavailable'),
      ]) {
        t.gateway.authorizeOutcomes.add(outcome);
        final reply = await t.post(
          '/jobs',
          token: t.sarah,
          body: {'propertyId': 'prop_maple'},
        );
        expectError(reply, status, code);
        if (code == 'card_declined') {
          expect(reply.map['error'], 'Your card was declined.');
        }
      }
      expect(t.gateway.callsTo('authorize'), hasLength(3));
      expect(t.gateway.intents, isEmpty);
      expect(t.store.count(Collections.jobs), before);
      expect(t.persistence.docs(Collections.jobs), hasLength(before));
      expect(
        (await t.get('/properties', token: t.sarah)).list.first['activeJob'],
        isNull,
      );
      // Nothing is left in the way of the next request.
      await requested();
    });

    test('a hold whose answer got lost is asked for again, not lost', () async {
      t.gateway.lostReplies.add(true);
      final job = await t.requestPlough(t.sarah, 'prop_maple');
      // Asked twice under one idempotency key: one hold, and the job has it.
      final calls = t.gateway.callsTo('authorize');
      expect(calls, hasLength(2));
      expect(calls[1].args, calls[0].args);
      final hold = t.gateway.intents.single;
      expect(hold.status, 'requires_capture');
      expect(payment(job['id'] as String)['paymentIntentId'], hold.id);
    });

    test('an unreachable payment service is asked twice, then 502', () async {
      final before = t.store.count(Collections.jobs);
      t.gateway.unavailable = true;
      expectError(
        await t.post(
          '/jobs',
          token: t.sarah,
          body: {'propertyId': 'prop_maple'},
        ),
        502,
        'payment_unavailable',
      );
      expect(t.gateway.callsTo('authorize'), hasLength(2));
      expect(t.store.count(Collections.jobs), before);
      final jobId = t.gateway.callsTo('authorize').first.args['jobId'];
      expect(t.logs.join('\n'), contains('metadata jobId $jobId may exist'));
      t.gateway.unavailable = false;
      await requested();
    });

    test('a takeover while the new job is saved releases its hold', () async {
      final before = t.store.count(Collections.jobs);
      t.persistence.loseLeaseOnNextCommit();
      expectError(
        await t.post(
          '/jobs',
          token: t.sarah,
          body: {'propertyId': 'prop_maple'},
        ),
        503,
        'storage_unavailable',
      );
      // The reload dropped the job, so nothing may stay held for it.
      expect(t.store.count(Collections.jobs), before);
      expect(t.gateway.intents.single.status, 'canceled');
      expect(t.gateway.callsTo('cancel'), hasLength(1));

      // The customer's retry gets the only hold there is.
      final id = await requested();
      expect(
        t.gateway.intents.where((i) => i.status == 'requires_capture').single,
        t.gateway.intentForJob(id),
      );
    });

    test('a save that merely failed keeps the job and its hold', () async {
      t.persistence.failNextCommits(1);
      expectError(
        await t.post(
          '/jobs',
          token: t.sarah,
          body: {'propertyId': 'prop_maple'},
        ),
        503,
        'storage_unavailable',
      );
      final job = t.store
          .where(
            Collections.jobs,
            (j) => j['status'] == 'open' && j['propertyId'] == 'prop_maple',
          )
          .single;
      expect(
        t.gateway.intentForJob(job['id'] as String)!.status,
        'requires_capture',
      );
      expect(t.gateway.callsTo('cancel'), isEmpty);
      // The retry finds it instead of holding the card a second time.
      final again = await t.post(
        '/jobs',
        token: t.sarah,
        body: {'propertyId': 'prop_maple'},
      );
      expectError(again, 409, 'job_active');
      expect(again.map['jobId'], job['id']);
      expect(
        t.persistence.doc(Collections.jobs, job['id'] as String),
        isNotNull,
      );
    });

    test('a property has at most one unfinished job', () async {
      final first = await requested();
      final again = await t.post(
        '/jobs',
        token: t.sarah,
        body: {'propertyId': 'prop_maple', 'shovel': true},
      );
      expectError(again, 409, 'job_active');
      expect(again.map['jobId'], first);
      expectError(
        await t.post(
          '/jobs',
          token: t.lia,
          body: {'propertyId': 'prop_maple', 'payment': 'manual'},
        ),
        409,
        'job_active',
      );
      expect(t.gateway.callsTo('authorize'), hasLength(1));

      await t.post('/jobs/$first/claim', token: t.marcus);
      expectError(
        await t.post(
          '/jobs',
          token: t.sarah,
          body: {'propertyId': 'prop_maple'},
        ),
        409,
        'job_active',
      );
      await t.post('/jobs/$first/start', token: t.marcus);
      await t.post('/jobs/$first/complete', token: t.marcus);
      expect(await requested(), isNot(first));
    });

    test(
      'two simultaneous requests place one hold and create one job',
      () async {
        t.gateway.latency = const Duration(milliseconds: 20);
        final replies = await Future.wait([
          for (var i = 0; i < 2; i++)
            t.post('/jobs', token: t.sarah, body: {'propertyId': 'prop_maple'}),
        ]);
        expect(replies.map((r) => r.status).toList()..sort(), [201, 409]);
        expectError(
          replies.firstWhere((r) => r.status == 409),
          409,
          'invalid_state',
        );
        expect(t.gateway.callsTo('authorize'), hasLength(1));
        expect(
          (await t.get('/jobs?status=open', token: t.sarah)).list,
          hasLength(1),
        );
      },
    );

    test('a re-price while the hold is placed releases it again', () async {
      t.gateway.latency = const Duration(milliseconds: 300);
      final pending = t.post(
        '/jobs',
        token: t.sarah,
        body: {'propertyId': 'prop_maple'},
      );
      await until(() => t.gateway.callsTo('authorize').isNotEmpty);
      t.gateway.latency = Duration.zero;
      final repriced = await t.post(
        '/properties/prop_maple/price',
        token: t.lia,
        body: {'price': 60, 'crewPay': 30},
      );
      expect(repriced.status, 200, reason: repriced.text);

      expectError(await pending, 409, 'invalid_state');
      expect(t.gateway.intents.single.status, 'canceled');
      expect((await t.get('/jobs?status=open', token: t.sarah)).list, isEmpty);
      // The next request is held at the new price.
      final job = await t.requestPlough(t.sarah, 'prop_maple');
      expect(job['total'], 60);
      expect(t.gateway.callsTo('authorize').last.args['amountDollars'], 60);
    });

    test('a job keeps the prices it was requested at', () async {
      final id = await requested(shovel: true);
      await t.post(
        '/properties/prop_maple/price',
        token: t.lia,
        body: {'price': 80, 'crewPay': 50},
      );
      await t.post(
        '/settings',
        token: t.lia,
        body: {'shovelPrice': 30, 'crewShovelBonus': 15},
      );
      final job = await adminView(id);
      expect(
        [job['price'], job['shovelPrice'], job['total'], job['crewPay']],
        [45, 20, 65, 35],
      );
      await t.post('/jobs/$id/cancel', token: t.sarah);

      final next = await adminView(await requested(shovel: true));
      expect(
        [next['price'], next['shovelPrice'], next['total'], next['crewPay']],
        [80, 30, 110, 65],
      );
    });

    test('the admin can request for a customer, by card or manually', () async {
      // Sarah has a card: the default is a card hold.
      final byCard = await t.requestPlough(t.lia, 'prop_maple');
      expect(byCard['source'], 'admin');
      expect((byCard['payment'] as Map)['mode'], 'stripe');
      expect((byCard['payment'] as Map)['status'], 'authorized');
      await t.post('/jobs/${byCard['id']}/cancel', token: t.lia);

      final manual = await t.requestPlough(
        t.lia,
        'prop_maple',
        payment: 'manual',
      );
      expect(manual['payment'], {
        'mode': 'manual',
        'status': 'none',
        'error': null,
        'holdExpiresAt': null,
        'capturedAt': null,
      });
      expect(t.gateway.callsTo('authorize'), hasLength(1));

      // Anna has no card: manual by default, and a card cannot be forced.
      await t.post('/jobs/job_cedar_2/cancel', token: t.lia);
      expectError(
        await t.post(
          '/jobs',
          token: t.lia,
          body: {'propertyId': 'prop_cedar', 'payment': 'card'},
        ),
        402,
        'card_required',
      );
      final fallback = await t.requestPlough(t.lia, 'prop_cedar');
      expect((fallback['payment'] as Map)['mode'], 'manual');
      expect(fallback['customerName'], 'Anna Tomlinson');
      expect(fallback['source'], 'admin');

      // A customer cannot choose: the `payment` field is ignored for them.
      await t.post('/jobs/${manual['id']}/cancel', token: t.lia);
      final own = await t.requestPlough(
        t.sarah,
        'prop_maple',
        payment: 'manual',
      );
      expect(own['source'], 'customer');
      expect((own['payment'] as Map)['mode'], 'stripe');
    });
  });

  group('claiming', () {
    test('the second crew member loses with already_claimed', () async {
      final id = await requested();
      final first = await t.post('/jobs/$id/claim', token: t.marcus);
      expect(first.status, 200);
      expectError(
        await t.post('/jobs/$id/claim', token: t.jordan),
        409,
        'already_claimed',
      );
      await t.post('/jobs/$id/start', token: t.marcus);
      expectError(
        await t.post('/jobs/$id/claim', token: t.jordan),
        409,
        'already_claimed',
      );
      await t.post('/jobs/$id/complete', token: t.marcus);
      expectError(
        await t.post('/jobs/$id/claim', token: t.jordan),
        409,
        'already_claimed',
      );
      expect(t.jobDoc(id)['crewId'], 'crew_marcus');
    });

    test('of two simultaneous claims exactly one wins', () async {
      for (var round = 0; round < 5; round++) {
        final id = await requested();
        final replies = await Future.wait([
          t.post('/jobs/$id/claim', token: t.marcus),
          t.post('/jobs/$id/claim', token: t.jordan),
        ]);
        expect(replies.map((r) => r.status).toList()..sort(), [200, 409]);
        final winner = replies.firstWhere((r) => r.status == 200);
        expectError(
          replies.firstWhere((r) => r.status == 409),
          409,
          'already_claimed',
        );
        expect(t.jobDoc(id)['crewId'], winner.map['crewId']);
        expect(
          t.persistence.doc(Collections.jobs, id)!['crewId'],
          winner.map['crewId'],
        );
        await t.post('/jobs/$id/cancel', token: t.sarah);
      }
    });

    test('claiming again is a no-op for the owner', () async {
      final id = await requested();
      final first = await t.post('/jobs/$id/claim', token: t.marcus);
      t.advance(const Duration(minutes: 3));
      final second = await t.post('/jobs/$id/claim', token: t.marcus);
      expect(second.status, 200);
      expect(second.map, first.map);
      await t.post('/jobs/$id/start', token: t.marcus);
      final third = await t.post('/jobs/$id/claim', token: t.marcus);
      expect(third.status, 200);
      expect(third.map['status'], 'inProgress');
    });

    test('a cancelled job cannot be claimed', () async {
      final id = await requested();
      await t.post('/jobs/$id/cancel', token: t.sarah);
      expectError(
        await t.post('/jobs/$id/claim', token: t.marcus),
        409,
        'invalid_state',
      );
      // Not even by the crew member who had it when it was cancelled.
      final other = await requested();
      await t.post('/jobs/$other/claim', token: t.marcus);
      await t.post('/jobs/$other/cancel', token: t.sarah);
      expectError(
        await t.post('/jobs/$other/claim', token: t.marcus),
        409,
        'invalid_state',
      );
    });
  });

  group('unclaiming', () {
    test('puts the job back on the open list for someone else', () async {
      final id = await requested();
      await t.post('/jobs/$id/claim', token: t.marcus);
      final released = await t.post('/jobs/$id/unclaim', token: t.marcus);
      expect(released.status, 200, reason: released.text);
      expect(released.map['status'], 'open');
      expect(released.map['crewId'], isNull);
      expect(released.map['claimedAt'], isNull);
      expect(released.map['crewName'], '');
      expect(released.map['customerName'], '');
      expect(payment(id)['status'], 'authorized');

      final taken = await t.post('/jobs/$id/claim', token: t.jordan);
      expect(taken.map['crewId'], 'crew_jordan');
      expect(
        (await t.get('/jobs', token: t.marcus)).list.map((j) => j['id']),
        isNot(contains(id)),
      );
    });

    test('is only possible while claimed', () async {
      final id = await requested();
      expectError(
        await t.post('/jobs/$id/unclaim', token: t.marcus),
        409,
        'invalid_state',
      );
      expectError(
        await t.post('/jobs/$id/unclaim', token: t.lia),
        409,
        'invalid_state',
      );
      await t.post('/jobs/$id/claim', token: t.marcus);
      await t.post('/jobs/$id/start', token: t.marcus);
      expectError(
        await t.post('/jobs/$id/unclaim', token: t.marcus),
        409,
        'invalid_state',
      );
      expect(t.jobDoc(id)['status'], 'inProgress');
    });

    test('the admin can take a job away from a crew member', () async {
      final id = await requested();
      await t.post('/jobs/$id/claim', token: t.marcus);
      final reply = await t.post('/jobs/$id/unclaim', token: t.lia);
      expect(reply.map['status'], 'open');
      expect(reply.map['crewId'], isNull);
      expectError(
        await t.post('/jobs/$id/start', token: t.marcus),
        409,
        'invalid_state',
      );
    });
  });

  group('starting and completing', () {
    test('follow claimed -> inProgress -> done and repeat safely', () async {
      final id = await requested();
      expectError(
        await t.post('/jobs/$id/start', token: t.marcus),
        409,
        'invalid_state',
      );
      expectError(
        await t.post('/jobs/$id/complete', token: t.marcus),
        409,
        'invalid_state',
      );
      await t.post('/jobs/$id/claim', token: t.marcus);
      expectError(
        await t.post('/jobs/$id/complete', token: t.marcus),
        409,
        'invalid_state',
      );

      final started = await t.post('/jobs/$id/start', token: t.marcus);
      t.advance(const Duration(minutes: 30));
      final startedAgain = await t.post('/jobs/$id/start', token: t.marcus);
      expect(startedAgain.status, 200);
      expect(startedAgain.map, started.map);

      final done = await t.post(
        '/jobs/$id/complete',
        token: t.marcus,
        body: {'crewNote': 'All clear.'},
      );
      t.advance(const Duration(minutes: 30));
      final doneAgain = await t.post(
        '/jobs/$id/complete',
        token: t.marcus,
        body: {'crewNote': 'A different note.'},
      );
      expect(doneAgain.status, 200);
      expect(doneAgain.map, done.map);
      expect(doneAgain.map['crewNote'], 'All clear.');
      expect(t.gateway.callsTo('capture'), hasLength(1));
      expect((await t.post('/jobs/$id/complete', token: t.lia)).status, 200);
      expect(t.gateway.callsTo('capture'), hasLength(1));

      expectError(
        await t.post('/jobs/$id/start', token: t.marcus),
        409,
        'invalid_state',
      );
    });

    test('the admin may complete a claimed job but not an open one', () async {
      final id = await requested();
      expectError(
        await t.post('/jobs/$id/complete', token: t.lia),
        409,
        'invalid_state',
      );
      await t.post('/jobs/$id/claim', token: t.jordan);
      final done = await t.post(
        '/jobs/$id/complete',
        token: t.lia,
        body: {'crewNote': 'Closed by the office.'},
      );
      expect(done.status, 200, reason: done.text);
      expect(done.map['status'], 'done');
      expect(done.map['startedAt'], isNull);
      expect(done.map['crewId'], 'crew_jordan');
      expect((done.map['payment'] as Map)['status'], 'captured');
      final pay = await t.get('/crew/crew_jordan/pay', token: t.lia);
      expect(
        (pay.map['unpaidJobs'] as List).map((j) => (j as Map)['id']),
        contains(id),
      );
    });

    test('the job is saved as done before the card is captured', () async {
      final id = await requested();
      await t.post('/jobs/$id/claim', token: t.marcus);
      await t.post('/jobs/$id/start', token: t.marcus);

      t.gateway.latency = const Duration(milliseconds: 100);
      final pending = t.post('/jobs/$id/complete', token: t.marcus);
      await until(() => t.gateway.callsTo('capture').isNotEmpty);
      final saved = t.persistence.doc(Collections.jobs, id)!;
      expect(saved['status'], 'done');
      expect((saved['payment'] as Map)['status'], 'authorized');
      expect(t.gateway.intentForJob(id)!.status, 'requires_capture');

      expect((await pending).status, 200);
      expect(
        (t.persistence.doc(Collections.jobs, id)!['payment'] as Map)['status'],
        'captured',
      );
    });

    test(
      'a failed save stops the capture; repeating complete finishes it',
      () async {
        final id = await requested();
        await t.post('/jobs/$id/claim', token: t.marcus);
        await t.post('/jobs/$id/start', token: t.marcus);

        t.persistence.failNextCommits(1);
        expectError(
          await t.post('/jobs/$id/complete', token: t.marcus),
          503,
          'storage_unavailable',
        );
        expect(t.gateway.callsTo('capture'), isEmpty);
        expect(t.jobDoc(id)['status'], 'done');

        final retried = await t.post('/jobs/$id/complete', token: t.marcus);
        expect(retried.status, 200, reason: retried.text);
        expect(t.gateway.callsTo('capture'), hasLength(1));
        expect(payment(id)['status'], 'captured');
        expect(t.persistence.doc(Collections.jobs, id)!['status'], 'done');
      },
    );
  });

  group('cancelling', () {
    test(
      'a customer cancel releases the hold and frees the property',
      () async {
        final id = await requested();
        t.advance(const Duration(minutes: 4));
        final reply = await t.post('/jobs/$id/cancel', token: t.sarah);
        expect(reply.status, 200, reason: reply.text);
        expect(reply.map['status'], 'cancelled');
        expect(reply.map['cancelledBy'], 'customer');
        expect(reply.map['cancelledAt'], '2026-01-07T15:04:00.000Z');
        expect((reply.map['payment'] as Map)['status'], 'released');
        expect(t.gateway.intentForJob(id)!.status, 'canceled');

        final again = await t.post('/jobs/$id/cancel', token: t.sarah);
        expect(again.status, 200);
        expect(again.map, reply.map);
        expect((await t.post('/jobs/$id/cancel', token: t.lia)).status, 200);
        expect(t.gateway.callsTo('cancel'), hasLength(1));

        final billing = await t.get('/billing', token: t.sarah);
        expect(
          (billing.map['charges'] as List).map((c) => (c as Map)['jobId']),
          isNot(contains(id)),
        );
        await requested();
      },
    );

    test('the job is saved as cancelled before the hold is released', () async {
      final id = await requested();
      t.gateway.latency = const Duration(milliseconds: 100);
      final pending = t.post('/jobs/$id/cancel', token: t.sarah);
      await until(() => t.gateway.callsTo('cancel').isNotEmpty);
      final saved = t.persistence.doc(Collections.jobs, id)!;
      expect(saved['status'], 'cancelled');
      expect((saved['payment'] as Map)['status'], 'authorized');
      expect((await pending).status, 200);
    });

    test(
      'a claimed job can be cancelled and stays in the crew\'s history',
      () async {
        final id = await requested();
        await t.post('/jobs/$id/claim', token: t.marcus);
        final reply = await t.post('/jobs/$id/cancel', token: t.sarah);
        expect(reply.map['status'], 'cancelled');

        final mine = await t.get('/jobs', token: t.marcus);
        expect(mine.list.first['id'], id);
        expect(mine.list.first['status'], 'cancelled');
        for (final step in ['start', 'complete', 'unclaim']) {
          expectError(
            await t.post('/jobs/$id/$step', token: t.marcus),
            409,
            'invalid_state',
          );
        }
      },
    );

    test(
      'a customer cannot cancel once work has started; the admin can',
      () async {
        final id = await requested();
        await t.post('/jobs/$id/claim', token: t.marcus);
        await t.post('/jobs/$id/start', token: t.marcus);
        expectError(
          await t.post('/jobs/$id/cancel', token: t.sarah),
          409,
          'job_started',
        );
        expect(t.jobDoc(id)['status'], 'inProgress');
        expect(t.gateway.callsTo('cancel'), isEmpty);

        final reply = await t.post('/jobs/$id/cancel', token: t.lia);
        expect(reply.status, 200);
        expect(reply.map['status'], 'cancelled');
        expect(reply.map['cancelledBy'], 'admin');
        expect((reply.map['payment'] as Map)['status'], 'released');
        expectError(
          await t.post('/jobs/$id/complete', token: t.marcus),
          409,
          'invalid_state',
        );
      },
    );

    test('a completed job cannot be cancelled', () async {
      final id = await requested();
      await t.plough(t.marcus, id);
      expectError(
        await t.post('/jobs/$id/cancel', token: t.sarah),
        409,
        'invalid_state',
      );
      expectError(
        await t.post('/jobs/$id/cancel', token: t.lia),
        409,
        'invalid_state',
      );
      expect(payment(id)['status'], 'captured');
    });

    test('when the hold cannot be released yet the sweep retries', () async {
      final id = await requested();
      t.gateway.unavailable = true;
      final reply = await t.post('/jobs/$id/cancel', token: t.sarah);
      expect(reply.status, 200, reason: reply.text);
      expect(reply.map['status'], 'cancelled');
      expect((reply.map['payment'] as Map)['status'], 'authorized');
      expect((reply.map['payment'] as Map)['error'], contains('retried'));
      // The property is free although the old hold is still there.
      t.gateway.unavailable = false;
      await requested();

      t.advance(const Duration(minutes: 11));
      await t.get('/health');
      await until(() => payment(id)['status'] == 'released');
      expect(payment(id)['error'], isNull);
      expect(t.gateway.intentForJob(id)!.status, 'canceled');
      await until(
        () =>
            (t.persistence.doc(Collections.jobs, id)!['payment']
                as Map)['status'] ==
            'released',
      );
    });
  });

  group('payment problems after completion', () {
    Future<String> inProgress({bool shovel = false}) async {
      final id = await requested(shovel: shovel);
      await t.post('/jobs/$id/claim', token: t.marcus);
      await t.post('/jobs/$id/start', token: t.marcus);
      return id;
    }

    test(
      'a declined capture leaves the job done and the payment failed',
      () async {
        final id = await inProgress(shovel: true);
        t.gateway.captureOutcomes.add(PaymentOutcome.declined);
        final done = await t.post('/jobs/$id/complete', token: t.marcus);
        expect(done.status, 200, reason: done.text);
        expect(done.map['status'], 'done');

        final job = await adminView(id);
        expect(job['payment'], {
          'mode': 'stripe',
          'status': 'failed',
          'error': 'Your card was declined.',
          'holdExpiresAt': isNotNull,
          'capturedAt': null,
        });
        // The crew member earned their pay regardless.
        final pay = await t.get('/crew/me/pay', token: t.marcus);
        expect(pay.map['earnedToday'], 35);
        // The admin and the customer both see what is owed.
        final dashboard = await t.get('/dashboard/admin', token: t.lia);
        expect(
          (dashboard.map['paymentIssues'] as List).map((j) => (j as Map)['id']),
          [id, 'job_cedar_1'],
        );
        expect((dashboard.map['counts'] as Map)['paymentIssues'], 2);
        final billing = await t.get('/billing', token: t.sarah);
        expect(billing.map['balanceDue'], 65);
        expect((billing.map['charges'] as List).first, {
          'jobId': id,
          'propertyName': 'Maple Street home',
          'date': isNotNull,
          'total': 65,
          'shovel': true,
          'status': 'failed',
        });
        final detail = await t.get('/customers/cust_sarah', token: t.lia);
        expect(detail.map['totals'], {'billed': 155, 'outstanding': 65});

        // Retrying uses a fresh idempotency attempt and succeeds.
        t.advance(const Duration(hours: 3));
        final retried = await t.post('/jobs/$id/retry-payment', token: t.lia);
        expect(retried.status, 200, reason: retried.text);
        expect((retried.map['payment'] as Map)['status'], 'captured');
        expect((retried.map['payment'] as Map)['error'], isNull);
        expect(
          (retried.map['payment'] as Map)['capturedAt'],
          '2026-01-07T18:00:00.000Z',
        );
        expect(t.gateway.callsTo('capture').map((c) => c.args['attempt']), [
          0,
          1,
        ]);
        expect((await t.get('/billing', token: t.sarah)).map['balanceDue'], 0);
        expectError(
          await t.post('/jobs/$id/retry-payment', token: t.lia),
          409,
          'invalid_state',
        );
      },
    );

    test('a retry can fail again', () async {
      final id = await inProgress();
      t.gateway.captureOutcomes.addAll([
        PaymentOutcome.declined,
        PaymentOutcome.authRequired,
      ]);
      await t.post('/jobs/$id/complete', token: t.marcus);
      final retried = await t.post('/jobs/$id/retry-payment', token: t.lia);
      expect(retried.status, 200);
      expect((retried.map['payment'] as Map)['status'], 'failed');
      expect(
        (retried.map['payment'] as Map)['error'],
        contains('extra authentication'),
      );
    });

    test('an outage during capture can be settled by hand instead', () async {
      final id = await inProgress();
      t.gateway.unavailable = true;
      final done = await t.post('/jobs/$id/complete', token: t.marcus);
      expect(done.status, 200);
      t.gateway.unavailable = false;
      final failed = await adminView(id);
      expect((failed['payment'] as Map)['status'], 'failed');
      expect(
        (failed['payment'] as Map)['error'],
        'The payment service was unavailable. Retry the payment.',
      );
      expect(t.logs.join('\n'), contains('charging job $id failed'));

      t.advance(const Duration(days: 1));
      final paid = await t.post('/jobs/$id/mark-paid', token: t.lia);
      expect(paid.status, 200, reason: paid.text);
      expect(paid.map['payment'], {
        'mode': 'stripe',
        'status': 'paid',
        'error': null,
        'holdExpiresAt': isNotNull,
        'capturedAt': '2026-01-08T15:00:00.000Z',
      });
      // Paid in cash, so the card is let go.
      expect(t.gateway.intentForJob(id)!.status, 'canceled');
      final again = await t.post('/jobs/$id/mark-paid', token: t.lia);
      expect(again.status, 200);
      expect(again.map, paid.map);
      expect(t.gateway.callsTo('cancel'), hasLength(1));
      expectError(
        await t.post('/jobs/$id/retry-payment', token: t.lia),
        409,
        'invalid_state',
      );
    });

    test('an expired hold is replaced by a fresh charge', () async {
      final id = await inProgress();
      final hold = t.gateway.intentForJob(id)!;
      t.gateway.expireHold(hold.id);
      await t.post('/jobs/$id/complete', token: t.marcus);
      expect(payment(id)['status'], 'captured');
      final charge = t.gateway.intentForJob(id)!;
      expect(charge.id, isNot(hold.id));
      expect(charge.status, 'succeeded');
      expect(charge.amountDollars, 45);
      expect(payment(id)['paymentIntentId'], charge.id);
    });

    test('a fresh charge whose answer got lost is not made twice', () async {
      final id = await inProgress();
      final hold = t.gateway.intentForJob(id)!;
      t.gateway.expireHold(hold.id);
      // The hold has expired, so completing charges afresh. The charge goes
      // through, but its answer never arrives.
      t.gateway.lostReplies.add(true);
      await t.post('/jobs/$id/complete', token: t.marcus);
      expect(payment(id)['status'], 'failed');
      expect(
        payment(id)['error'],
        'The payment service was unavailable. Retry the payment.',
      );
      expect(payment(id)['paymentIntentId'], hold.id);
      final charge = t.gateway.intentForJob(id)!;
      expect(charge.status, 'succeeded');

      // The admin does what the message says. The retry repeats the same
      // attempt, so the payment service answers with the charge it made.
      final retried = await t.post('/jobs/$id/retry-payment', token: t.lia);
      expect((retried.map['payment'] as Map)['status'], 'captured');
      expect(t.gateway.callsTo('capture').map((c) => c.args['attempt']), [
        0,
        0,
      ]);
      expect(t.gateway.intents.where((i) => i.status == 'succeeded'), [charge]);
      expect(payment(id)['paymentIntentId'], charge.id);
    });

    test('a lost answer from the newer card is not charged twice', () async {
      final id = await inProgress();
      await t.saveCard(t.sarah);
      t.gateway.captureOutcomes.add(PaymentOutcome.declined);
      // The held card is refused; the charge of the newer one goes through
      // without an answer.
      t.gateway.lostReplies.addAll([false, true]);
      await t.post('/jobs/$id/complete', token: t.marcus);
      expect(payment(id)['status'], 'failed');
      final charge = t.gateway.intentForJob(id)!;
      expect(charge.status, 'succeeded');

      final retried = await t.post('/jobs/$id/retry-payment', token: t.lia);
      expect((retried.map['payment'] as Map)['status'], 'captured');
      // Call for call the same as the first try.
      expect(t.gateway.callsTo('capture').map((c) => c.args['attempt']), [
        0,
        0,
      ]);
      final charges = t.gateway.callsTo('chargeNow');
      expect(charges.map((c) => c.args['attempt']), [1, 1]);
      expect(charges[1].args, charges[0].args);
      expect(t.gateway.intents.where((i) => i.status == 'succeeded'), [charge]);
      expect(payment(id)['paymentIntentId'], charge.id);
      expect(payment(id)['paymentMethodId'], charge.paymentMethodId);
    });

    test('an outage does not use up the attempt; an answer does', () async {
      final id = await inProgress();
      t.gateway.unavailable = true;
      await t.post('/jobs/$id/complete', token: t.marcus);
      await t.post('/jobs/$id/retry-payment', token: t.lia);
      t.gateway.unavailable = false;
      // The service answers with an error, then with a decline: both final.
      t.gateway.captureOutcomes.addAll([
        PaymentOutcome.unavailable,
        PaymentOutcome.declined,
      ]);
      await t.post('/jobs/$id/retry-payment', token: t.lia);
      await t.post('/jobs/$id/retry-payment', token: t.lia);
      final retried = await t.post('/jobs/$id/retry-payment', token: t.lia);
      expect((retried.map['payment'] as Map)['status'], 'captured');
      expect(t.gateway.callsTo('capture').map((c) => c.args['attempt']), [
        0,
        0,
        0,
        1,
        2,
      ]);
    });

    test('a refused held card falls back to a newer saved card', () async {
      final id = await inProgress();
      final oldCard = payment(id)['paymentMethodId'];
      await t.saveCard(t.sarah);
      t.gateway.captureOutcomes.add(PaymentOutcome.declined);
      await t.post('/jobs/$id/complete', token: t.marcus);

      final charge = t.gateway.callsTo('chargeNow').single.args;
      expect(charge['paymentMethodId'], isNot(oldCard));
      expect(charge['amountDollars'], 45);
      expect(charge['attempt'], 1);
      expect(payment(id)['status'], 'captured');
      expect(payment(id)['paymentMethodId'], charge['paymentMethodId']);
    });

    test(
      'mark-paid and retry-payment only apply to unpaid finished jobs',
      () async {
        final open = await requested();
        expectError(
          await t.post('/jobs/$open/mark-paid', token: t.lia),
          409,
          'invalid_state',
        );
        expectError(
          await t.post('/jobs/$open/retry-payment', token: t.lia),
          409,
          'invalid_state',
        );
        await t.plough(t.marcus, open);
        expectError(
          await t.post('/jobs/$open/mark-paid', token: t.lia),
          409,
          'invalid_state',
        );
        // A manual job that is due cannot be retried on a card.
        expectError(
          await t.post('/jobs/job_cedar_1/retry-payment', token: t.lia),
          409,
          'invalid_state',
        );
        final paid = await t.post('/jobs/job_cedar_1/mark-paid', token: t.lia);
        expect((paid.map['payment'] as Map)['status'], 'paid');
        expect((await t.get('/billing', token: t.anna)).map['balanceDue'], 0);
      },
    );
  });

  group('the stale-job sweep', () {
    test(
      'cancels open jobs nobody accepted in time and releases holds',
      () async {
        final held = await requested();
        await t.post('/jobs/job_cedar_2/claim', token: t.jordan);

        t.advance(const Duration(hours: 47, minutes: 55));
        await t.get('/health');
        expect(t.jobDoc(held)['status'], 'open');

        t.advance(const Duration(minutes: 10));
        final seen = await t.get('/jobs/$held', token: t.sarah);
        expect(seen.map['status'], 'cancelled');
        expect(seen.map['cancelledBy'], 'system');
        expect(seen.map['cancelledAt'], isNotNull);
        expect(t.logs.join('\n'), contains('cancelled 1 open job'));
        // The hold is released right after, without holding the request up.
        await until(() => payment(held)['status'] == 'released');
        expect(t.gateway.intentForJob(held)!.status, 'canceled');
        // A claimed job is somebody's responsibility and is left alone.
        expect(t.jobDoc('job_cedar_2')['status'], 'claimed');
        // Saved, not only in memory.
        await until(
          () =>
              (t.persistence.doc(Collections.jobs, held)!['payment']
                  as Map)['status'] ==
              'released',
        );
        expect(
          t.persistence.doc(Collections.jobs, held)!['status'],
          'cancelled',
        );
        await requested();
      },
    );

    test('no request waits for the payment service', () async {
      final held = await requested();
      t.advance(const Duration(hours: 49));
      t.gateway.latency = const Duration(milliseconds: 150);

      final seen = await t.get('/jobs/$held', token: t.sarah);
      // Answered while the release is still on its way: cancelled and saved
      // as such, the hold not yet let go.
      expect(seen.map['status'], 'cancelled');
      expect((seen.map['payment'] as Map)['status'], 'authorized');
      expect(t.gateway.intentForJob(held)!.status, 'requires_capture');
      expect(t.persistence.doc(Collections.jobs, held)!['status'], 'cancelled');

      await until(() => payment(held)['status'] == 'released');
      expect(t.gateway.intentForJob(held)!.status, 'canceled');
      expect(t.gateway.callsTo('cancel'), hasLength(1));
    });

    test(
      'a crew member rejected during a sweep does not keep the job',
      () async {
        // A hold that could not be released gives the next sweep slow card
        // work to do...
        final stuck = await requested();
        t.gateway.unavailable = true;
        await t.post('/jobs/$stuck/cancel', token: t.sarah);
        t.gateway
          ..unavailable = false
          ..latency = const Duration(milliseconds: 100);
        t.advance(const Duration(minutes: 11));
        // ...while Marcus accepts a job and the admin rejects him.
        final claim = t.post('/jobs/job_cedar_2/claim', token: t.marcus);
        final reject = t.post('/crew/crew_marcus/reject', token: t.lia);
        final replies = await Future.wait([claim, reject]);
        expect(replies[1].status, 200, reason: replies[1].text);
        expect(t.gateway.callsTo('cancel'), hasLength(2), reason: 'swept');

        // Whichever came first, a rejected member holds no accepted job.
        final job = t.jobDoc('job_cedar_2');
        expect((job['status'], job['crewId']), ('open', null));
        expectError(
          await t.post('/jobs/job_cedar_2/start', token: t.marcus),
          403,
          'crew_rejected',
        );
        expect(
          (await t.get(
            '/jobs?scope=open',
            token: t.jordan,
          )).list.map((j) => j['id']),
          ['job_cedar_2'],
        );
        await until(() => payment(stuck)['status'] == 'released');
      },
    );

    test(
      'honours settings.openJobExpiryHours and runs every ten minutes',
      () async {
        await t.post(
          '/settings',
          token: t.lia,
          body: {'openJobExpiryHours': 1},
        );
        // The seeded open job was requested ten minutes before the start time.
        t.advance(const Duration(minutes: 49));
        await t.get('/health');
        expect(t.jobDoc('job_cedar_2')['status'], 'open');

        // Stale now, but the last sweep was two minutes ago.
        t.advance(const Duration(minutes: 2));
        await t.get('/health');
        expect(t.jobDoc('job_cedar_2')['status'], 'open');

        t.advance(const Duration(minutes: 9));
        await t.get('/health');
        final job = t.jobDoc('job_cedar_2');
        expect(job['status'], 'cancelled');
        expect(job['cancelledBy'], 'system');
        // A manual job has no hold to release.
        expect((job['payment'] as Map)['status'], 'none');
        expect(t.gateway.callsTo('cancel'), isEmpty);
      },
    );

    test('finishes a capture that a failed save interrupted', () async {
      final id = await requested();
      await t.post('/jobs/$id/claim', token: t.marcus);
      await t.post('/jobs/$id/start', token: t.marcus);
      t.persistence.failNextCommits(1);
      await t.post('/jobs/$id/complete', token: t.marcus);
      expect(payment(id)['status'], 'authorized');

      t.advance(const Duration(minutes: 11));
      await t.get('/health');
      await until(() => payment(id)['status'] == 'captured');
      expect(t.gateway.intentForJob(id)!.status, 'succeeded');
    });

    test('a failing sweep never fails the request that triggered it', () async {
      final id = await requested();
      t.advance(const Duration(hours: 49));
      t.persistence.failNextCommits(1);
      final health = await t.get('/health');
      expect(health.status, 200);
      await until(() => t.logs.join('\n').contains('sweep: failed'));
      // The cancellation itself happened; no hold is released before it is
      // saved.
      expect(t.jobDoc(id)['status'], 'cancelled');
      expect(t.gateway.callsTo('cancel'), isEmpty);
      t.advance(const Duration(minutes: 11));
      await t.get('/health');
      await until(() => payment(id)['status'] == 'released');
      expect(t.persistence.doc(Collections.jobs, id)!['status'], 'cancelled');
    });
  });

  group('listing', () {
    Future<List<Object?>> ids(String path, String token) async {
      final reply = await t.get(path, token: token);
      expect(reply.status, 200, reason: reply.text);
      return [for (final j in reply.list) j['id']];
    }

    test(
      'the admin sees every job, newest request first, with filters',
      () async {
        expect(await ids('/jobs', t.lia), [
          'job_cedar_2',
          'job_maple_3',
          'job_cedar_1',
          'job_maple_2',
          'job_maple_1',
        ]);
        expect(await ids('/jobs?status=open,cancelled', t.lia), [
          'job_cedar_2',
        ]);
        expect(await ids('/jobs?customerId=cust_anna', t.lia), [
          'job_cedar_2',
          'job_cedar_1',
        ]);
        expect(await ids('/jobs?crewId=crew_jordan', t.lia), ['job_cedar_1']);
        expect(await ids('/jobs?propertyId=prop_maple&status=done', t.lia), [
          'job_maple_3',
          'job_maple_2',
          'job_maple_1',
        ]);
        expect(await ids('/jobs?payment=due,none', t.lia), [
          'job_cedar_2',
          'job_cedar_1',
        ]);
        final from = Uri.encodeQueryComponent('2026-01-03T00:00:00Z');
        final to = Uri.encodeQueryComponent('2026-01-06T00:00:00.000Z');
        expect(await ids('/jobs?from=$from&to=$to', t.lia), [
          'job_maple_3',
          'job_cedar_1',
        ]);
        expect(await ids('/jobs?from=$to', t.lia), ['job_cedar_2']);
        expect(await ids('/jobs?customerId=cust_paul', t.lia), isEmpty);
      },
    );

    test('a customer filters their own jobs', () async {
      final live = await requested();
      expect(await ids('/jobs', t.sarah), [
        live,
        'job_maple_3',
        'job_maple_2',
        'job_maple_1',
      ]);
      expect(await ids('/jobs?status=open,claimed,inProgress', t.sarah), [
        live,
      ]);
      expect(await ids('/jobs?propertyId=prop_cabin', t.sarah), isEmpty);
      // Admin-only filters do not widen a customer's list.
      expect(await ids('/jobs?customerId=cust_anna', t.sarah), hasLength(4));
    });

    test(
      'crew see the open list oldest first and their own by activity',
      () async {
        final newer = await requested();
        expect(await ids('/jobs?scope=open', t.marcus), ['job_cedar_2', newer]);
        expect(await ids('/jobs?scope=open', t.jordan), ['job_cedar_2', newer]);

        t.advance(const Duration(minutes: 1));
        await t.post('/jobs/$newer/claim', token: t.marcus);
        expect(await ids('/jobs', t.marcus), [
          newer,
          'job_maple_3',
          'job_maple_2',
          'job_maple_1',
        ]);
        expect(await ids('/jobs?scope=mine', t.marcus), hasLength(4));
        expect(await ids('/jobs?scope=open', t.jordan), ['job_cedar_2']);
      },
    );

    test('bad filters are validation errors', () async {
      for (final (path, token) in [
        ('/jobs?status=finished', t.lia),
        ('/jobs?payment=free', t.lia),
        ('/jobs?from=yesterday', t.lia),
        ('/jobs?status=', t.sarah),
        ('/jobs?status=open,nope', t.sarah),
        ('/jobs?scope=all', t.marcus),
      ]) {
        final reply = await t.get(path, token: token);
        if (path == '/jobs?status=') {
          expect(reply.status, 200, reason: 'an empty filter is no filter');
        } else {
          expectError(reply, 400, 'validation');
        }
      }
    });
  });
}

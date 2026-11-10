import 'package:redefine_api/src/data/persistence.dart';
import 'package:test/test.dart';

import 'support/harness.dart';

void main() {
  test(
    'a second server over the same database sees everything; sessions survive',
    () async {
      final first = await TestApp.start();
      final sarah = await first.login('sarah.m@gmail.com');
      await first.saveCard(sarah);
      final job = await first.requestPlough(sarah, 'prop_maple', shovel: true);
      final id = job['id'] as String;
      await first.post('/jobs/$id/claim', token: first.marcus);
      await first.post(
        '/quotes/quote_cabin/send',
        token: first.lia,
        body: {'price': 120, 'crewPay': 70},
      );
      await first.post(
        '/settings',
        token: first.lia,
        body: {'openJobExpiryHours': 24},
      );
      expect(first.store.isDirty, isFalse);

      // "Restart": a new store and app, loaded from what was persisted.
      final second = await TestApp.start(persistence: first.persistence);
      expect(second.persistence.loadCount, 2);
      expect(second.store.count(Collections.users), 7, reason: 'no re-seed');

      final me = await second.get('/auth/me', token: sarah);
      expect(me.status, 200, reason: 'the session was persisted');
      expect(me.map['email'], 'sarah.m@gmail.com');

      for (final path in [
        '/jobs',
        '/properties',
        '/quotes',
        '/crew',
        '/customers',
        '/customers/cust_sarah',
        '/dashboard/admin',
        '/settings',
        '/crew/crew_marcus/pay',
      ]) {
        final before = await first.get(path, token: first.lia);
        final after = await second.get(path, token: second.lia);
        expect(after.status, 200, reason: path);
        expect(after.json, before.json, reason: path);
      }
      expect((await second.get('/billing', token: sarah)).map['card'], {
        'brand': 'visa',
        'last4': '4242',
        'expMonth': 12,
        'expYear': 2030,
        'updatedAt': isNotNull,
      });

      // The private payment fields came along, so the hold can be released.
      final stored = second.jobDoc(id)['payment'] as Map<String, dynamic>;
      expect(stored['paymentIntentId'], startsWith('pi_'));
      expect(stored['paymentMethodId'], startsWith('pm_'));

      // Passwords too: logging in again works against the reloaded hashes.
      final started = await second.post(
        '/jobs/$id/start',
        token: await second.login('marcus@redefine.co'),
      );
      expect(started.map['status'], 'inProgress');

      // Logging out on one server is persisted for the next.
      await second.post('/auth/logout', token: sarah);
      final third = await TestApp.start(persistence: first.persistence);
      expectError(
        await third.get('/auth/me', token: sarah),
        401,
        'unauthorized',
      );
      expect(third.jobDoc(id)['status'], 'inProgress');
    },
  );

  test(
    'a failed commit answers 503; a later flush persists the change',
    () async {
      final t = await TestApp.start();
      t.persistence.failNextCommits(1);
      final failed = await t.post(
        '/properties',
        token: t.sarah,
        body: {'name': 'Garage', 'address': '5 Mill Rd'},
      );
      expectError(failed, 503, 'storage_unavailable');
      expect(
        failed.headers['access-control-allow-origin'],
        '*',
        reason: 'CORS on storage errors too',
      );
      expect(t.persistence.docs(Collections.properties), hasLength(4));
      // Memory stays authoritative and the change is queued.
      expect(t.store.count(Collections.properties), 5);
      expect(t.store.isDirty, isTrue);
      expect(t.logs.join('\n'), contains('flush'));

      // Any later request flushes what is still queued, even a read.
      final list = await t.get('/properties', token: t.sarah);
      expect(list.list.map((p) => p['name']), contains('Garage'));
      expect(t.store.isDirty, isFalse);
      expect(t.persistence.docs(Collections.properties), hasLength(5));
      expect(t.persistence.docs(Collections.quotes), hasLength(5));

      final restarted = await TestApp.start(persistence: t.persistence);
      expect(
        (await restarted.get(
          '/properties',
          token: restarted.sarah,
        )).list.map((p) => p['name']),
        contains('Garage'),
      );
    },
  );

  test('a persistent outage keeps answering 503 without losing data', () async {
    final t = await TestApp.start();
    t.persistence.failNextCommits(3);
    for (var i = 0; i < 3; i++) {
      expectError(
        await t.post('/jobs/job_cedar_2/claim', token: t.marcus),
        503,
        'storage_unavailable',
      );
    }
    // The claim happened once; repeating it was idempotent each time.
    expect(t.jobDoc('job_cedar_2')['crewId'], 'crew_marcus');
    expect(
      t.persistence.doc(Collections.jobs, 'job_cedar_2')!['status'],
      'open',
    );

    final ok = await t.post('/jobs/job_cedar_2/claim', token: t.marcus);
    expect(ok.status, 200);
    expect(
      t.persistence.doc(Collections.jobs, 'job_cedar_2')!['status'],
      'claimed',
    );
  });

  test(
    'a document the database refuses fails one request, not all later ones',
    () async {
      final t = await TestApp.start();
      final sarah = await t.login('sarah.m@gmail.com');
      final marcus = await t.login('marcus@redefine.co');
      t.persistence.rejectWrite = (w) => w.data?['name'] == 'Poison';

      final refused = await t.post(
        '/properties',
        token: sarah,
        body: {'name': 'Poison', 'address': '5 Mill Rd'},
      );
      expectError(refused, 503, 'storage_unavailable');
      // What could not be stored is gone from memory too, so it is not sent
      // again with every later save.
      expect(t.store.count(Collections.properties), 4);
      expect(t.store.count(Collections.quotes), 4);
      expect(t.store.isDirty, isFalse);
      expect(t.logs.join('\n'), contains('giving up the refused writes'));

      final ok = await t.post(
        '/properties',
        token: sarah,
        body: {'name': 'Garage', 'address': '5 Mill Rd'},
      );
      expect(ok.status, 201, reason: ok.text);
      expect(
        (await t.post('/jobs/job_cedar_2/claim', token: marcus)).status,
        200,
      );
      await t.login('lia@redefine.co');
      expect(t.persistence.docs(Collections.properties), hasLength(5));
      expect(
        t.persistence.doc(Collections.jobs, 'job_cedar_2')!['status'],
        'claimed',
      );
    },
  );

  test(
    'when another instance takes over, the request fails and state reloads',
    () async {
      final t = await TestApp.start();
      final token = await t.login('marcus@redefine.co');
      t.persistence.loseLeaseOnNextCommit();
      final reply = await t.post('/jobs/job_cedar_2/claim', token: token);
      expectError(reply, 503, 'storage_unavailable');
      // The unsaved claim is gone: the database is the truth after a takeover.
      expect(t.jobDoc('job_cedar_2')['status'], 'open');
      expect((await t.get('/auth/me', token: token)).status, 200);
      final retry = await t.post('/jobs/job_cedar_2/claim', token: token);
      expect(retry.status, 200);
      expect(retry.map['status'], 'claimed');
    },
  );

  test(
    'the demo seed is written once and only into an empty database',
    () async {
      final t = await TestApp.start();
      final users = t.persistence.docs(Collections.users);
      expect(users, hasLength(7));
      final again = await TestApp.start(persistence: t.persistence);
      expect(again.persistence.docs(Collections.users), users);
      expect(again.store.count(Collections.jobs), 5);

      final empty = await TestApp.start(seed: false);
      expect(empty.store.count(Collections.users), 0);
      expect(empty.store.settings, {
        'id': 'main',
        'shovelPrice': 20,
        'crewShovelBonus': 10,
        'openJobExpiryHours': 48,
      });
      expect(empty.persistence.doc(Collections.settings, 'main'), isNotNull);
    },
  );
}

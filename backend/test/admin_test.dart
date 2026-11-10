import 'package:test/test.dart';

import 'support/harness.dart';

void main() {
  late TestApp t;

  setUp(() async => t = await TestApp.start());

  group('crew management', () {
    test('the crew list is grouped by status with earnings', () async {
      final crew = await t.get('/crew', token: t.lia);
      expect(crew.status, 200, reason: crew.text);
      expect(crew.map.keys, ['active', 'pending', 'rejected']);
      expect(crew.map['active'], [
        {
          'id': 'crew_jordan',
          'userId': 'user_jordan',
          'name': 'Jordan Park',
          'initials': 'JP',
          'color': 'paper',
          'email': 'jordan@redefine.co',
          'phone': '(807) 555-0127',
          'status': 'active',
          'appliedAt': '2025-11-30T15:00:00.000Z',
          // Last Sunday's job is not part of this week.
          'jobsThisWeek': 0,
          'earnedThisWeek': 0,
          'unpaidTotal': 30,
          'unpaidJobs': 1,
        },
        {
          'id': 'crew_marcus',
          'userId': 'user_marcus',
          'name': 'Marcus Reid',
          'initials': 'MR',
          'color': 'teal',
          'email': 'marcus@redefine.co',
          'phone': '(807) 555-0111',
          'status': 'active',
          'appliedAt': '2025-11-23T15:00:00.000Z',
          'jobsThisWeek': 1,
          'earnedThisWeek': 25,
          'unpaidTotal': 50,
          'unpaidJobs': 2,
        },
      ]);
      expect((crew.map['pending'] as List).map((c) => (c as Map)['id']), [
        'crew_tasha',
      ]);
      expect(crew.map['rejected'], isEmpty);
    });

    test('approving lets a crew member work; it can be repeated', () async {
      final approved = await t.post('/crew/crew_tasha/approve', token: t.lia);
      expect(approved.status, 200, reason: approved.text);
      expect(approved.map['id'], 'crew_tasha');
      expect(approved.map['status'], 'active');
      expect(approved.map['unpaidJobs'], 0);
      expect(
        (await t.post('/crew/crew_tasha/approve', token: t.lia)).map,
        approved.map,
      );

      final claimed = await t.post('/jobs/job_cedar_2/claim', token: t.tasha);
      expect(claimed.status, 200, reason: claimed.text);
      expect(claimed.map['crewId'], 'crew_tasha');
      final crew = await t.get('/crew', token: t.lia);
      expect((crew.map['active'] as List).map((c) => (c as Map)['name']), [
        'Jordan Park',
        'Marcus Reid',
        'Tasha Rivera',
      ]);
      expect(crew.map['pending'], isEmpty);
    });

    test('rejecting reopens what they had only claimed', () async {
      await t.post('/jobs/job_cedar_2/claim', token: t.marcus);
      final started = await t.requestPlough(t.lia, 'prop_maple');
      await t.post('/jobs/${started['id']}/claim', token: t.marcus);
      await t.post('/jobs/${started['id']}/start', token: t.marcus);

      final rejected = await t.post('/crew/crew_marcus/reject', token: t.lia);
      expect(rejected.status, 200, reason: rejected.text);
      expect(rejected.map['status'], 'rejected');

      final reopened = (await t.get('/jobs/job_cedar_2', token: t.lia)).map;
      expect(reopened['status'], 'open');
      expect(reopened['crewId'], isNull);
      expect(reopened['claimedAt'], isNull);
      // Work in progress stays theirs until the office sorts it out.
      final working = (await t.get('/jobs/${started['id']}', token: t.lia)).map;
      expect(working['status'], 'inProgress');
      expect(working['crewId'], 'crew_marcus');

      expectError(
        await t.post('/jobs/${started['id']}/complete', token: t.marcus),
        403,
        'crew_rejected',
      );
      expect(
        (await t.get('/auth/me', token: t.marcus)).map['crewStatus'],
        'rejected',
      );
      final closed = await t.post(
        '/jobs/${started['id']}/complete',
        token: t.lia,
      );
      expect(closed.map['status'], 'done');
      // What they earned is still owed and can be paid out.
      final pay = await t.get('/crew/crew_marcus/pay', token: t.lia);
      expect(pay.map['unpaidTotal'], 75);
      final crew = await t.get('/crew', token: t.lia);
      expect(
        (crew.map['rejected'] as List).single,
        containsPair('id', 'crew_marcus'),
      );

      // Someone else can take the reopened job; the decision can be undone.
      expect(
        (await t.post('/jobs/job_cedar_2/claim', token: t.jordan)).status,
        200,
      );
      final back = await t.post('/crew/crew_marcus/approve', token: t.lia);
      expect(back.map['status'], 'active');
      expect((await t.get('/jobs', token: t.marcus)).status, 200);
    });

    test(
      'pay shows today, this week, all time, unpaid jobs and payouts',
      () async {
        final pay = await t.get('/crew/crew_marcus/pay', token: t.lia);
        expect(pay.status, 200, reason: pay.text);
        expect(pay.map.keys, [
          'crewId',
          'name',
          'earnedToday',
          'jobsToday',
          'earnedThisWeek',
          'jobsThisWeek',
          'earnedAllTime',
          'unpaidTotal',
          'unpaidJobs',
          'payouts',
        ]);
        expect(pay.map['crewId'], 'crew_marcus');
        expect(pay.map['name'], 'Marcus Reid');
        expect([pay.map['earnedToday'], pay.map['jobsToday']], [0, 0]);
        expect([pay.map['earnedThisWeek'], pay.map['jobsThisWeek']], [25, 1]);
        expect(pay.map['earnedAllTime'], 85);
        expect(pay.map['unpaidTotal'], 50);
        final unpaid = (pay.map['unpaidJobs'] as List)
            .cast<Map<String, dynamic>>();
        expect(unpaid.map((j) => j['id']), ['job_maple_3', 'job_maple_2']);
        // The crew member's own Job view, even when the admin asks.
        expect(unpaid.first['customerName'], 'Sarah Mitchell');
        expect(unpaid.first['crewPay'], 25);
        expect(unpaid.first['paidOut'], isFalse);
        expect(unpaid.first.containsKey('total'), isFalse);
        expect(unpaid.first.containsKey('payment'), isFalse);
        expect(pay.map['payouts'], [
          {
            'id': 'payout_1',
            'crewId': 'crew_marcus',
            'amount': 35,
            'jobCount': 1,
            'paidAt': '2025-12-24T15:00:00.000Z',
            'note': 'e-transfer',
          },
        ]);
        // The crew member sees exactly the same.
        expect((await t.get('/crew/me/pay', token: t.marcus)).map, pay.map);
      },
    );

    test('a payout covers every unpaid job exactly once', () async {
      expectError(
        await t.post('/crew/crew_tasha/payouts', token: t.lia),
        409,
        'nothing_to_pay',
      );
      final first = await t.post('/crew/crew_jordan/payouts', token: t.lia);
      expect(first.status, 200, reason: first.text);
      expect(first.map.keys, ['payout', 'pay']);
      final payout = first.map['payout'] as Map;
      expect(
        [payout['amount'], payout['jobCount'], payout['note']],
        [30, 1, ''],
      );
      final pay = first.map['pay'] as Map;
      expect(pay['unpaidTotal'], 0);
      expect(pay['earnedAllTime'], 30);
      expect((pay['payouts'] as List).single, payout);
      expect(
        (await t.get('/jobs/job_cedar_1', token: t.lia)).map['paidOut'],
        isTrue,
      );
      expectError(
        await t.post('/crew/crew_jordan/payouts', token: t.lia),
        409,
        'nothing_to_pay',
      );

      // Unfinished work is not paid; it is once it is done.
      await t.post('/jobs/job_cedar_2/claim', token: t.jordan);
      await t.post('/jobs/job_cedar_2/start', token: t.jordan);
      expectError(
        await t.post('/crew/crew_jordan/payouts', token: t.lia),
        409,
        'nothing_to_pay',
      );
      await t.post('/jobs/job_cedar_2/complete', token: t.jordan);
      t.advance(const Duration(hours: 1));
      final second = await t.post(
        '/crew/crew_jordan/payouts',
        token: t.lia,
        body: {'note': ' cash '},
      );
      final again = second.map['payout'] as Map;
      expect(
        [again['amount'], again['jobCount'], again['note']],
        [40, 1, 'cash'],
      );
      expect(
        ((second.map['pay'] as Map)['payouts'] as List).map(
          (p) => (p as Map)['amount'],
        ),
        [40, 30],
        reason: 'newest first',
      );
    });
  });

  group('today and this week follow the caller\'s time zone', () {
    test('today', () async {
      t = await TestApp.start(stripe: false, now: DateTime.utc(2026, 1, 6, 23));
      await t.post('/jobs/job_cedar_2/claim', token: t.jordan);
      await t.post('/jobs/job_cedar_2/start', token: t.jordan);
      t.now = DateTime.utc(2026, 1, 6, 23, 30);
      await t.post('/jobs/job_cedar_2/complete', token: t.jordan);
      final extra = await t.requestPlough(t.lia, 'prop_maple');
      t.now = DateTime.utc(2026, 1, 6, 23, 40);
      await t.post('/jobs/${extra['id']}/cancel', token: t.lia);

      // 04:30 UTC on the 7th: still the evening of the 6th in Thunder Bay.
      t.now = DateTime.utc(2026, 1, 7, 4, 30);
      Future<Map<String, dynamic>> pay(String query) async =>
          (await t.get('/crew/me/pay$query', token: t.jordan)).map;
      Future<Map> counts(String query) async =>
          (await t.get('/dashboard/admin$query', token: t.lia)).map['counts']
              as Map;

      final utc = await pay('');
      expect([utc['jobsToday'], utc['earnedToday']], [0, 0]);
      final local = await pay('?tz=-300');
      expect([local['jobsToday'], local['earnedToday']], [1, 40]);
      final india = await pay('?tz=330');
      expect([india['jobsToday'], india['earnedToday']], [1, 40]);
      final azores = await pay('?tz=-60');
      expect([azores['jobsToday'], azores['earnedToday']], [0, 0]);

      final utcCounts = await counts('?tz=0');
      expect(
        [
          utcCounts['doneToday'],
          utcCounts['revenueToday'],
          utcCounts['cancelledToday'],
        ],
        [0, 0, 0],
      );
      final localCounts = await counts('?tz=-300');
      expect(
        [
          localCounts['doneToday'],
          localCounts['revenueToday'],
          localCounts['cancelledToday'],
        ],
        [1, 75, 1],
      );
    });

    test('this week starts on the caller\'s Monday', () async {
      // Sunday night UTC.
      t = await TestApp.start(stripe: false, now: DateTime.utc(2026, 1, 4, 22));
      await t.post('/jobs/job_cedar_2/claim', token: t.jordan);
      await t.post('/jobs/job_cedar_2/start', token: t.jordan);
      t.now = DateTime.utc(2026, 1, 4, 23);
      await t.post('/jobs/job_cedar_2/complete', token: t.jordan);

      // Monday 02:00 UTC is still Sunday evening at UTC-5.
      t.now = DateTime.utc(2026, 1, 5, 2);
      Future<Map<String, dynamic>> pay(String query) async =>
          (await t.get('/crew/crew_jordan/pay$query', token: t.lia)).map;
      Future<Map> member(String query) async =>
          ((await t.get('/crew$query', token: t.lia)).map['active'] as List)
                  .firstWhere((c) => (c as Map)['id'] == 'crew_jordan')
              as Map;

      final utc = await pay('');
      expect([utc['jobsThisWeek'], utc['earnedThisWeek']], [0, 0]);
      expect([utc['jobsToday'], utc['earnedAllTime']], [0, 70]);
      // Locally the week also holds the seeded job from Thursday.
      final local = await pay('?tz=-300');
      expect([local['jobsThisWeek'], local['earnedThisWeek']], [2, 70]);
      expect(local['jobsToday'], 1);

      final utcMember = await member('');
      expect([utcMember['jobsThisWeek'], utcMember['earnedThisWeek']], [0, 0]);
      final localMember = await member('?tz=-300');
      expect(
        [localMember['jobsThisWeek'], localMember['earnedThisWeek']],
        [2, 70],
      );
      // In Sydney the job itself was already done on Monday morning.
      final sydney = await pay('?tz=660');
      expect([sydney['jobsThisWeek'], sydney['earnedThisWeek']], [1, 40]);
    });
  });

  group('customers', () {
    test('the list is sorted by name and summarises each customer', () async {
      final list = await t.get('/customers', token: t.lia);
      expect(list.status, 200, reason: list.text);
      expect(list.list.map((c) => c['name']), [
        'Anna Tomlinson',
        'Paul Larson',
        'Sarah Mitchell',
      ]);
      expect(list.list.last, {
        'id': 'cust_sarah',
        'name': 'Sarah Mitchell',
        'initials': 'SM',
        'color': 'teal',
        'email': 'sarah.m@gmail.com',
        'phone': '(807) 555-0142',
        'createdAt': '2025-12-17T15:00:00.000Z',
        'propertyCount': 2,
        'activeProperties': 1,
        'jobCount': 3,
        'lastJobAt': '2026-01-05T13:00:00.000Z',
        'hasCard': false,
        'addresses': [
          '412 Maple St, Thunder Bay, ON',
          '88 Lakeside Rd, Thunder Bay, ON',
        ],
      });
      final paul = list.list[1];
      expect(
        [paul['propertyCount'], paul['activeProperties'], paul['jobCount']],
        [1, 0, 0],
      );
      expect(paul['lastJobAt'], isNull);
      expect(paul['phone'], '');

      await t.saveCard(t.sarah);
      expect(
        (await t.get('/customers', token: t.lia)).list.last['hasCard'],
        isTrue,
      );
    });

    test('the detail adds card, properties, jobs and totals', () async {
      final anna = await t.get('/customers/cust_anna', token: t.lia);
      expect(anna.status, 200, reason: anna.text);
      expect(anna.map['id'], 'cust_anna');
      expect(anna.map['card'], isNull);
      expect(anna.map['totals'], {'billed': 0, 'outstanding': 55});
      final properties = (anna.map['properties'] as List).cast<Map>();
      expect(properties.single['id'], 'prop_cedar');
      expect(properties.single['crewPay'], 30);
      expect(properties.single['customerName'], 'Anna Tomlinson');
      expect((properties.single['activeJob'] as Map)['id'], 'job_cedar_2');
      final jobs = (anna.map['jobs'] as List).cast<Map>();
      expect(jobs.map((j) => j['id']), ['job_cedar_2', 'job_cedar_1']);
      expect(jobs.last['crewPay'], 30);
      expect((jobs.last['payment'] as Map)['status'], 'due');

      final sarah = await t.get('/customers/cust_sarah', token: t.lia);
      expect(sarah.map['totals'], {'billed': 155, 'outstanding': 0});
      expect((sarah.map['properties'] as List).map((p) => (p as Map)['id']), [
        'prop_maple',
        'prop_cabin',
      ]);
      await t.saveCard(t.sarah);
      final withCard = await t.get('/customers/cust_sarah', token: t.lia);
      expect(withCard.map['hasCard'], isTrue);
      expect((withCard.map['card'] as Map).keys, [
        'brand',
        'last4',
        'expMonth',
        'expYear',
        'updatedAt',
      ]);
    });
  });

  group('dashboard', () {
    test('counts and lists reflect the live state', () async {
      final seeded = await t.get('/dashboard/admin', token: t.lia);
      expect(seeded.status, 200, reason: seeded.text);
      expect(seeded.map.keys, [
        'serverTime',
        'counts',
        'pendingQuotes',
        'liveJobs',
        'pendingCrew',
        'paymentIssues',
      ]);
      expect(seeded.map['serverTime'], '2026-01-07T15:00:00.000Z');
      expect(seeded.map['counts'], {
        'pendingQuotes': 1,
        'sentQuotes': 1,
        'pendingCrew': 1,
        'openJobs': 1,
        'claimedJobs': 0,
        'inProgressJobs': 0,
        'doneToday': 0,
        'cancelledToday': 0,
        'revenueToday': 0,
        'paymentIssues': 1,
      });
      List<Object?> ids(Reply r, String key) => [
        for (final item in r.map[key] as List) (item as Map)['id'],
      ];
      expect(ids(seeded, 'pendingQuotes'), ['quote_cabin']);
      expect(ids(seeded, 'liveJobs'), ['job_cedar_2']);
      expect(ids(seeded, 'pendingCrew'), ['crew_tasha']);
      expect(ids(seeded, 'paymentIssues'), ['job_cedar_1']);
      final quote = (seeded.map['pendingQuotes'] as List).single as Map;
      expect(quote['customerName'], 'Sarah Mitchell');
      expect(quote['address'], '88 Lakeside Rd, Thunder Bay, ON');
      expect(quote['note'], contains('gravel driveway'));

      // Move things along and look again.
      t.advance(const Duration(hours: 1));
      await t.post(
        '/properties',
        token: t.paul,
        body: {'name': 'Shop', 'address': '3 Main St'},
      );
      final extra = await t.requestPlough(t.lia, 'prop_maple', shovel: true);
      await t.post('/jobs/${extra['id']}/claim', token: t.marcus);
      await t.post('/jobs/${extra['id']}/start', token: t.marcus);
      await t.plough(t.jordan, 'job_cedar_2');
      t.advance(const Duration(minutes: 1));
      final second = await t.requestPlough(t.lia, 'prop_cedar');
      await t.post('/jobs/${second['id']}/claim', token: t.jordan);
      await t.post('/crew/crew_tasha/approve', token: t.lia);
      await t.post('/quotes/quote_birch/decline', token: t.paul);

      final now = await t.get('/dashboard/admin', token: t.lia);
      expect(now.map['counts'], {
        'pendingQuotes': 2,
        'sentQuotes': 0,
        'pendingCrew': 0,
        'openJobs': 0,
        'claimedJobs': 1,
        'inProgressJobs': 1,
        'doneToday': 1,
        'cancelledToday': 0,
        'revenueToday': 75,
        'paymentIssues': 2,
      });
      expect(
        ids(now, 'pendingQuotes').first,
        'quote_cabin',
        reason: 'oldest first',
      );
      expect(ids(now, 'liveJobs'), [extra['id'], second['id']]);
      expect(ids(now, 'paymentIssues'), ['job_cedar_2', 'job_cedar_1']);
      expect(now.map['pendingCrew'], isEmpty);
    });
  });

  group('settings', () {
    test(
      'the admin changes prices and every role sees its own slice',
      () async {
        final updated = await t.post(
          '/settings',
          token: t.lia,
          body: {
            'shovelPrice': 25,
            'crewShovelBonus': 12,
            'openJobExpiryHours': 36,
          },
        );
        expect(updated.status, 200, reason: updated.text);
        expect(updated.map, {
          'shovelPrice': 25,
          'crewShovelBonus': 12,
          'openJobExpiryHours': 36,
          'currency': 'cad',
          'paymentsMode': 'stripe',
        });
        expect((await t.get('/settings', token: t.lia)).map, updated.map);
        expect((await t.get('/settings', token: t.sarah)).map, {
          'shovelPrice': 25,
          'currency': 'cad',
          'paymentsMode': 'stripe',
        });
        expect((await t.get('/settings', token: t.marcus)).map, {
          'crewShovelBonus': 12,
          'currency': 'cad',
        });
        expect((await t.get('/settings', token: t.tasha)).map, {
          'crewShovelBonus': 12,
          'currency': 'cad',
        });

        // A partial update leaves the rest alone.
        final partial = await t.post(
          '/settings',
          token: t.lia,
          body: {'crewShovelBonus': 0},
        );
        expect(partial.map['shovelPrice'], 25);
        expect(partial.map['crewShovelBonus'], 0);
        expect(partial.map['openJobExpiryHours'], 36);

        final job = await t.requestPlough(t.lia, 'prop_maple', shovel: true);
        expect(
          [job['shovelPrice'], job['total'], job['crewPay']],
          [25, 70, 25],
        );
      },
    );
  });
}

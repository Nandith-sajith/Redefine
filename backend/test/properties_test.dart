import 'package:test/test.dart';

import 'support/harness.dart';

void main() {
  late TestApp t;

  setUp(() async => t = await TestApp.start());

  group('properties', () {
    test('the admin sees every property, oldest first, with filters', () async {
      final all = await t.get('/properties', token: t.lia);
      expect(all.status, 200, reason: all.text);
      expect(all.list.map((p) => p['id']), [
        'prop_maple',
        'prop_cedar',
        'prop_birch',
        'prop_cabin',
      ]);
      expect(all.list.first, {
        'id': 'prop_maple',
        'name': 'Maple Street home',
        'address': '412 Maple St, Thunder Bay, ON',
        'illustration': 'house',
        'note': '',
        'status': 'active',
        'price': 45,
        'quoteId': 'quote_maple',
        'createdAt': '2025-12-17T15:00:00.000Z',
        'activeJob': null,
        'customerId': 'cust_sarah',
        'customerName': 'Sarah Mitchell',
        'crewPay': 25,
      });
      final cedar = all.list[1];
      expect((cedar['activeJob'] as Map)['id'], 'job_cedar_2');
      expect((cedar['activeJob'] as Map)['crewPay'], 40);
      final cabin = all.list.last;
      expect(
        [cabin['status'], cabin['price'], cabin['crewPay']],
        ['quoteRequested', null, null],
      );

      Future<List<Object?>> ids(String query) async => [
        for (final p in (await t.get('/properties$query', token: t.lia)).list)
          p['id'],
      ];
      expect(await ids('?customerId=cust_sarah'), ['prop_maple', 'prop_cabin']);
      expect(await ids('?status=active'), ['prop_maple', 'prop_cedar']);
      expect(await ids('?status=quoted'), ['prop_birch']);
      expect(await ids('?customerId=cust_sarah&status=quoteRequested'), [
        'prop_cabin',
      ]);
      expect(await ids('?customerId=cust_nobody'), isEmpty);
    });

    test('a customer sees their own, without the crew pay', () async {
      final mine = await t.get('/properties?status=active', token: t.anna);
      expect(mine.list.single.keys, [
        'id',
        'name',
        'address',
        'illustration',
        'note',
        'status',
        'price',
        'quoteId',
        'createdAt',
        'activeJob',
      ]);
      final job = mine.list.single['activeJob'] as Map;
      expect(job['id'], 'job_cedar_2');
      expect(job['total'], 75);
      expect(job.containsKey('crewPay'), isFalse);
    });

    test('the admin can add a property for a customer', () async {
      final added = await t.post(
        '/properties',
        token: t.lia,
        body: {
          'customerId': 'cust_paul',
          'name': 'Workshop',
          'address': '40 Mill Rd, Thunder Bay, ON',
          'illustration': 'garage',
          'note': 'Called in by phone.',
        },
      );
      expect(added.status, 201, reason: added.text);
      final property = added.map['property'] as Map;
      final quote = added.map['quote'] as Map;
      expect(property['customerId'], 'cust_paul');
      expect(property['customerName'], 'Paul Larson');
      expect(property['status'], 'quoteRequested');
      expect(property['quoteId'], quote['id']);
      expect(quote['status'], 'pending');
      expect(quote['note'], 'Called in by phone.');
      expect(quote['customerName'], 'Paul Larson');
      expect(quote['illustration'], 'garage');
      // It shows up for the customer like one they added themselves.
      final mine = await t.get('/properties', token: t.paul);
      expect(mine.list.map((p) => p['name']), ['Birch Road home', 'Workshop']);
    });

    test('re-pricing applies to active properties only', () async {
      final repriced = await t.post(
        '/properties/prop_maple/price',
        token: t.lia,
        body: {'price': 50, 'crewPay': 28},
      );
      expect(repriced.status, 200, reason: repriced.text);
      expect([repriced.map['price'], repriced.map['crewPay']], [50, 28]);
      expect(repriced.map['status'], 'active');
      expect(
        (await t.get('/properties', token: t.sarah)).list.first['price'],
        50,
      );
      // The accepted quote keeps what was agreed at the time.
      expect(
        (await t.get('/quotes/quote_maple', token: t.lia)).map['price'],
        45,
      );
      for (final id in ['prop_cabin', 'prop_birch']) {
        expectError(
          await t.post(
            '/properties/$id/price',
            token: t.lia,
            body: {'price': 50, 'crewPay': 28},
          ),
          409,
          'invalid_state',
        );
      }
    });
  });

  group('quotes', () {
    test('lists are newest first; customers see only theirs', () async {
      final all = await t.get('/quotes', token: t.lia);
      expect(all.list.map((q) => q['id']), [
        'quote_cabin',
        'quote_birch',
        'quote_cedar',
        'quote_maple',
      ]);
      expect(all.list[1], {
        'id': 'quote_birch',
        'propertyId': 'prop_birch',
        'customerId': 'cust_paul',
        'status': 'sent',
        'note': 'Double driveway, please keep the snow off the hedge.',
        'price': 60,
        'crewPay': 35,
        'createdAt': '2026-01-05T15:00:00.000Z',
        'sentAt': '2026-01-06T15:00:00.000Z',
        'decidedAt': null,
        'customerName': 'Paul Larson',
        'customerInitials': 'PL',
        'customerColor': 'lime',
        'email': 'paul.l@gmail.com',
        'phone': '',
        'propertyName': 'Birch Road home',
        'address': '21 Birch Rd, Thunder Bay, ON',
        'illustration': 'townhouse',
      });
      expect(
        (await t.get(
          '/quotes?status=accepted',
          token: t.lia,
        )).list.map((q) => q['id']),
        ['quote_cedar', 'quote_maple'],
      );
      final sarah = await t.get('/quotes', token: t.sarah);
      expect(sarah.list.map((q) => q['id']), ['quote_cabin', 'quote_maple']);
      expect(sarah.list.map((q) => q['crewPay']), [null, null]);
      expect(
        (await t.get(
          '/quotes?status=pending',
          token: t.sarah,
        )).list.map((q) => q['id']),
        ['quote_cabin'],
      );
      final one = await t.get('/quotes/quote_birch', token: t.paul);
      expect(one.map['price'], 60);
      expect(one.map['crewPay'], isNull);
    });

    test(
      'sending prices the quote and the property; re-sending changes the offer',
      () async {
        final sent = await t.post(
          '/quotes/quote_cabin/send',
          token: t.lia,
          body: {'price': 120, 'crewPay': 70},
        );
        expect(sent.status, 200, reason: sent.text);
        expect(
          [sent.map['status'], sent.map['price'], sent.map['crewPay']],
          ['sent', 120, 70],
        );
        expect(sent.map['sentAt'], '2026-01-07T15:00:00.000Z');
        var cabin = (await t.get('/properties', token: t.sarah)).list.last;
        expect([cabin['status'], cabin['price']], ['quoted', 120]);

        t.advance(const Duration(hours: 1));
        final resent = await t.post(
          '/quotes/quote_cabin/send',
          token: t.lia,
          body: {'price': 110, 'crewPay': 65},
        );
        expect(
          [resent.map['status'], resent.map['price'], resent.map['crewPay']],
          ['sent', 110, 65],
        );
        expect(resent.map['sentAt'], '2026-01-07T16:00:00.000Z');
        cabin = (await t.get(
          '/properties?customerId=cust_sarah',
          token: t.lia,
        )).list.last;
        expect(
          [cabin['status'], cabin['price'], cabin['crewPay']],
          ['quoted', 110, 65],
        );
      },
    );

    test('accepting activates the property at the quoted price', () async {
      // Not before the admin has sent it.
      expectError(
        await t.post('/quotes/quote_cabin/accept', token: t.sarah),
        409,
        'quote_not_open',
      );
      expectError(
        await t.post('/quotes/quote_cabin/decline', token: t.sarah),
        409,
        'quote_not_open',
      );

      t.advance(const Duration(hours: 2));
      final accepted = await t.post(
        '/quotes/quote_birch/accept',
        token: t.paul,
      );
      expect(accepted.status, 200, reason: accepted.text);
      expect(accepted.map.keys, ['quote', 'property']);
      final quote = accepted.map['quote'] as Map;
      final property = accepted.map['property'] as Map;
      expect(
        [quote['status'], quote['decidedAt']],
        ['accepted', '2026-01-07T17:00:00.000Z'],
      );
      expect([property['status'], property['price']], ['active', 60]);
      expect(property.containsKey('crewPay'), isFalse);

      // Accepting again changes nothing; declining is too late.
      t.advance(const Duration(hours: 1));
      final again = await t.post('/quotes/quote_birch/accept', token: t.paul);
      expect(again.status, 200);
      expect(again.map, accepted.map);
      expectError(
        await t.post('/quotes/quote_birch/decline', token: t.paul),
        409,
        'quote_not_open',
      );
      expectError(
        await t.post(
          '/quotes/quote_birch/send',
          token: t.lia,
          body: {'price': 70, 'crewPay': 40},
        ),
        409,
        'quote_not_open',
      );
      // The price applies to every later request.
      for (var i = 0; i < 2; i++) {
        final job = await t.requestPlough(t.lia, 'prop_birch');
        expect([job['price'], job['total'], job['crewPay']], [60, 60, 35]);
        await t.post('/jobs/${job['id']}/cancel', token: t.paul);
      }
    });

    test('declining can be followed by a new quote request', () async {
      // Only a declined property can ask again.
      for (final (id, token) in [
        ('prop_birch', t.paul),
        ('prop_maple', t.sarah),
        ('prop_cabin', t.sarah),
      ]) {
        expectError(
          await t.post('/properties/$id/request-quote', token: token),
          409,
          'invalid_state',
        );
      }

      final declined = await t.post(
        '/quotes/quote_birch/decline',
        token: t.paul,
      );
      expect(declined.status, 200, reason: declined.text);
      expect((declined.map['quote'] as Map)['status'], 'declined');
      expect((declined.map['quote'] as Map)['decidedAt'], isNotNull);
      expect((declined.map['property'] as Map)['status'], 'declined');
      expect(
        (await t.post('/quotes/quote_birch/decline', token: t.paul)).map,
        declined.map,
      );
      expectError(
        await t.post('/quotes/quote_birch/accept', token: t.paul),
        409,
        'quote_not_open',
      );
      expectError(
        await t.post(
          '/quotes/quote_birch/send',
          token: t.lia,
          body: {'price': 55, 'crewPay': 30},
        ),
        409,
        'quote_not_open',
      );
      expectError(
        await t.post(
          '/jobs',
          token: t.paul,
          body: {'propertyId': 'prop_birch'},
        ),
        409,
        'invalid_state',
      );

      t.advance(const Duration(days: 1));
      final asked = await t.post(
        '/properties/prop_birch/request-quote',
        token: t.paul,
      );
      expect(asked.status, 200, reason: asked.text);
      final property = asked.map['property'] as Map;
      final quote = asked.map['quote'] as Map;
      expect([property['status'], property['price']], ['quoteRequested', null]);
      expect(property['quoteId'], quote['id']);
      expect(quote['id'], isNot('quote_birch'));
      expect([quote['status'], quote['price']], ['pending', null]);
      expect(quote['note'], contains('Double driveway'));
      expect(
        (await t.get('/quotes', token: t.paul)).list.map((q) => q['status']),
        ['pending', 'declined'],
      );

      // The new quote runs its own course.
      await t.post(
        '/quotes/${quote['id']}/send',
        token: t.lia,
        body: {'price': 52, 'crewPay': 30},
      );
      final accepted = await t.post(
        '/quotes/${quote['id']}/accept',
        token: t.paul,
      );
      expect((accepted.map['property'] as Map)['status'], 'active');
      expect((accepted.map['property'] as Map)['price'], 52);
    });
  });
}

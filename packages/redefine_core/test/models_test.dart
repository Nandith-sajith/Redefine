import 'package:redefine_core/redefine_core.dart';
import 'package:test/test.dart';

Map<String, dynamic> adminJob([Map<String, dynamic> over = const {}]) => {
  'id': 'job_1',
  'propertyId': 'prop_maple',
  'customerId': 'cust_sarah',
  'propertyName': 'Maple Street home',
  'address': '412 Maple St, Thunder Bay, ON',
  'illustration': 'house',
  'customerName': 'Sarah Mitchell',
  'customerInitials': 'SM',
  'customerPhone': '(807) 555-0142',
  'shovel': true,
  'price': 45,
  'shovelPrice': 20,
  'total': 65,
  'crewPay': 35,
  'status': 'done',
  'crewId': 'crew_marcus',
  'crewName': 'Marcus Reid',
  'crewInitials': 'MR',
  'crewColor': 'teal',
  'note': 'Gate code 4411',
  'crewNote': 'Salted the steps',
  'source': 'customer',
  'requestedAt': '2026-01-05T10:00:00Z',
  'claimedAt': '2026-01-05T10:04:00Z',
  'startedAt': '2026-01-05T10:30:00Z',
  'completedAt': '2026-01-05T11:17:00Z',
  'cancelledAt': null,
  'cancelledBy': null,
  'payment': {
    'mode': 'stripe',
    'status': 'captured',
    'error': null,
    'holdExpiresAt': '2026-01-11T10:00:00Z',
    'capturedAt': '2026-01-05T11:17:02Z',
  },
  'paidOut': true,
  ...over,
};

Map<String, dynamic> adminProperty([Map<String, dynamic> over = const {}]) => {
  'id': 'prop_maple',
  'name': 'Maple Street home',
  'address': '412 Maple St, Thunder Bay, ON',
  'illustration': 'house',
  'note': '',
  'status': 'active',
  'price': 45,
  'quoteId': 'quote_maple',
  'createdAt': '2025-11-20T15:00:00Z',
  'activeJob': null,
  'customerId': 'cust_sarah',
  'customerName': 'Sarah Mitchell',
  'crewPay': 25,
  ...over,
};

const quoteJson = <String, dynamic>{
  'id': 'quote_birch',
  'propertyId': 'prop_birch',
  'customerId': 'cust_paul',
  'status': 'sent',
  'note': 'Long gravel driveway',
  'price': 60,
  'crewPay': 35,
  'createdAt': '2026-01-02T09:00:00Z',
  'sentAt': '2026-01-03T09:00:00Z',
  'decidedAt': null,
  'customerName': 'Paul Larson',
  'customerInitials': 'PL',
  'customerColor': 'paper',
  'email': 'paul.l@gmail.com',
  'phone': '',
  'propertyName': 'Birch Road home',
  'address': '21 Birch Rd',
  'illustration': 'bungalow',
};

const cardJson = <String, dynamic>{
  'brand': 'visa',
  'last4': '4242',
  'expMonth': 4,
  'expYear': 2030,
  'updatedAt': '2026-01-01T00:00:00Z',
};

const crewMemberJson = <String, dynamic>{
  'id': 'crew_marcus',
  'userId': 'user_marcus',
  'name': 'Marcus Reid',
  'initials': 'MR',
  'color': 'teal',
  'email': 'marcus@redefine.co',
  'phone': '(807) 555-0111',
  'status': 'active',
  'appliedAt': '2025-11-01T12:00:00Z',
  'jobsThisWeek': 3,
  'earnedThisWeek': 95,
  'unpaidTotal': 60,
  'unpaidJobs': 2,
};

const payoutJson = <String, dynamic>{
  'id': 'payout_1',
  'crewId': 'crew_marcus',
  'amount': 25,
  'jobCount': 1,
  'paidAt': '2025-12-28T18:00:00Z',
  'note': 'e-transfer',
};

// One complete, valid sample per model, paired with its parser.
final samples =
    <String, (Object Function(Map<String, dynamic>), Map<String, dynamic>)>{
      'AuthUser': (
        AuthUser.fromJson,
        {
          'id': 'user_marcus',
          'name': 'Marcus Reid',
          'email': 'marcus@redefine.co',
          'role': 'crew',
          'initials': 'MR',
          'color': 'teal',
          'phone': '(807) 555-0111',
          'linkedId': 'crew_marcus',
          'crewStatus': 'active',
        },
      ),
      'AuthResult': (
        AuthResult.fromJson,
        {
          'token': 'tok',
          'user': {'id': 'user_lia', 'name': 'Lia Robinson', 'role': 'admin'},
        },
      ),
      'Settings': (
        Settings.fromJson,
        {
          'shovelPrice': 20,
          'crewShovelBonus': 10,
          'openJobExpiryHours': 48,
          'currency': 'cad',
          'paymentsMode': 'manual',
        },
      ),
      'PaymentInfo': (
        PaymentInfo.fromJson,
        adminJob()['payment'] as Map<String, dynamic>,
      ),
      'Job': (Job.fromJson, adminJob()),
      'Property': (
        Property.fromJson,
        adminProperty({
          'activeJob': adminJob({'status': 'open'}),
        }),
      ),
      'Quote': (Quote.fromJson, quoteJson),
      'CardInfo': (CardInfo.fromJson, cardJson),
      'Charge': (
        Charge.fromJson,
        {
          'jobId': 'job_1',
          'propertyName': 'Maple Street home',
          'date': '2026-01-05T11:17:00Z',
          'total': 65,
          'shovel': true,
          'status': 'captured',
        },
      ),
      'Billing': (
        Billing.fromJson,
        {
          'mode': 'stripe',
          'card': cardJson,
          'pendingSetup': false,
          'balanceDue': 0,
          'charges': [
            {'jobId': 'job_1', 'total': 65, 'status': 'captured'},
          ],
        },
      ),
      'Customer': (
        Customer.fromJson,
        {
          'id': 'cust_sarah',
          'name': 'Sarah Mitchell',
          'initials': 'SM',
          'color': 'lime',
          'email': 'sarah.m@gmail.com',
          'phone': '(807) 555-0142',
          'createdAt': '2025-11-20T15:00:00Z',
          'propertyCount': 2,
          'activeProperties': 1,
          'jobCount': 3,
          'lastJobAt': '2026-01-05T11:17:00Z',
          'hasCard': true,
          'addresses': ['412 Maple St, Thunder Bay, ON', '88 Lakeside Rd'],
        },
      ),
      'CustomerDetail': (
        CustomerDetail.fromJson,
        {
          'id': 'cust_sarah',
          'name': 'Sarah Mitchell',
          'addresses': ['412 Maple St, Thunder Bay, ON'],
          'card': cardJson,
          'properties': [adminProperty()],
          'jobs': [adminJob()],
          'totals': {'billed': 155, 'outstanding': 45},
        },
      ),
      'CrewMember': (CrewMember.fromJson, crewMemberJson),
      'Payout': (Payout.fromJson, payoutJson),
      'CrewPay': (
        CrewPay.fromJson,
        {
          'crewId': 'crew_marcus',
          'name': 'Marcus Reid',
          'earnedToday': 35,
          'jobsToday': 1,
          'earnedThisWeek': 95,
          'jobsThisWeek': 3,
          'earnedAllTime': 410,
          'unpaidTotal': 60,
          'unpaidJobs': [adminJob()],
          'payouts': [payoutJson],
        },
      ),
      'DashboardCounts': (
        DashboardCounts.fromJson,
        {
          'pendingQuotes': 1,
          'sentQuotes': 1,
          'pendingCrew': 1,
          'openJobs': 1,
          'claimedJobs': 0,
          'inProgressJobs': 0,
          'doneToday': 2,
          'cancelledToday': 0,
          'revenueToday': 110,
          'paymentIssues': 1,
        },
      ),
      'AdminDashboard': (
        AdminDashboard.fromJson,
        {
          'serverTime': '2026-01-05T12:00:00Z',
          'counts': {'pendingQuotes': 1, 'openJobs': 1},
          'pendingQuotes': [quoteJson],
          'liveJobs': [
            adminJob({'status': 'open'}),
          ],
          'pendingCrew': [crewMemberJson],
          'paymentIssues': [adminJob()],
        },
      ),
    };

void main() {
  group('json readers', () {
    test('str / strOrNull', () {
      expect(str('a'), 'a');
      expect(str(null), '');
      expect(str(5), '');
      expect(str(null, 'x'), 'x');
      expect(strOrNull('a'), 'a');
      expect(strOrNull(''), '');
      expect(strOrNull(3), isNull);
    });

    test('intOf / intOrNull', () {
      expect(intOf(45), 45);
      expect(intOf(45.0), 45);
      expect(intOf('45'), 0);
      expect(intOf(null, 7), 7);
      expect(intOf(double.nan), 0);
      expect(intOf(double.infinity), 0);
      expect(intOrNull(0), 0);
      expect(intOrNull(null), isNull);
      expect(intOrNull(true), isNull);
    });

    test('boolOf is true only for true', () {
      expect(boolOf(true), isTrue);
      expect(boolOf(false), isFalse);
      expect(boolOf('true'), isFalse);
      expect(boolOf(1), isFalse);
      expect(boolOf(null), isFalse);
    });

    test('dateOrNull parses to local time', () {
      final d = dateOrNull('2026-01-05T10:00:00Z')!;
      expect(d.isUtc, isFalse);
      expect(d.toUtc(), DateTime.utc(2026, 1, 5, 10));
      expect(dateOrNull('yesterday'), isNull);
      expect(dateOrNull(''), isNull);
      expect(dateOrNull(1736071200), isNull);
      expect(dateOrNull(null), isNull);
    });

    test('mapOf', () {
      expect(mapOf({'a': 1}), {'a': 1});
      expect(mapOf(<Object?, Object?>{'a': 1, 2: 'b'}), {'a': 1});
      expect(mapOf('x'), isEmpty);
      expect(mapOf(null), isEmpty);
    });

    test('listOf skips non-object items', () {
      final ids = listOf([
        {'id': 'a'},
        'junk',
        null,
        7,
        {'id': 'b'},
      ], (m) => str(m['id']));
      expect(ids, ['a', 'b']);
      expect(listOf('nope', (m) => m), isEmpty);
      expect(listOf(null, (m) => m), isEmpty);
    });

    test('strList keeps strings only', () {
      expect(strList(['a', 1, null, 'b']), ['a', 'b']);
      expect(strList({'a': 1}), isEmpty);
    });

    test('enumOf matches by name', () {
      expect(
        enumOf(JobStatus.values, 'inProgress', JobStatus.unknown),
        JobStatus.inProgress,
      );
      expect(
        enumOf(JobStatus.values, 'InProgress', JobStatus.unknown),
        JobStatus.unknown,
      );
      expect(enumOf(JobStatus.values, 3, JobStatus.unknown), JobStatus.unknown);
      expect(enumOf(JobStatus.values, null, JobStatus.open), JobStatus.open);
    });
  });

  group('defaults', () {
    test('every model parses {}', () {
      for (final MapEntry(key: name, value: (parse, _)) in samples.entries) {
        expect(() => parse(const {}), returnsNormally, reason: name);
      }
    });

    test('AuthUser', () {
      final u = AuthUser.fromJson(const {});
      expect([
        u.id,
        u.name,
        u.email,
        u.role,
        u.initials,
        u.color,
        u.phone,
      ], everyElement(''));
      expect(u.linkedId, isNull);
      expect(u.crewStatus, isNull);
      expect(u.firstName, '');
      expect(AuthResult.fromJson(const {}).token, '');
      expect(AuthResult.fromJson(const {}).user.id, '');
    });

    test('Job', () {
      final j = Job.fromJson(const {});
      expect(j.id, '');
      expect(j.shovel, isFalse);
      expect([j.price, j.shovelPrice, j.total, j.crewPay], everyElement(0));
      expect(j.status, JobStatus.unknown);
      expect([
        j.crewId,
        j.crewName,
        j.crewInitials,
        j.crewColor,
      ], everyElement(''));
      expect(j.cancelledBy, '');
      expect(j.requestedAt, isNull);
      expect(j.payment.mode, PaymentMode.unknown);
      expect(j.payment.status, PaymentStatus.unknown);
      expect(j.payment.error, isNull);
      expect(j.paidOut, isFalse);
      expect(j.isActive, isFalse);
      expect(j.canCustomerCancel, isFalse);
      expect(j.duration, isNull);
      expect(j.stepIndex, 0);
    });

    test('Property and Quote', () {
      final p = Property.fromJson(const {});
      expect(p.status, PropertyStatus.unknown);
      expect(p.price, isNull);
      expect(p.crewPay, isNull);
      expect(p.activeJob, isNull);
      expect(p.createdAt, isNull);
      expect([p.quoteId, p.customerId, p.customerName], everyElement(''));

      final q = Quote.fromJson(const {});
      expect(q.status, QuoteStatus.unknown);
      expect(q.price, isNull);
      expect(q.crewPay, isNull);
      expect(q.sentAt, isNull);
    });

    test('Settings, Billing and the admin aggregates', () {
      final s = Settings.fromJson(const {});
      expect([
        s.shovelPrice,
        s.crewShovelBonus,
        s.openJobExpiryHours,
      ], everyElement(0));
      expect(s.currency, '');
      expect(s.paymentsMode, PaymentMode.unknown);

      final b = Billing.fromJson(const {});
      expect(b.mode, PaymentMode.unknown);
      expect(b.card, isNull);
      expect(b.pendingSetup, isFalse);
      expect(b.balanceDue, 0);
      expect(b.charges, isEmpty);
      expect(b.needsCard, isFalse);

      final c = CustomerDetail.fromJson(const {});
      expect(c.customer.id, '');
      expect(c.customer.addresses, isEmpty);
      expect(c.card, isNull);
      expect(c.properties, isEmpty);
      expect(c.jobs, isEmpty);
      expect([c.billed, c.outstanding], everyElement(0));

      final pay = CrewPay.fromJson(const {});
      expect(pay.unpaidJobs, isEmpty);
      expect(pay.payouts, isEmpty);
      expect(pay.unpaidTotal, 0);

      expect(CrewMember.fromJson(const {}).status, CrewStatus.unknown);
      expect(Charge.fromJson(const {}).status, PaymentStatus.unknown);

      final d = AdminDashboard.fromJson(const {});
      expect(d.serverTime, isNull);
      expect(d.counts.openJobs, 0);
      expect(d.pendingQuotes, isEmpty);
      expect(d.liveJobs, isEmpty);
      expect(d.pendingCrew, isEmpty);
      expect(d.paymentIssues, isEmpty);
    });
  });

  test('wrong types never throw', () {
    const garbage = <Object?>[
      null,
      42,
      3.9,
      'nope',
      true,
      [1, 'a', null, true],
      {'x': 1},
      [
        {'id': 7, 'status': [], 'payment': 'x', 'activeJob': 3, 'card': 'c'},
      ],
      {
        'status': 5,
        'mode': 1,
        'card': 'x',
        'totals': [],
        'user': 'u',
        'payment': [1],
        'billed': 'lots',
      },
    ];
    for (final MapEntry(key: name, value: (parse, sample)) in samples.entries) {
      for (final g in garbage) {
        final allWrong = {for (final k in sample.keys) k: g};
        expect(() => parse(allWrong), returnsNormally, reason: '$name <- $g');
        // One wrong field at a time, the rest valid.
        for (final k in sample.keys) {
          expect(
            () => parse({...sample, k: g}),
            returnsNormally,
            reason: '$name.$k <- $g',
          );
        }
      }
    }
  });

  test('a wrongly-typed field falls back without spoiling its neighbours', () {
    final j = Job.fromJson(
      adminJob({
        'price': '45',
        'shovel': 'yes',
        'requestedAt': 12345,
        'payment': 'captured',
        'crewName': null,
      }),
    );
    expect(j.price, 0);
    expect(j.shovel, isFalse);
    expect(j.requestedAt, isNull);
    expect(j.payment.status, PaymentStatus.unknown);
    expect(j.crewName, '');
    expect(j.total, 65);
    expect(j.status, JobStatus.done);
  });

  group('enums', () {
    test('known values', () {
      expect(
        Property.fromJson({'status': 'quoteRequested'}).status,
        PropertyStatus.quoteRequested,
      );
      expect(
        Quote.fromJson({'status': 'accepted'}).status,
        QuoteStatus.accepted,
      );
      expect(
        Job.fromJson({'status': 'inProgress'}).status,
        JobStatus.inProgress,
      );
      expect(
        PaymentInfo.fromJson({'mode': 'manual', 'status': 'none'}).status,
        PaymentStatus.none,
      );
      expect(
        CrewMember.fromJson({'status': 'rejected'}).status,
        CrewStatus.rejected,
      );
    });

    test('unknown values map to unknown', () {
      expect(
        Property.fromJson({'status': 'archived'}).status,
        PropertyStatus.unknown,
      );
      expect(Quote.fromJson({'status': 'expired'}).status, QuoteStatus.unknown);
      expect(Job.fromJson({'status': 'paused'}).status, JobStatus.unknown);
      final p = PaymentInfo.fromJson({'mode': 'paypal', 'status': 'refunded'});
      expect(p.mode, PaymentMode.unknown);
      expect(p.status, PaymentStatus.unknown);
      expect(
        CrewMember.fromJson({'status': 'banned'}).status,
        CrewStatus.unknown,
      );
      expect(
        Settings.fromJson({'paymentsMode': 'barter'}).paymentsMode,
        PaymentMode.unknown,
      );
      expect(
        AuthUser.fromJson({'crewStatus': 'suspended'}).crewStatus,
        CrewStatus.unknown,
      );
    });
  });

  group('AuthUser', () {
    test('crew account', () {
      final u = AuthUser.fromJson(samples['AuthUser']!.$2);
      expect(u.id, 'user_marcus');
      expect(u.role, 'crew');
      expect(u.linkedId, 'crew_marcus');
      expect(u.crewStatus, CrewStatus.active);
      expect(u.phone, '(807) 555-0111');
      expect(u.firstName, 'Marcus');
    });

    test('admin has no linkedId or crewStatus', () {
      final u = AuthUser.fromJson({
        'id': 'user_lia',
        'name': 'Lia Robinson',
        'role': 'admin',
        'linkedId': null,
        'crewStatus': null,
      });
      expect(u.linkedId, isNull);
      expect(u.crewStatus, isNull);
    });

    test('firstName', () {
      String first(String name) => AuthUser.fromJson({'name': name}).firstName;
      expect(first('Sarah Mitchell'), 'Sarah');
      expect(first('  Anna   Tomlinson '), 'Anna');
      expect(first('Cher'), 'Cher');
      expect(first('   '), '');
    });
  });

  group('Job', () {
    test('admin view', () {
      final j = Job.fromJson(adminJob());
      expect(j.id, 'job_1');
      expect(j.propertyName, 'Maple Street home');
      expect(j.customerPhone, '(807) 555-0142');
      expect(j.shovel, isTrue);
      expect([j.price, j.shovelPrice, j.total, j.crewPay], [45, 20, 65, 35]);
      expect(j.status, JobStatus.done);
      expect(j.crewId, 'crew_marcus');
      expect(j.crewColor, 'teal');
      expect(j.crewNote, 'Salted the steps');
      expect(j.source, 'customer');
      expect(j.requestedAt!.toUtc(), DateTime.utc(2026, 1, 5, 10));
      expect(j.cancelledAt, isNull);
      expect(j.cancelledBy, '');
      expect(j.payment.mode, PaymentMode.stripe);
      expect(j.payment.status, PaymentStatus.captured);
      expect(j.payment.error, isNull);
      expect(
        j.payment.capturedAt!.toUtc(),
        DateTime.utc(2026, 1, 5, 11, 17, 2),
      );
      expect(j.payment.holdExpiresAt, isNotNull);
      expect(j.paidOut, isTrue);
    });

    test('crew view omits the money the customer pays', () {
      final json = adminJob({'status': 'open', 'customerName': ''})
        ..remove('price')
        ..remove('shovelPrice')
        ..remove('total')
        ..remove('payment');
      final j = Job.fromJson(json);
      expect([j.price, j.shovelPrice, j.total], everyElement(0));
      expect(j.crewPay, 35);
      expect(j.payment.status, PaymentStatus.unknown);
      expect(j.customerName, '');
    });

    test('customer view omits crewPay, paidOut and crewId', () {
      final json = adminJob()
        ..remove('crewPay')
        ..remove('paidOut')
        ..remove('crewId');
      final j = Job.fromJson(json);
      expect(j.crewPay, 0);
      expect(j.paidOut, isFalse);
      expect(j.crewId, '');
      expect(j.crewName, 'Marcus Reid');
      expect(j.total, 65);
    });

    test('failed payment carries the error', () {
      final j = Job.fromJson(
        adminJob({
          'payment': {
            'mode': 'stripe',
            'status': 'failed',
            'error': 'Your card was declined.',
            'holdExpiresAt': null,
            'capturedAt': null,
          },
        }),
      );
      expect(j.payment.status, PaymentStatus.failed);
      expect(j.payment.error, 'Your card was declined.');
      expect(j.payment.capturedAt, isNull);
    });

    test('isActive and canCustomerCancel', () {
      Job at(String status) => Job.fromJson({'status': status});
      expect(at('open').isActive, isTrue);
      expect(at('claimed').isActive, isTrue);
      expect(at('inProgress').isActive, isTrue);
      expect(at('done').isActive, isFalse);
      expect(at('cancelled').isActive, isFalse);

      expect(at('open').canCustomerCancel, isTrue);
      expect(at('claimed').canCustomerCancel, isTrue);
      expect(at('inProgress').canCustomerCancel, isFalse);
      expect(at('done').canCustomerCancel, isFalse);
      expect(at('cancelled').canCustomerCancel, isFalse);
    });

    test('duration is completedAt - startedAt', () {
      expect(Job.fromJson(adminJob()).duration, const Duration(minutes: 47));
      expect(Job.fromJson(adminJob({'startedAt': null})).duration, isNull);
      expect(Job.fromJson(adminJob({'completedAt': null})).duration, isNull);
      expect(
        Job.fromJson(
          adminJob({'completedAt': '2026-01-05T10:00:00Z'}),
        ).duration,
        Duration.zero,
      );
    });

    test('stepIndex', () {
      int step(Map<String, dynamic> j) => Job.fromJson(j).stepIndex;
      expect(step({'status': 'open'}), 0);
      expect(step({'status': 'claimed'}), 1);
      expect(step({'status': 'inProgress'}), 2);
      expect(step({'status': 'done'}), 3);
      // A cancelled job reports how far it got.
      expect(step({'status': 'cancelled'}), 0);
      expect(
        step({'status': 'cancelled', 'claimedAt': '2026-01-05T10:04:00Z'}),
        1,
      );
      expect(
        step({
          'status': 'cancelled',
          'claimedAt': '2026-01-05T10:04:00Z',
          'startedAt': '2026-01-05T10:30:00Z',
        }),
        2,
      );
    });
  });

  group('Property', () {
    test('customer view without a job', () {
      final json = adminProperty()
        ..remove('customerId')
        ..remove('customerName')
        ..remove('crewPay');
      final p = Property.fromJson(json);
      expect(p.id, 'prop_maple');
      expect(p.status, PropertyStatus.active);
      expect(p.price, 45);
      expect(p.quoteId, 'quote_maple');
      expect(p.createdAt!.toUtc(), DateTime.utc(2025, 11, 20, 15));
      expect(p.activeJob, isNull);
      expect(p.customerId, '');
      expect(p.customerName, '');
      expect(p.crewPay, isNull);
    });

    test('nested activeJob', () {
      final p = Property.fromJson(
        adminProperty({
          'activeJob': adminJob({'id': 'job_live', 'status': 'claimed'}),
        }),
      );
      expect(p.activeJob, isNotNull);
      expect(p.activeJob!.id, 'job_live');
      expect(p.activeJob!.status, JobStatus.claimed);
      expect(p.activeJob!.isActive, isTrue);
      expect(p.activeJob!.payment.status, PaymentStatus.captured);
      expect(p.customerName, 'Sarah Mitchell');
      expect(p.crewPay, 25);
    });

    test('price is null until quoted', () {
      final p = Property.fromJson(
        adminProperty({
          'status': 'quoteRequested',
          'price': null,
          'crewPay': null,
        }),
      );
      expect(p.status, PropertyStatus.quoteRequested);
      expect(p.price, isNull);
      expect(p.crewPay, isNull);
    });
  });

  test('Quote', () {
    final q = Quote.fromJson(quoteJson);
    expect(q.id, 'quote_birch');
    expect(q.propertyId, 'prop_birch');
    expect(q.status, QuoteStatus.sent);
    expect(q.price, 60);
    expect(q.crewPay, 35);
    expect(q.sentAt!.toUtc(), DateTime.utc(2026, 1, 3, 9));
    expect(q.decidedAt, isNull);
    expect(q.customerInitials, 'PL');
    expect(q.customerColor, 'paper');
    expect(q.illustration, 'bungalow');

    final pending = Quote.fromJson({
      ...quoteJson,
      'status': 'pending',
      'price': null,
      'crewPay': null,
    });
    expect(pending.price, isNull);
    expect(pending.crewPay, isNull);
  });

  group('Billing', () {
    test('card null: stripe mode needs a card, manual does not', () {
      final stripe = Billing.fromJson({'mode': 'stripe', 'card': null});
      expect(stripe.card, isNull);
      expect(stripe.needsCard, isTrue);

      final manual = Billing.fromJson({'mode': 'manual', 'card': null});
      expect(manual.card, isNull);
      expect(manual.needsCard, isFalse);
    });

    test('card object and charges', () {
      final b = Billing.fromJson({
        'mode': 'stripe',
        'card': cardJson,
        'pendingSetup': true,
        'balanceDue': 45,
        'charges': [
          {
            'jobId': 'job_2',
            'propertyName': 'Maple Street home',
            'date': '2026-01-05T11:17:00Z',
            'total': 45,
            'shovel': false,
            'status': 'failed',
          },
          {
            'jobId': 'job_1',
            'propertyName': 'Maple Street home',
            'date': '2025-12-29T11:17:00Z',
            'total': 65,
            'shovel': true,
            'status': 'captured',
          },
        ],
      });
      expect(b.needsCard, isFalse);
      expect(b.card!.brand, 'visa');
      expect(b.card!.last4, '4242');
      expect(b.card!.expMonth, 4);
      expect(b.card!.expYear, 2030);
      expect(b.card!.updatedAt, isNotNull);
      expect(b.pendingSetup, isTrue);
      expect(b.balanceDue, 45);
      expect(b.charges.map((c) => c.jobId), ['job_2', 'job_1']);
      expect(b.charges.first.status, PaymentStatus.failed);
      expect(b.charges.first.shovel, isFalse);
      expect(b.charges.last.total, 65);
      expect(b.charges.last.date!.toUtc(), DateTime.utc(2025, 12, 29, 11, 17));
    });
  });

  test('Customer and CustomerDetail', () {
    final c = Customer.fromJson(samples['Customer']!.$2);
    expect(c.name, 'Sarah Mitchell');
    expect(c.propertyCount, 2);
    expect(c.activeProperties, 1);
    expect(c.jobCount, 3);
    expect(c.hasCard, isTrue);
    expect(c.lastJobAt, isNotNull);
    expect(c.addresses, hasLength(2));

    final d = CustomerDetail.fromJson(samples['CustomerDetail']!.$2);
    expect(d.customer.id, 'cust_sarah');
    expect(d.customer.addresses, ['412 Maple St, Thunder Bay, ON']);
    expect(d.card!.last4, '4242');
    expect(d.properties.single.crewPay, 25);
    expect(d.jobs.single.paidOut, isTrue);
    expect(d.billed, 155);
    expect(d.outstanding, 45);
  });

  test('CrewMember, CrewPay and Payout', () {
    final m = CrewMember.fromJson(crewMemberJson);
    expect(m.userId, 'user_marcus');
    expect(m.status, CrewStatus.active);
    expect(m.appliedAt, isNotNull);
    expect(
      [m.jobsThisWeek, m.earnedThisWeek, m.unpaidTotal, m.unpaidJobs],
      [3, 95, 60, 2],
    );

    final pay = CrewPay.fromJson(samples['CrewPay']!.$2);
    expect(pay.crewId, 'crew_marcus');
    expect(pay.name, 'Marcus Reid');
    expect([pay.earnedToday, pay.jobsToday], [35, 1]);
    expect([pay.earnedThisWeek, pay.jobsThisWeek], [95, 3]);
    expect(pay.earnedAllTime, 410);
    expect(pay.unpaidTotal, 60);
    expect(pay.unpaidJobs.single.crewPay, 35);
    final payout = pay.payouts.single;
    expect(payout.id, 'payout_1');
    expect(payout.amount, 25);
    expect(payout.jobCount, 1);
    expect(payout.note, 'e-transfer');
    expect(payout.paidAt!.toUtc(), DateTime.utc(2025, 12, 28, 18));
  });

  test('role-shaped Settings', () {
    final customer = Settings.fromJson({
      'shovelPrice': 20,
      'currency': 'cad',
      'paymentsMode': 'stripe',
    });
    expect(customer.shovelPrice, 20);
    expect(customer.crewShovelBonus, 0);
    expect(customer.paymentsMode, PaymentMode.stripe);

    final crew = Settings.fromJson({'crewShovelBonus': 10, 'currency': 'cad'});
    expect(crew.crewShovelBonus, 10);
    expect(crew.shovelPrice, 0);
    expect(crew.paymentsMode, PaymentMode.unknown);

    final admin = Settings.fromJson(samples['Settings']!.$2);
    expect(admin.openJobExpiryHours, 48);
    expect(admin.currency, 'cad');
    expect(admin.paymentsMode, PaymentMode.manual);
  });

  test('AdminDashboard', () {
    final d = AdminDashboard.fromJson({
      ...samples['AdminDashboard']!.$2,
      'counts': samples['DashboardCounts']!.$2,
    });
    expect(d.serverTime!.toUtc(), DateTime.utc(2026, 1, 5, 12));
    expect(d.counts.pendingQuotes, 1);
    expect(d.counts.sentQuotes, 1);
    expect(d.counts.pendingCrew, 1);
    expect(d.counts.openJobs, 1);
    expect(d.counts.doneToday, 2);
    expect(d.counts.revenueToday, 110);
    expect(d.counts.paymentIssues, 1);
    expect(d.pendingQuotes.single.id, 'quote_birch');
    expect(d.liveJobs.single.status, JobStatus.open);
    expect(d.pendingCrew.single.id, 'crew_marcus');
    expect(d.paymentIssues.single.id, 'job_1');
  });
}

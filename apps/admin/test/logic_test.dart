// Unit tests for the admin app's pure helpers.

import 'package:flutter_test/flutter_test.dart';
import 'package:redefine_admin/nav.dart';
import 'package:redefine_admin/screens/customer_detail.dart';
import 'package:redefine_admin/screens/customers.dart';
import 'package:redefine_admin/screens/job_detail.dart';
import 'package:redefine_admin/screens/jobs.dart';
import 'package:redefine_admin/screens/settings.dart';
import 'package:redefine_admin/widgets/common.dart';
import 'package:redefine_admin/widgets/job_widgets.dart';
import 'package:redefine_admin/widgets/price_fields.dart';
import 'package:redefine_ui/redefine_ui.dart';

final _now = DateTime(2026, 1, 15, 10, 30);

String _iso(Duration ago) => _now.subtract(ago).toUtc().toIso8601String();

Job _job(
  String id, {
  String status = 'open',
  Duration? requested,
  Duration? claimed,
  Duration? started,
  Duration? completed,
  Duration? cancelled,
  String payment = 'none',
  int total = 45,
  bool shovel = false,
  String crewName = '',
  String cancelledBy = '',
  String source = 'customer',
}) => Job.fromJson({
  'id': id,
  'status': status,
  'shovel': shovel,
  'total': total,
  'crewName': crewName,
  'source': source,
  'cancelledBy': cancelledBy,
  'requestedAt': requested == null ? null : _iso(requested),
  'claimedAt': claimed == null ? null : _iso(claimed),
  'startedAt': started == null ? null : _iso(started),
  'completedAt': completed == null ? null : _iso(completed),
  'cancelledAt': cancelled == null ? null : _iso(cancelled),
  'payment': {'mode': 'manual', 'status': payment},
});

void main() {
  group('validatePricing', () {
    test('accepts whole dollars with crew pay up to the price', () {
      expect(validatePricing('45', '25'), (price: null, crewPay: null));
      expect(validatePricing(' 45 ', ' 0 '), (price: null, crewPay: null));
      expect(validatePricing('1', '1'), (price: null, crewPay: null));
      expect(validatePricing('10000', '10000'), (price: null, crewPay: null));
    });

    test('requires both fields', () {
      final errors = validatePricing('', '  ');
      expect(errors.price, 'Enter the price per plough.');
      expect(errors.crewPay, 'Enter the crew pay per plough.');
    });

    test('keeps the price within 1..10000', () {
      expect(validatePricing('0', '0').price, contains(r'$1 to $10,000'));
      expect(validatePricing('10001', '0').price, contains(r'$1 to $10,000'));
    });

    test('rejects anything but digits', () {
      for (final bad in ['4.5', '-5', '1e3', 'forty', '+45', '4 5']) {
        expect(validatePricing(bad, '0').price, isNotNull, reason: bad);
        expect(validatePricing('45', bad).crewPay, isNotNull, reason: bad);
      }
    });

    test('crew pay may not exceed the price', () {
      expect(validatePricing('45', '46').crewPay, "Crew pay can't be more than the price.");
      // With no valid price to compare against, only the price is flagged.
      expect(validatePricing('', '46'), (price: 'Enter the price per plough.', crewPay: null));
    });

    test('parsePricing gives the numbers only when both are valid', () {
      expect(parsePricing('45', '25'), (price: 45, crewPay: 25));
      expect(parsePricing('045', '0'), (price: 45, crewPay: 0));
      expect(parsePricing('45', '50'), isNull);
      expect(parsePricing('', '25'), isNull);
    });
  });

  group('validateSettings', () {
    test('accepts the documented ranges', () {
      const ok = (shovelPrice: null, crewShovelBonus: null, expiryHours: null);
      expect(validateSettings('20', '10', '48'), ok);
      expect(validateSettings('0', '0', '1'), ok);
      expect(validateSettings('1000', '1000', '120'), ok);
      expect(parseSettings('20', '10', '48'), (
        shovelPrice: 20,
        crewShovelBonus: 10,
        expiryHours: 48,
      ));
    });

    test('flags each field on its own', () {
      expect(validateSettings('1001', '0', '48').shovelPrice, isNotNull);
      expect(validateSettings('20', '21', '48').crewShovelBonus, contains("can't be more"));
      expect(validateSettings('20', '10', '0').expiryHours, isNotNull);
      expect(validateSettings('20', '10', '121').expiryHours, isNotNull);
      expect(validateSettings('', '', '').shovelPrice, isNotNull);
      expect(
        validateSettings('2.5', 'x', '-1'),
        isNot((shovelPrice: null, crewShovelBonus: null, expiryHours: null)),
      );
      expect(parseSettings('20', '21', '48'), isNull);
    });
  });

  group('groupLive', () {
    test('splits by stage, longest-standing first, and drops finished jobs', () {
      final groups = groupLive([
        _job('new', requested: const Duration(minutes: 2)),
        _job('old', requested: const Duration(minutes: 40)),
        _job(
          'claimed',
          status: 'claimed',
          requested: const Duration(hours: 1),
          claimed: const Duration(minutes: 5),
        ),
        _job('working-late', status: 'inProgress', started: const Duration(minutes: 3)),
        _job('working-early', status: 'inProgress', started: const Duration(minutes: 30)),
        _job('done', status: 'done'),
        _job('cancelled', status: 'cancelled'),
      ]);
      expect(groups.waiting.map((j) => j.id), ['old', 'new']);
      expect(groups.assigned.map((j) => j.id), ['claimed']);
      expect(groups.inProgress.map((j) => j.id), ['working-early', 'working-late']);
    });

    test('jobs without a timestamp go last', () {
      final groups = groupLive([_job('unknown'), _job('known', requested: Duration.zero)]);
      expect(groups.waiting.map((j) => j.id), ['known', 'unknown']);
      final none = groupLive(const []);
      expect([...none.waiting, ...none.assigned, ...none.inProgress], isEmpty);
    });
  });

  test('needsPayment is true for due and failed payments only', () {
    final expected = {
      'none': false,
      'authorized': false,
      'captured': false,
      'released': false,
      'failed': true,
      'due': true,
      'paid': false,
    };
    for (final MapEntry(key: status, value: owing) in expected.entries) {
      expect(
        needsPayment(_job('j', status: 'done', payment: status)),
        owing,
        reason: status,
      );
    }
    // The crew's view of a job carries no payment at all.
    expect(needsPayment(Job.fromJson(const {'id': 'j', 'status': 'done'})), isFalse);
  });

  group('paymentExplanation', () {
    test('a live job says what is still to come', () {
      expect(paymentExplanation(_job('j')), 'Nothing is billed until the job is done.');
      expect(
        paymentExplanation(_job('j', status: 'claimed', payment: 'authorized')),
        "A hold of \$45 is on the customer's card. It is charged when the job is done.",
      );
    });

    test('a cancelled job is never said to be billed or charged later', () {
      expect(
        paymentExplanation(_job('j', status: 'cancelled')),
        'The job was cancelled. Nothing was billed.',
      );
      expect(
        paymentExplanation(_job('j', status: 'cancelled', payment: 'authorized')),
        "The job was cancelled. The hold of \$45 on the customer's card is being released.",
      );
      expect(
        paymentExplanation(_job('j', status: 'cancelled', payment: 'released')),
        'The hold was released. Nothing was charged.',
      );
    });

    test('a finished job says where the money stands', () {
      expect(
        paymentExplanation(_job('j', status: 'done', payment: 'authorized')),
        "The job is done. The charge of \$45 to the customer's card is being processed.",
      );
      expect(paymentExplanation(_job('j', status: 'done', payment: 'captured')), r'Charged $45.');
      expect(
        paymentExplanation(_job('j', status: 'done', payment: 'failed')),
        r'The charge of $45 did not go through.',
      );
      expect(
        paymentExplanation(_job('j', status: 'done', payment: 'due')),
        r'$45 is due from the customer.',
      );
      expect(
        paymentExplanation(_job('j', status: 'done', payment: 'paid')),
        'Marked as paid by the office.',
      );
    });
  });

  test('jobStillChanging: live jobs, and finished ones whose hold is not settled', () {
    for (final live in ['open', 'claimed', 'inProgress']) {
      expect(jobStillChanging(_job('j', status: live)), isTrue, reason: live);
    }
    expect(jobStillChanging(_job('j', status: 'cancelled', payment: 'authorized')), isTrue);
    expect(jobStillChanging(_job('j', status: 'done', payment: 'authorized')), isTrue);
    for (final settled in ['none', 'released', 'captured', 'failed', 'due', 'paid']) {
      expect(jobStillChanging(_job('j', status: 'done', payment: settled)), isFalse);
      expect(jobStillChanging(_job('j', status: 'cancelled', payment: settled)), isFalse);
    }
  });

  test('waitingTooLong flags open requests older than 15 minutes', () {
    expect(waitingTooLong(_job('j', requested: const Duration(minutes: 16)), now: _now), isTrue);
    expect(waitingTooLong(_job('j', requested: const Duration(minutes: 15)), now: _now), isFalse);
    expect(
      waitingTooLong(
        _job('j', status: 'claimed', requested: const Duration(hours: 2)),
        now: _now,
      ),
      isFalse,
    );
    expect(waitingTooLong(_job('j'), now: _now), isFalse);
  });

  test('summarizeJobs counts by outcome and totals the finished jobs', () {
    final totals = summarizeJobs([
      _job('a'),
      _job('b', status: 'done', total: 45),
      _job('c', status: 'done', total: 75),
      _job('d', status: 'cancelled', total: 60),
      _job('e', status: 'inProgress', total: 55),
    ]);
    expect(totals, (requested: 5, done: 2, cancelled: 1, billed: 120));
    expect(summarizeJobs(const []), (requested: 0, done: 0, cancelled: 0, billed: 0));
  });

  test('filterHistory narrows a list on the client', () {
    final jobs = [
      _job('open'),
      _job('paid', status: 'done', payment: 'paid'),
      _job('due', status: 'done', payment: 'due'),
      _job('failed', status: 'done', payment: 'failed'),
      _job('cancelled', status: 'cancelled', payment: 'released'),
    ];
    List<String> ids(HistoryFilter filter) => [for (final j in filterHistory(jobs, filter)) j.id];
    expect(ids(HistoryFilter.all), ['open', 'paid', 'due', 'failed', 'cancelled']);
    expect(ids(HistoryFilter.done), ['paid', 'due', 'failed']);
    expect(ids(HistoryFilter.cancelled), ['cancelled']);
    expect(ids(HistoryFilter.needsPayment), ['due', 'failed']);
  });

  group('jobStatusLine', () {
    test('keeps time for live jobs', () {
      expect(
        jobStatusLine(_job('j', requested: const Duration(minutes: 6)), now: _now),
        'Waiting for crew · 6 min',
      );
      expect(
        jobStatusLine(_job('j', requested: const Duration(minutes: 6), shovel: true), now: _now),
        'Waiting for crew · 6 min · + shovel',
      );
      expect(
        jobStatusLine(
          _job(
            'j',
            status: 'claimed',
            claimed: const Duration(minutes: 4),
            crewName: 'Marcus Reid',
          ),
          now: _now,
        ),
        'Marcus · accepted 4 min ago',
      );
      expect(
        jobStatusLine(
          _job(
            'j',
            status: 'inProgress',
            started: const Duration(minutes: 18),
            crewName: 'Marcus Reid',
          ),
          now: _now,
        ),
        'Marcus · in progress 18 min',
      );
    });

    test('never shows negative time when the server clock is ahead', () {
      expect(
        jobStatusLine(_job('j', requested: const Duration(minutes: -3)), now: _now),
        'Waiting for crew · 0 min',
      );
    });

    test('finished jobs say how they ended', () {
      final done = jobStatusLine(
        _job('j', status: 'done', completed: const Duration(days: 400), total: 65),
        now: _now,
      );
      expect(done, startsWith('Done · '));
      expect(done, endsWith(r' · $65'));
      expect(jobStatusLine(_job('j', status: 'cancelled'), now: _now), 'Cancelled');
      expect(jobStatusLine(_job('j', status: 'claimed'), now: _now), 'Crew · accepted');
    });
  });

  group('timelineSteps', () {
    List<(String, RStepState)> shape(Job job) => [
      for (final step in timelineSteps(job, now: _now)) (step.title, step.state),
    ];

    test('an open job waits on the first step', () {
      final steps = timelineSteps(_job('j', requested: const Duration(minutes: 5)), now: _now);
      expect(steps.map((s) => s.state), [
        RStepState.current,
        RStepState.upcoming,
        RStepState.upcoming,
        RStepState.upcoming,
      ]);
      expect(steps[0].subtitle, endsWith('by the customer'));
      expect(steps[1].subtitle, 'Open to all approved crew');
    });

    test('a job in progress shows the crew member and how long they have been at it', () {
      final steps = timelineSteps(
        _job(
          'j',
          status: 'inProgress',
          requested: const Duration(hours: 1),
          claimed: const Duration(minutes: 50),
          started: const Duration(minutes: 18),
          crewName: 'Marcus Reid',
          source: 'admin',
        ),
        now: _now,
      );
      expect(steps.map((s) => s.state), [
        RStepState.done,
        RStepState.done,
        RStepState.current,
        RStepState.upcoming,
      ]);
      expect(steps[0].subtitle, endsWith('by the office'));
      expect(steps[1].subtitle, startsWith('Marcus Reid · '));
      expect(steps[2].subtitle, endsWith('for 18 min'));
      expect(steps[3].subtitle, isNull);
    });

    test('a finished job is all done and says how long it took', () {
      final job = _job(
        'j',
        status: 'done',
        requested: const Duration(hours: 3),
        claimed: const Duration(hours: 2, minutes: 50),
        started: const Duration(hours: 2),
        completed: const Duration(hours: 1, minutes: 13),
        crewName: 'Marcus Reid',
      );
      expect(shape(job).map((s) => s.$2), everyElement(RStepState.done));
      expect(timelineSteps(job, now: _now).last.subtitle, endsWith('took 47 min'));
    });

    test('a cancelled job lists what it reached, then who cancelled it', () {
      expect(
        shape(
          _job(
            'j',
            status: 'cancelled',
            requested: const Duration(hours: 2),
            cancelled: const Duration(hours: 1),
            cancelledBy: 'system',
          ),
        ),
        [('Requested', RStepState.done), ('Cancelled', RStepState.current)],
      );
      final claimedThenCancelled = timelineSteps(
        _job(
          'j',
          status: 'cancelled',
          requested: const Duration(hours: 2),
          claimed: const Duration(minutes: 90),
          cancelled: const Duration(hours: 1),
          cancelledBy: 'admin',
          crewName: 'Jordan Park',
        ),
        now: _now,
      );
      expect(claimedThenCancelled.map((s) => s.title), ['Requested', 'Crew assigned', 'Cancelled']);
      expect(claimedThenCancelled.last.subtitle, endsWith('by the office'));
    });
  });

  test('cancelledByLabel names who cancelled', () {
    expect(cancelledByLabel('customer'), 'by the customer');
    expect(cancelledByLabel('admin'), 'by the office');
    expect(cancelledByLabel('system'), contains('no crew accepted'));
    expect(cancelledByLabel(''), '');
  });

  group('matchesCustomer', () {
    final sarah = Customer.fromJson(const {
      'name': 'Sarah Mitchell',
      'email': 'sarah.m@gmail.com',
      'phone': '(807) 555-0142',
      'addresses': ['412 Maple St, Thunder Bay, ON', '88 Lakeside Rd'],
    });

    test('an empty search matches everyone', () {
      expect(matchesCustomer(sarah, ''), isTrue);
      expect(matchesCustomer(sarah, '   '), isTrue);
    });

    test('matches name, email, phone and address, whatever the case', () {
      for (final query in ['sarah', 'MITCHELL', 'gmail', 'lakeside', 'maple st', '555-0142']) {
        expect(matchesCustomer(sarah, query), isTrue, reason: query);
      }
    });

    test('every word must match somewhere', () {
      expect(matchesCustomer(sarah, 'sarah lakeside'), isTrue);
      expect(matchesCustomer(sarah, 'sarah cedar'), isFalse);
    });

    test('a phone number matches however it is typed', () {
      expect(matchesCustomer(sarah, '8075550142'), isTrue);
      expect(matchesCustomer(sarah, '807-555-0142'), isTrue);
      expect(matchesCustomer(sarah, '8075559999'), isFalse);
    });
  });

  test('cardLabel names the brand, last digits and expiry', () {
    CardInfo card(Map<String, dynamic> json) => CardInfo.fromJson(json);
    expect(
      cardLabel(card({'brand': 'visa', 'last4': '4242', 'expMonth': 8, 'expYear': 2027})),
      'Visa ending 4242 · expires 08/27',
    );
    expect(cardLabel(card({'brand': 'mastercard', 'last4': '4444'})), 'Mastercard ending 4444');
    expect(cardLabel(card(const {})), 'Card');
    expect(
      cardName(card({'brand': 'visa', 'last4': '4242', 'expMonth': 8, 'expYear': 2027})),
      ('Visa ending 4242'),
    );
  });

  test('small formatters', () {
    expect(fmtLongDate(DateTime(2026, 1, 15)), 'Thursday, January 15');
    expect(fmtLongDate(DateTime(2026, 10, 5)), 'Monday, October 5');
    expect(countOf(1, 'job'), '1 job');
    expect(countOf(0, 'job'), '0 jobs');
    expect(countOf(2, 'property', 'properties'), '2 properties');
    expect(firstNameOf('  Marcus   Reid '), 'Marcus');
    expect(firstNameOf(''), '');
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:redefine_customer/logic.dart';
import 'package:redefine_ui/redefine_ui.dart';

Property property(String id, {String status = 'active', int? price, String? jobId}) =>
    Property.fromJson({
      'id': id,
      'name': id,
      'status': status,
      'price': price,
      'activeJob': jobId == null ? null : {'id': jobId, 'status': 'open'},
    });

// Timestamps without a zone are local time, so the formatted text does not
// depend on where the tests run.
Job job({
  String status = 'open',
  String paymentMode = 'manual',
  String paymentStatus = 'none',
  String? capturedAt,
  bool shovel = false,
  String crewName = '',
  String? claimedAt,
  String? startedAt,
  String? completedAt,
  String? cancelledAt,
  String? cancelledBy,
}) => Job.fromJson({
  'id': 'job_1',
  'status': status,
  'shovel': shovel,
  'price': 45,
  'shovelPrice': shovel ? 20 : 0,
  'total': shovel ? 65 : 45,
  'crewName': crewName,
  'requestedAt': '2020-01-05T09:00:00',
  'claimedAt': claimedAt,
  'startedAt': startedAt,
  'completedAt': completedAt,
  'cancelledAt': cancelledAt,
  'cancelledBy': cancelledBy,
  'payment': {'mode': paymentMode, 'status': paymentStatus, 'capturedAt': capturedAt},
});

Billing billing({String mode = 'stripe', Map<String, Object?>? card}) =>
    Billing.fromJson({'mode': mode, 'card': card});

CardInfo card({String brand = 'visa', String last4 = '4242', String? updatedAt}) =>
    CardInfo.fromJson({
      'brand': brand,
      'last4': last4,
      'expMonth': 4,
      'expYear': 2027,
      'updatedAt': updatedAt,
    });

List<String> describe(List<RStep> steps) => [
  for (final s in steps)
    '${s.state.name}: ${s.title}${s.subtitle == null ? '' : ' (${s.subtitle})'}',
];

void main() {
  group('property selection', () {
    final plain = property('a', price: 45);
    final waiting = property('b', status: 'quoteRequested');
    final quoted = property('c', status: 'quoted', price: 60);
    final busy = property('d', price: 50, jobId: 'job_9');

    test('needsAttention marks a quote to answer or a job under way', () {
      expect(needsAttention(plain), isFalse);
      expect(needsAttention(waiting), isFalse);
      expect(needsAttention(quoted), isTrue);
      expect(needsAttention(busy), isTrue);
    });

    test('defaultPropertyId prefers a job under way, then a quote, then the first', () {
      expect(defaultPropertyId([]), isNull);
      expect(defaultPropertyId([plain, waiting]), 'a');
      expect(defaultPropertyId([plain, waiting, quoted]), 'c');
      expect(defaultPropertyId([plain, quoted, busy]), 'd');
    });

    test('keepSelection keeps an existing selection and replaces a missing one', () {
      expect(keepSelection('b', [plain, waiting, quoted]), 'b');
      expect(keepSelection('gone', [plain, waiting, quoted]), 'c');
      expect(keepSelection(null, [plain]), 'a');
      expect(keepSelection('a', []), isNull);
    });

    test('propertiesPollInterval follows what is being waited for', () {
      expect(propertiesPollInterval([]), const Duration(seconds: 60));
      expect(propertiesPollInterval([plain, quoted]), const Duration(seconds: 60));
      expect(propertiesPollInterval([plain, waiting]), const Duration(seconds: 15));
      expect(propertiesPollInterval([waiting, busy]), const Duration(seconds: 5));
    });
  });

  group('followActiveJobs', () {
    test('starts following a new job without reporting anything', () {
      final result = followActiveJobs({}, [property('a', jobId: 'job_1'), property('b')]);
      expect(result.following, {'a': 'job_1'});
      expect(result.ended, isEmpty);
    });

    test('reports a followed job that is gone, once', () {
      final first = followActiveJobs({'a': 'job_1'}, [property('a')]);
      expect(first.ended, [(propertyId: 'a', jobId: 'job_1')]);
      expect(first.following, isEmpty);
      expect(followActiveJobs(first.following, [property('a')]).ended, isEmpty);
    });

    test('reports a job that was replaced by another and follows the new one', () {
      final result = followActiveJobs({'a': 'job_1'}, [property('a', jobId: 'job_2')]);
      expect(result.ended, [(propertyId: 'a', jobId: 'job_1')]);
      expect(result.following, {'a': 'job_2'});
    });

    test('forgets a property that no longer exists', () {
      final result = followActiveJobs({'a': 'job_1'}, [property('b')]);
      expect(result.following, isEmpty);
      expect(result.ended, isEmpty);
    });
  });

  group('job changes made on this device', () {
    final requested = job();
    final idle = property('a', price: 45);
    final busy = property('b', price: 50, jobId: 'job_9');

    test('shownJob prefers what was just done over what the property says', () {
      expect(shownJob(idle), isNull);
      expect(shownJob(busy)?.id, 'job_9');
      // Requested here: shown although the property does not carry it yet.
      expect(shownJob(idle, {'a': JobChange(requested, afterLoad: 3)}), same(requested));
      // Cancelled here: gone although the property still carries it.
      expect(shownJob(busy, {'b': const JobChange(null, afterLoad: 3)}), isNull);
      // A change to another property does not matter.
      expect(shownJob(busy, {'a': JobChange(requested, afterLoad: 3)})?.id, 'job_9');
    });

    test('a change is known only to properties loaded after it', () {
      const change = JobChange(null, afterLoad: 3);
      expect(change.knownTo(2), isFalse);
      // Load 3 was already under way and may have missed it.
      expect(change.knownTo(3), isFalse);
      expect(change.knownTo(4), isTrue);
    });

    test('needsAttention follows the shown job', () {
      expect(needsAttention(idle, {'a': JobChange(requested, afterLoad: 1)}), isTrue);
      expect(needsAttention(busy, {'b': const JobChange(null, afterLoad: 1)}), isFalse);
    });

    test('the properties are polled quickly until they catch up with a change', () {
      expect(propertiesPollInterval([idle]), const Duration(seconds: 60));
      expect(
        propertiesPollInterval([idle], {'a': JobChange(requested, afterLoad: 1)}),
        const Duration(seconds: 5),
      );
      expect(
        propertiesPollInterval([idle], {'a': const JobChange(null, afterLoad: 1)}),
        const Duration(seconds: 5),
      );
    });

    test('followActiveJobs follows a job requested here before the properties carry it', () {
      final changes = {'a': JobChange(requested, afterLoad: 1)};
      final first = followActiveJobs({}, [idle], changes);
      expect(first.following, {'a': 'job_1'});
      expect(first.ended, isEmpty);
      // The properties caught up and the job is over already.
      expect(followActiveJobs(first.following, [idle]).ended, [(propertyId: 'a', jobId: 'job_1')]);
    });

    test('followActiveJobs ends a job cancelled here while the properties still carry it', () {
      final changes = {'b': const JobChange(null, afterLoad: 1)};
      final result = followActiveJobs({'b': 'job_9'}, [busy], changes);
      expect(result.ended, [(propertyId: 'b', jobId: 'job_9')]);
      expect(result.following, isEmpty);
      expect(followActiveJobs(result.following, [busy], changes).ended, isEmpty);
    });
  });

  group('prices and cards', () {
    test('ploughTotal adds the shovelling price only when asked', () {
      expect(ploughTotal(price: 45, shovel: false, shovelPrice: 20), 45);
      expect(ploughTotal(price: 45, shovel: true, shovelPrice: 20), 65);
    });

    test('shovelExtra', () {
      expect(shovelExtra(20), '+\$20');
      expect(shovelExtra(0), 'at no extra charge');
    });

    test('cardLabel and cardExpiry', () {
      expect(cardLabel(card()), 'Visa ending 4242');
      expect(cardLabel(card(brand: 'amex', last4: '0005')), 'American Express ending 0005');
      expect(cardLabel(card(brand: 'cartes_bancaires')), 'Cartes bancaires ending 4242');
      expect(cardLabel(card(brand: '', last4: '')), 'Card');
      expect(cardExpiry(card()), 'Expires 04/27');
      expect(cardExpiry(CardInfo.fromJson({})), '');
    });

    test('cardSaved needs a card that is not the one already on file', () {
      final old = card(updatedAt: '2025-01-01T10:00:00Z');
      expect(cardSaved(null, null), isFalse);
      expect(cardSaved(old, null), isFalse);
      expect(cardSaved(null, old), isTrue);
      expect(cardSaved(old, card(updatedAt: '2025-01-01T10:00:00Z')), isFalse);
      expect(cardSaved(old, card(last4: '1111', updatedAt: '2025-03-01T10:00:00Z')), isTrue);
    });

    test('requestConfirmation states the hold in Stripe mode and the bill otherwise', () {
      expect(
        requestConfirmation(65, billing(card: {'brand': 'visa', 'last4': '4242'})),
        "We'll place a hold of \$65 on your Visa ending 4242. "
        "You're charged only when the job is done.",
      );
      expect(
        requestConfirmation(45, billing(mode: 'manual')),
        "You'll be billed \$45 after the job.",
      );
      expect(requestConfirmation(45, billing()), "You'll be billed \$45 after the job.");
    });

    test('requestConfirmation says when the total is not the one the screen showed', () {
      expect(
        requestConfirmation(75, billing(mode: 'manual'), shownTotal: 65),
        'The price has changed, so the total is now \$75, not \$65. '
        "You'll be billed \$75 after the job.",
      );
      expect(
        requestConfirmation(40, billing(card: {'brand': 'visa', 'last4': '4242'}), shownTotal: 45),
        'The price has changed, so the total is now \$40, not \$45. '
        "We'll place a hold of \$40 on your Visa ending 4242. "
        "You're charged only when the job is done.",
      );
      expect(
        requestConfirmation(45, billing(mode: 'manual'), shownTotal: 45),
        "You'll be billed \$45 after the job.",
      );
    });

    test('requestedMessage gives the real total when it is not the confirmed one', () {
      expect(
        requestedMessage(job(), confirmed: 45),
        'Plough requested. The crew that accepts it shows up here.',
      );
      expect(
        requestedMessage(job(shovel: true), confirmed: 55),
        'Plough requested, but the price changed as you confirmed: the total is \$65, '
        'not \$55. You can still cancel the request.',
      );
    });

    test('Account.paysByCard follows the billing mode', () {
      Account account(String mode) => Account(
        settings: Settings.fromJson({'shovelPrice': 20, 'paymentsMode': mode}),
        billing: billing(mode: mode),
      );
      expect(account('stripe').paysByCard, isTrue);
      expect(account('manual').paysByCard, isFalse);
    });
  });

  group('jobOutcomeMessage', () {
    test('a finished job says what happened to the money', () {
      expect(
        jobOutcomeMessage(job(status: 'done', paymentMode: 'stripe', paymentStatus: 'captured')),
        'Plough complete · \$45 charged',
      );
      expect(
        jobOutcomeMessage(job(status: 'done', paymentStatus: 'due', shovel: true)),
        'Plough complete · \$65 billed',
      );
      expect(
        jobOutcomeMessage(job(status: 'done', paymentStatus: 'paid')),
        'Plough complete · \$45 paid',
      );
      expect(
        jobOutcomeMessage(job(status: 'done', paymentMode: 'stripe', paymentStatus: 'failed')),
        "Plough complete · we couldn't charge your card",
      );
    });

    test('a cancelled job mentions the hold only when one was released', () {
      expect(
        jobOutcomeMessage(
          job(status: 'cancelled', paymentMode: 'stripe', paymentStatus: 'released'),
        ),
        'Request cancelled · hold released',
      );
      expect(jobOutcomeMessage(job(status: 'cancelled')), 'Request cancelled');
    });

    test('a cancelled job whose hold is still on the card says it is being released', () {
      expect(
        jobOutcomeMessage(
          job(status: 'cancelled', paymentMode: 'stripe', paymentStatus: 'authorized'),
        ),
        'Request cancelled · the hold is being released',
      );
    });

    test('a job still under way has no outcome', () {
      expect(jobOutcomeMessage(job()), isNull);
      expect(jobOutcomeMessage(job(status: 'inProgress')), isNull);
    });
  });

  group('jobSteps', () {
    test('open: requested is current and the rest is still to come', () {
      expect(describe(jobSteps(job())), [
        'current: Requested (Jan 5, 2020, 9:00 am · waiting for a crew to accept)',
        'upcoming: Crew assigned',
        'upcoming: In progress',
        'upcoming: Done',
      ]);
    });

    test('claimed: names the crew', () {
      final steps = jobSteps(
        job(status: 'claimed', crewName: 'Marcus Reid', claimedAt: '2020-01-05T09:10:00'),
      );
      expect(describe(steps), [
        'done: Requested (Jan 5, 2020, 9:00 am)',
        'current: Crew assigned (Marcus Reid · Jan 5, 2020, 9:10 am)',
        'upcoming: In progress',
        'upcoming: Done',
      ]);
    });

    test('in progress: shows the start and the running time', () {
      final steps = jobSteps(
        job(
          status: 'inProgress',
          crewName: 'Marcus Reid',
          claimedAt: '2020-01-05T09:10:00',
          startedAt: '2020-01-05T09:42:00',
        ),
        elapsed: const Duration(minutes: 18, seconds: 30),
      );
      expect(describe(steps).sublist(2), [
        'current: In progress (Started 9:42 am · 18 min)',
        'upcoming: Done',
      ]);
    });

    test('done: every step is done, with the time it took', () {
      final steps = jobSteps(
        job(
          status: 'done',
          crewName: 'Marcus Reid',
          claimedAt: '2020-01-05T09:10:00',
          startedAt: '2020-01-05T09:42:00',
          completedAt: '2020-01-05T10:29:00',
        ),
      );
      expect(describe(steps), [
        'done: Requested (Jan 5, 2020, 9:00 am)',
        'done: Crew assigned (Marcus Reid · Jan 5, 2020, 9:10 am)',
        'done: Work started (Jan 5, 2020, 9:42 am)',
        'done: Done (Jan 5, 2020, 10:29 am · took 47 min)',
      ]);
    });

    test('cancelled: only the steps it reached, then who cancelled', () {
      expect(
        describe(
          jobSteps(
            job(status: 'cancelled', cancelledAt: '2020-01-05T09:20:00', cancelledBy: 'customer'),
          ),
        ),
        [
          'done: Requested (Jan 5, 2020, 9:00 am)',
          'current: Cancelled by you (Jan 5, 2020, 9:20 am)',
        ],
      );
      final afterStart = jobSteps(
        job(
          status: 'cancelled',
          crewName: 'Marcus Reid',
          claimedAt: '2020-01-05T09:10:00',
          startedAt: '2020-01-05T09:42:00',
          cancelledAt: '2020-01-05T09:50:00',
          cancelledBy: 'admin',
        ),
      );
      expect(describe(afterStart), [
        'done: Requested (Jan 5, 2020, 9:00 am)',
        'done: Crew assigned (Marcus Reid · Jan 5, 2020, 9:10 am)',
        'done: Work started (Jan 5, 2020, 9:42 am)',
        'current: Cancelled by the office (Jan 5, 2020, 9:50 am)',
      ]);
    });
  });

  group('past jobs', () {
    final done = job(
      status: 'done',
      crewName: 'Marcus Reid',
      shovel: true,
      startedAt: '2020-01-05T09:42:00',
      completedAt: '2020-01-05T10:29:00',
    );
    final cancelled = job(
      status: 'cancelled',
      cancelledAt: '2020-01-05T09:20:00',
      cancelledBy: 'system',
    );

    test('pastJobs keeps done and cancelled jobs in order', () {
      final jobs = [job(), done, job(status: 'inProgress'), cancelled];
      expect(pastJobs(jobs), [done, cancelled]);
    });

    test('pastJobDate is when the job ended', () {
      expect(pastJobDate(done), DateTime(2020, 1, 5, 10, 29));
      expect(pastJobDate(cancelled), DateTime(2020, 1, 5, 9, 20));
    });

    test('pastJobSummary', () {
      expect(pastJobSummary(done), 'Marcus Reid · 47 min · with shovelling');
      expect(pastJobSummary(cancelled), 'Expired before a crew accepted');
      expect(pastJobSummary(job(status: 'done')), 'Plough');
    });

    test('cancelledLabel', () {
      expect(cancelledLabel('customer'), 'Cancelled by you');
      expect(cancelledLabel('admin'), 'Cancelled by the office');
      expect(cancelledLabel(''), 'Cancelled');
    });
  });

  group('payment wording', () {
    test('activePaymentLine', () {
      expect(
        activePaymentLine(job(paymentMode: 'stripe', paymentStatus: 'authorized').payment),
        'Hold placed on your card',
      );
      expect(activePaymentLine(job().payment), 'Billed after the job');
    });

    test('paymentSummary covers every payment status', () {
      String summary(String status, {String jobStatus = 'done', String? capturedAt}) =>
          paymentSummary(
            job(
              status: jobStatus,
              paymentMode: 'stripe',
              paymentStatus: status,
              capturedAt: capturedAt,
            ),
          );
      expect(
        summary('authorized', jobStatus: 'open'),
        "A hold of \$45 is on your card. You're charged only when the job is done.",
      );
      expect(summary('captured'), '\$45 was charged to your card.');
      expect(
        summary('captured', capturedAt: '2020-01-05T10:29:00'),
        '\$45 was charged to your card on Jan 5, 2020, 10:29 am.',
      );
      expect(
        summary('released', jobStatus: 'cancelled'),
        'The hold on your card was released. You were not charged.',
      );
      expect(summary('failed'), "We couldn't charge your card for this job.");
      expect(summary('due'), '\$45 is due for this job.');
      expect(summary('paid'), 'Paid. Thank you.');
      expect(summary('none', jobStatus: 'open'), "You'll be billed \$45 after the job.");
      expect(
        summary('none', jobStatus: 'cancelled'),
        'This request was cancelled, so nothing is billed.',
      );
      expect(summary('none'), '');
    });

    test('paymentSummary reads a hold by where the job stands', () {
      String held(String jobStatus) => paymentSummary(
        job(status: jobStatus, paymentMode: 'stripe', paymentStatus: 'authorized'),
      );
      const waiting = "A hold of \$45 is on your card. You're charged only when the job is done.";
      expect(held('open'), waiting);
      expect(held('claimed'), waiting);
      expect(held('inProgress'), waiting);
      // Cancelled while the payment provider could not be reached.
      expect(
        held('cancelled'),
        'The hold of \$45 on your card is being released. You will not be charged.',
      );
      // Done, with the charge still going through.
      expect(held('done'), 'The job is done and \$45 is being charged to your card.');
    });

    test('holdBeingReleased is a cancelled job with its hold still placed', () {
      Job cancelled(String payment) =>
          job(status: 'cancelled', paymentMode: 'stripe', paymentStatus: payment);
      expect(holdBeingReleased(cancelled('authorized')), isTrue);
      expect(holdBeingReleased(cancelled('released')), isFalse);
      expect(holdBeingReleased(job(paymentMode: 'stripe', paymentStatus: 'authorized')), isFalse);
    });
  });

  group('validatePropertyForm', () {
    test('accepts a name and an address, with or without a note', () {
      expect(validatePropertyForm(name: 'Home', address: '1 Main St', note: '').isEmpty, isTrue);
      expect(
        validatePropertyForm(name: 'H' * 60, address: 'A' * 160, note: 'n' * 500).isEmpty,
        isTrue,
      );
    });

    test('requires the name and the address', () {
      final errors = validatePropertyForm(name: '', address: '', note: '');
      expect(errors.name, 'Give this property a name.');
      expect(errors.address, 'Enter the address to plough.');
      expect(errors.note, isNull);
      expect(errors.isEmpty, isFalse);
    });

    test('enforces the API limits', () {
      final errors = validatePropertyForm(name: 'H' * 61, address: 'A' * 161, note: 'n' * 501);
      expect(errors.name, 'Use 60 characters or fewer.');
      expect(errors.address, 'Use 160 characters or fewer.');
      expect(errors.note, 'Use 500 characters or fewer.');
    });
  });
}

import 'package:redefine_core/redefine_core.dart';
import 'package:redefine_e2e/redefine_e2e.dart';
import 'package:test/test.dart';

import 'support/harness.dart';

const _colors = ['lime', 'teal', 'paper'];

DateTime _ago({int days = 0, int hours = 0, int minutes = 0}) => TestServer
    .startTime
    .subtract(Duration(days: days, hours: hours, minutes: minutes));

/// Every list and detail model, parsed from the contract's demo data.
void main() {
  late TestServer server;
  late ApiClient lia;

  setUp(() async {
    server = await startServer(seed: true);
    lia = await signIn(server, 'lia@redefine.co');
  });

  test('settings are shaped by role', () async {
    final sarah = await signIn(server, 'sarah.m@gmail.com');
    final marcus = await signIn(server, 'marcus@redefine.co');

    final admin = await lia.settings();
    expect((admin.shovelPrice, admin.crewShovelBonus), (20, 10));
    expect(admin.openJobExpiryHours, 48);
    expect((admin.currency, admin.paymentsMode), ('cad', PaymentMode.stripe));

    final customer = await sarah.settings();
    expect((customer.shovelPrice, customer.crewShovelBonus), (20, 0));
    expect(customer.openJobExpiryHours, 0);
    expect(customer.currency, 'cad');
    expect(customer.paymentsMode, PaymentMode.stripe);

    final crew = await marcus.settings();
    expect((crew.shovelPrice, crew.crewShovelBonus), (0, 10));
    expect((crew.currency, crew.paymentsMode), ('cad', PaymentMode.unknown));
  });

  test('the customer directory and a customer in detail', () async {
    final sarahApp = await signIn(server, 'sarah.m@gmail.com');
    await saveCard(sarahApp);

    final customers = await lia.customers();
    expect(customers.map((c) => c.name), [
      'Anna Tomlinson',
      'Paul Larson',
      'Sarah Mitchell',
    ]);
    final [anna, paul, sarah] = customers;
    expect((sarah.id, sarah.initials), ('cust_sarah', 'SM'));
    expect((sarah.email, sarah.phone), ('sarah.m@gmail.com', '(807) 555-0142'));
    expect(_colors, contains(sarah.color));
    expect(sarah.createdAt, isMoment(_ago(days: 21)));
    expect((sarah.propertyCount, sarah.activeProperties), (2, 1));
    expect(sarah.jobCount, 3);
    expect(sarah.lastJobAt, isMoment(_ago(days: 2, hours: 2)));
    expect(sarah.hasCard, isTrue);
    expect(sarah.addresses, [
      '412 Maple St, Thunder Bay, ON',
      '88 Lakeside Rd, Thunder Bay, ON',
    ]);
    expect((anna.id, anna.jobCount, anna.hasCard), ('cust_anna', 2, false));
    expect((paul.propertyCount, paul.activeProperties), (1, 0));
    expect((paul.jobCount, paul.lastJobAt, paul.phone), (0, null, ''));

    final detail = await lia.customer('cust_sarah');
    expect(detail.customer.name, 'Sarah Mitchell');
    expect(detail.customer.jobCount, 3);
    expect((detail.card?.brand, detail.card?.last4), ('visa', '4242'));
    expect((detail.billed, detail.outstanding), (155, 0));
    expect(detail.jobs.map((j) => j.id), [
      'job_maple_3',
      'job_maple_2',
      'job_maple_1',
    ]);
    final [maple, cabin] = detail.properties;
    expect((maple.id, maple.status), ('prop_maple', PropertyStatus.active));
    expect((maple.price, maple.crewPay), (45, 25));
    expect(
      (maple.customerId, maple.customerName),
      ('cust_sarah', 'Sarah Mitchell'),
    );
    expect((maple.quoteId, maple.activeJob), ('quote_maple', null));
    expect(cabin.status, PropertyStatus.quoteRequested);
    expect(
      (cabin.price, cabin.crewPay, cabin.quoteId),
      (null, null, 'quote_cabin'),
    );
    expect(cabin.note, contains('gravel driveway'));

    final owing = await lia.customer('cust_anna');
    expect((owing.billed, owing.outstanding, owing.card), (0, 55, null));
    expect(owing.jobs.map((j) => j.id), ['job_cedar_2', 'job_cedar_1']);
    final waiting = owing.properties.single.activeJob!;
    expect(
      (waiting.id, waiting.total, waiting.crewPay),
      ('job_cedar_2', 75, 40),
    );
  });

  test('jobs as the admin, the customer and the crew see them', () async {
    final anna = await signIn(server, 'anna.t@gmail.com');
    final marcus = await signIn(server, 'marcus@redefine.co');

    final full = await lia.job('job_maple_1');
    expect((full.propertyId, full.customerId), ('prop_maple', 'cust_sarah'));
    expect(full.propertyName, 'Maple Street home');
    expect(full.address, '412 Maple St, Thunder Bay, ON');
    expect(full.illustration, 'house');
    expect(
      (full.customerName, full.customerInitials),
      ('Sarah Mitchell', 'SM'),
    );
    expect(full.customerPhone, '(807) 555-0142');
    expect((full.shovel, full.price, full.shovelPrice), (true, 45, 20));
    expect((full.total, full.crewPay), (65, 35));
    expect((full.status, full.source), (JobStatus.done, 'customer'));
    expect((full.crewId, full.crewName), ('crew_marcus', 'Marcus Reid'));
    expect(full.crewInitials, 'MR');
    expect(_colors, contains(full.crewColor));
    expect(full.completedAt, isMoment(_ago(days: 16)));
    expect(full.requestedAt, isMoment(_ago(days: 16, hours: 2)));
    expect(full.duration, const Duration(minutes: 40));
    expect((full.cancelledAt, full.cancelledBy), (null, ''));
    expect(
      (full.payment.mode, full.payment.status),
      (PaymentMode.manual, PaymentStatus.paid),
    );
    expect(full.payment.capturedAt, isMoment(_ago(days: 15)));
    expect(full.paidOut, isTrue);
    expect((await lia.job('job_maple_2')).paidOut, isFalse);

    expect((await lia.jobs()).map((j) => j.id), [
      'job_cedar_2',
      'job_maple_3',
      'job_cedar_1',
      'job_maple_2',
      'job_maple_1',
    ]);
    Future<List<String>> ids(Future<List<Job>> jobs) async => [
      for (final j in await jobs) j.id,
    ];
    expect(await ids(lia.jobs(status: [JobStatus.open, JobStatus.claimed])), [
      'job_cedar_2',
    ]);
    expect(await ids(lia.jobs(payment: [PaymentStatus.due])), ['job_cedar_1']);
    expect(await ids(lia.jobs(crewId: 'crew_marcus')), [
      'job_maple_3',
      'job_maple_2',
      'job_maple_1',
    ]);
    expect(
      await ids(lia.jobs(customerId: 'cust_anna', status: [JobStatus.done])),
      ['job_cedar_1'],
    );
    expect(await ids(lia.jobs(propertyId: 'prop_cedar')), [
      'job_cedar_2',
      'job_cedar_1',
    ]);
    expect(await ids(lia.jobs(from: _ago(days: 5), to: _ago(days: 1))), [
      'job_maple_3',
      'job_cedar_1',
    ]);
    expect(await ids(lia.jobs(from: _ago(hours: 1))), ['job_cedar_2']);

    final mine = await anna.jobs();
    expect(mine.map((j) => j.id), ['job_cedar_2', 'job_cedar_1']);
    final requested = mine.first;
    expect((requested.status, requested.shovel), (JobStatus.open, true));
    expect(
      (requested.price, requested.shovelPrice, requested.total),
      (55, 20, 75),
    );
    expect(
      (requested.crewPay, requested.crewId, requested.paidOut),
      (0, '', false),
    );
    expect(
      (requested.payment.mode, requested.payment.status),
      (PaymentMode.manual, PaymentStatus.none),
    );
    expect(requested.requestedAt, isMoment(_ago(minutes: 10)));
    expect(mine.last.crewName, 'Jordan Park');
    expect(await ids(anna.jobs(status: [JobStatus.done])), ['job_cedar_1']);
    expect(await ids(anna.jobs(propertyId: 'prop_maple')), isEmpty);

    final open = (await marcus.jobs(scope: 'open')).single;
    expect((open.id, open.crewPay), ('job_cedar_2', 40));
    expect((open.price, open.total), (0, 0));
    expect(open.payment.status, PaymentStatus.unknown);
    expect((open.customerName, open.customerPhone), ('', ''));
    expect(open.note, contains('side door'));
    final done = await marcus.jobs(scope: 'mine');
    expect(done.map((j) => j.id), [
      'job_maple_3',
      'job_maple_2',
      'job_maple_1',
    ]);
    expect(
      (done.first.customerName, done.first.crewPay),
      ('Sarah Mitchell', 25),
    );
    expect(done.map((j) => j.paidOut), [false, false, true]);
  });

  test('properties and quotes, listed and filtered', () async {
    final paul = await signIn(server, 'paul.l@gmail.com');

    final all = await lia.properties();
    expect(all.map((p) => p.id), [
      'prop_maple',
      'prop_cedar',
      'prop_birch',
      'prop_cabin',
    ]);
    expect(all.map((p) => p.customerName).toSet(), {
      'Sarah Mitchell',
      'Anna Tomlinson',
      'Paul Larson',
    });
    expect(all[1].activeJob?.id, 'job_cedar_2');
    expect(all[1].createdAt, isMoment(_ago(days: 14)));
    expect((await lia.properties(status: 'active')).map((p) => p.id), [
      'prop_maple',
      'prop_cedar',
    ]);
    expect((await lia.properties(customerId: 'cust_sarah')).map((p) => p.id), [
      'prop_maple',
      'prop_cabin',
    ]);

    final birch = (await paul.properties()).single;
    expect((birch.id, birch.name), ('prop_birch', 'Birch Road home'));
    expect(
      (birch.address, birch.illustration),
      ('21 Birch Rd, Thunder Bay, ON', 'townhouse'),
    );
    expect((birch.status, birch.price), (PropertyStatus.quoted, 60));
    expect((birch.crewPay, birch.customerId), (null, ''));
    expect(birch.quoteId, 'quote_birch');
    expect(birch.note, contains('hedge'));

    expect((await lia.quotes()).map((q) => q.id), [
      'quote_cabin',
      'quote_birch',
      'quote_cedar',
      'quote_maple',
    ]);
    expect((await lia.quotes(status: 'sent')).map((q) => q.id), [
      'quote_birch',
    ]);
    final offer = await lia.quote('quote_birch');
    expect((offer.propertyId, offer.customerId), ('prop_birch', 'cust_paul'));
    expect(
      (offer.status, offer.price, offer.crewPay),
      (QuoteStatus.sent, 60, 35),
    );
    expect((offer.customerName, offer.customerInitials), ('Paul Larson', 'PL'));
    expect(_colors, contains(offer.customerColor));
    expect((offer.email, offer.phone), ('paul.l@gmail.com', ''));
    expect(
      (offer.propertyName, offer.address, offer.illustration),
      ('Birch Road home', '21 Birch Rd, Thunder Bay, ON', 'townhouse'),
    );
    expect(offer.note, contains('hedge'));
    expect(offer.createdAt, isMoment(_ago(days: 2)));
    expect(offer.sentAt, isMoment(_ago(days: 1)));
    expect(offer.decidedAt, isNull);

    final mine = (await paul.quotes()).single;
    expect((mine.id, mine.price, mine.crewPay), ('quote_birch', 60, null));
    final accepted = await lia.quote('quote_maple');
    expect(accepted.status, QuoteStatus.accepted);
    expect(accepted.decidedAt, isMoment(_ago(days: 20)));
  });

  test('the crew list, earnings and payouts', () async {
    final marcusApp = await signIn(server, 'marcus@redefine.co');

    final crew = await lia.crew();
    expect(crew.active.map((c) => c.name), ['Jordan Park', 'Marcus Reid']);
    expect(crew.pending.single.name, 'Tasha Rivera');
    expect(crew.rejected, isEmpty);
    final [jordan, marcus] = crew.active;
    expect((marcus.id, marcus.userId), ('crew_marcus', 'user_marcus'));
    expect((marcus.initials, marcus.status), ('MR', CrewStatus.active));
    expect(
      (marcus.email, marcus.phone),
      ('marcus@redefine.co', '(807) 555-0111'),
    );
    expect(_colors, contains(marcus.color));
    expect(marcus.appliedAt, isMoment(_ago(days: 45)));
    expect((marcus.jobsThisWeek, marcus.earnedThisWeek), (1, 25));
    expect((marcus.unpaidJobs, marcus.unpaidTotal), (2, 50));
    expect((jordan.unpaidJobs, jordan.unpaidTotal), (1, 30));
    expect(crew.pending.single.status, CrewStatus.pending);

    for (final pay in [
      await marcusApp.crewPay('me'),
      await marcusApp.crewPay('crew_marcus'),
      await lia.crewPay('crew_marcus'),
    ]) {
      expect((pay.crewId, pay.name), ('crew_marcus', 'Marcus Reid'));
      expect((pay.earnedToday, pay.jobsToday), (0, 0));
      expect((pay.earnedThisWeek, pay.jobsThisWeek), (25, 1));
      expect((pay.earnedAllTime, pay.unpaidTotal), (85, 50));
      expect(pay.unpaidJobs.map((j) => j.id), ['job_maple_3', 'job_maple_2']);
      expect(pay.unpaidJobs.first.customerName, 'Sarah Mitchell');
      expect(
        (pay.unpaidJobs.first.crewPay, pay.unpaidJobs.first.total),
        (25, 0),
      );
      final payout = pay.payouts.single;
      expect((payout.id, payout.crewId), ('payout_1', 'crew_marcus'));
      expect((payout.amount, payout.jobCount), (35, 1));
      expect(payout.note, 'e-transfer');
      expect(payout.paidAt, isMoment(_ago(days: 14)));
    }

    final paid = await lia.recordPayout('crew_marcus');
    expect((paid.payout.amount, paid.payout.jobCount), (50, 2));
    expect(paid.payout.note, '');
    expect(paid.pay.payouts.map((p) => p.id), [paid.payout.id, 'payout_1']);
    expect((paid.pay.unpaidTotal, paid.pay.earnedAllTime), (0, 85));
    final after = (await lia.crew()).active.last;
    expect((after.unpaidJobs, after.unpaidTotal), (0, 0));
  });

  test('the admin dashboard', () async {
    final dashboard = await lia.adminDashboard();
    final serverTime = dashboard.serverTime!.toUtc();
    expect(serverTime.isBefore(TestServer.startTime), isFalse);
    expect(serverTime.isAfter(server.now), isFalse);

    final counts = dashboard.counts;
    expect((counts.pendingQuotes, counts.sentQuotes), (1, 1));
    expect(counts.pendingCrew, 1);
    expect(
      (counts.openJobs, counts.claimedJobs, counts.inProgressJobs),
      (1, 0, 0),
    );
    expect((counts.doneToday, counts.cancelledToday), (0, 0));
    expect((counts.revenueToday, counts.paymentIssues), (0, 1));

    final quote = dashboard.pendingQuotes.single;
    expect((quote.id, quote.status), ('quote_cabin', QuoteStatus.pending));
    expect(
      (quote.customerName, quote.propertyName),
      ('Sarah Mitchell', 'Cabin'),
    );
    expect(quote.note, contains('gravel driveway'));
    final live = dashboard.liveJobs.single;
    expect((live.id, live.customerName), ('job_cedar_2', 'Anna Tomlinson'));
    expect((live.total, live.crewPay), (75, 40));
    final applicant = dashboard.pendingCrew.single;
    expect((applicant.id, applicant.name), ('crew_tasha', 'Tasha Rivera'));
    expect(applicant.appliedAt, isMoment(_ago(days: 1)));
    final issue = dashboard.paymentIssues.single;
    expect((issue.id, issue.total), ('job_cedar_1', 55));
    expect(issue.payment.status, PaymentStatus.due);

    // The dashboard follows the work.
    final marcus = await signIn(server, 'marcus@redefine.co');
    await marcus.claimJob('job_cedar_2');
    var moved = (await lia.adminDashboard()).counts;
    expect((moved.openJobs, moved.claimedJobs), (0, 1));
    await marcus.startJob('job_cedar_2');
    moved = (await lia.adminDashboard()).counts;
    expect((moved.claimedJobs, moved.inProgressJobs), (0, 1));
    await marcus.completeJob('job_cedar_2');
    final finished = await lia.adminDashboard();
    expect(finished.liveJobs, isEmpty);
    expect(finished.counts.inProgressJobs, 0);
    expect((finished.counts.doneToday, finished.counts.revenueToday), (1, 75));
    expect(finished.paymentIssues.map((j) => j.id), [
      'job_cedar_2',
      'job_cedar_1',
    ]);
  });

  test('billing lists what was held, charged and is still owed', () async {
    final sarah = await signIn(server, 'sarah.m@gmail.com');
    final marcus = await signIn(server, 'marcus@redefine.co');

    final history = await sarah.billing();
    expect((history.mode, history.needsCard), (PaymentMode.stripe, true));
    expect(history.balanceDue, 0);
    expect(history.charges.map((c) => c.jobId), [
      'job_maple_3',
      'job_maple_2',
      'job_maple_1',
    ]);
    final oldest = history.charges.last;
    expect(oldest.propertyName, 'Maple Street home');
    expect(
      (oldest.total, oldest.shovel, oldest.status),
      (65, true, PaymentStatus.paid),
    );
    expect(oldest.date, isMoment(_ago(days: 16)));

    await saveCard(sarah);
    final job = await sarah.requestJob(propertyId: 'prop_maple');
    final held = (await sarah.billing()).charges.first;
    expect((held.jobId, held.status), (job.id, PaymentStatus.authorized));
    expect(held.date, isMoment(job.requestedAt!));
    await plough(marcus, job.id);
    final charged = await sarah.billing();
    expect(charged.charges, hasLength(4));
    expect(
      (charged.charges.first.jobId, charged.charges.first.status),
      (job.id, PaymentStatus.captured),
    );
    expect((await lia.customer('cust_sarah')).billed, 200);
  });
}

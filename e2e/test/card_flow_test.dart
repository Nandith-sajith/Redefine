import 'package:redefine_core/redefine_core.dart';
import 'package:redefine_e2e/redefine_e2e.dart';
import 'package:test/test.dart';

import 'support/harness.dart';

void main() {
  late TestServer server;

  setUp(() async => server = await startServer());

  test('from quote request to crew payout, paid by card', () async {
    final gateway = server.gateway..autoCompleteSetup = false;
    final admin = await signUp(server, 'Avery Admin', role: 'admin');
    final customer = await signUp(
      server,
      'Casey Winter',
      phone: '(807) 555-0199',
    );
    final me = customer.currentUser!;
    expect((me.role, me.initials, me.crewStatus), ('customer', 'CW', null));
    expect(me.phone, '(807) 555-0199');
    final customerId = me.linkedId!;

    // Quote request, offer, acceptance.
    final requested = await customer.createProperty(
      name: 'Home',
      address: '12 Frost Lane',
      illustration: 'cabin',
      note: 'Steep driveway',
    );
    final propertyId = requested.property.id;
    final quoteId = requested.quote.id;
    expect(requested.property.status, PropertyStatus.quoteRequested);
    expect(requested.property.price, isNull);
    expect(requested.property.quoteId, quoteId);
    expect(requested.property.activeJob, isNull);
    expect(requested.quote.status, QuoteStatus.pending);
    expect(requested.quote.note, 'Steep driveway');
    expect(requested.quote.price, isNull);

    final inbox = await admin.adminDashboard();
    expect(inbox.counts.pendingQuotes, 1);
    final pending = inbox.pendingQuotes.single;
    expect(pending.id, quoteId);
    expect(pending.propertyId, propertyId);
    expect(pending.customerId, customerId);
    expect(pending.customerName, 'Casey Winter');
    expect(pending.customerInitials, 'CW');
    expect(pending.email, emailOf('Casey Winter'));
    expect(pending.phone, '(807) 555-0199');
    expect(pending.propertyName, 'Home');
    expect(pending.address, '12 Frost Lane');
    expect(pending.illustration, 'cabin');
    expect((await admin.quotes(status: 'pending')).map((q) => q.id), [quoteId]);

    final sent = await admin.sendQuote(quoteId, price: 45, crewPay: 25);
    expect(sent.status, QuoteStatus.sent);
    expect((sent.price, sent.crewPay), (45, 25));
    expect(sent.sentAt, isNotNull);
    expect(await admin.quotes(status: 'pending'), isEmpty);

    final quoted = (await customer.properties()).single;
    expect(quoted.status, PropertyStatus.quoted);
    expect(quoted.price, 45);
    expect(quoted.crewPay, isNull);
    final offer = await customer.quote(quoteId);
    expect(
      (offer.status, offer.price, offer.crewPay),
      (QuoteStatus.sent, 45, null),
    );

    final accepted = await customer.acceptQuote(quoteId);
    expect(accepted.quote.status, QuoteStatus.accepted);
    expect(accepted.quote.decidedAt, isNotNull);
    expect(accepted.property.status, PropertyStatus.active);
    expect(accepted.property.price, 45);

    // A card is needed before the first request.
    expect((await customer.settings()).paymentsMode, PaymentMode.stripe);
    final noCard = await customer.billing();
    expect(noCard.mode, PaymentMode.stripe);
    expect(noCard.needsCard, isTrue);
    expect(noCard.pendingSetup, isFalse);
    expect(noCard.charges, isEmpty);
    await expectApiError(
      customer.requestJob(propertyId: propertyId),
      402,
      'card_required',
    );

    final setupUrl = await customer.createCardSetupSession();
    final waiting = await customer.refreshBilling();
    expect(waiting.pendingSetup, isTrue);
    expect(waiting.needsCard, isTrue);
    server.completeCardSetup(setupUrl);
    // The server asks the payment provider at most once every two seconds.
    server.advance(const Duration(seconds: 3));
    final billing = await customer.refreshBilling();
    expect(billing.needsCard, isFalse);
    expect(billing.pendingSetup, isFalse);
    final card = billing.card!;
    expect(
      (card.brand, card.last4, card.expMonth, card.expYear),
      ('visa', '4242', 12, 2030),
    );
    expect(card.updatedAt, isNotNull);

    // The request places a hold for the plough plus the shovelling.
    final job = await customer.requestJob(
      propertyId: propertyId,
      shovel: true,
      note: 'Gate code 1234',
    );
    expect(job.status, JobStatus.open);
    expect(job.isActive, isTrue);
    expect((job.propertyId, job.customerId), (propertyId, customerId));
    expect((job.propertyName, job.address), ('Home', '12 Frost Lane'));
    expect(
      (job.shovel, job.note, job.source),
      (true, 'Gate code 1234', 'customer'),
    );
    expect((job.price, job.shovelPrice, job.total), (45, 20, 65));
    expect(job.payment.mode, PaymentMode.stripe);
    expect(job.payment.status, PaymentStatus.authorized);
    expect(job.payment.holdExpiresAt, isNotNull);
    expect(job.requestedAt, isNotNull);
    final hold = gateway.intentForJob(job.id)!;
    expect((hold.amountDollars, hold.status), (65, 'requires_capture'));
    expect((await customer.properties()).single.activeJob?.id, job.id);
    final held = (await customer.billing()).charges.single;
    expect(
      (held.jobId, held.status, held.total),
      (job.id, PaymentStatus.authorized, 65),
    );

    // Crew wait for approval, then see the job without its price.
    final crew = await signUp(
      server,
      'Riley Plough',
      role: 'crew',
      phone: '(807) 555-0101',
    );
    final rival = await signUp(server, 'Sam Drift', role: 'crew');
    final crewId = crew.currentUser!.linkedId!;
    final rivalId = rival.currentUser!.linkedId!;
    expect(crew.currentUser!.crewStatus, CrewStatus.pending);
    await expectApiError(crew.jobs(scope: 'open'), 403, 'crew_pending');
    await expectApiError(crew.claimJob(job.id), 403, 'crew_pending');

    final applicants = await admin.adminDashboard();
    expect(applicants.counts.pendingCrew, 2);
    expect(applicants.pendingCrew.map((c) => c.id), [crewId, rivalId]);
    expect(applicants.counts.openJobs, 1);
    expect(applicants.liveJobs.single.id, job.id);
    final approved = await admin.approveCrew(crewId);
    expect((approved.id, approved.status), (crewId, CrewStatus.active));
    expect(approved.name, 'Riley Plough');
    await admin.approveCrew(rivalId);
    expect((await crew.me()).crewStatus, CrewStatus.active);

    final offered = (await crew.jobs(scope: 'open')).single;
    expect(offered.id, job.id);
    expect((offered.price, offered.shovelPrice, offered.total), (0, 0, 0));
    expect(offered.payment.mode, PaymentMode.unknown);
    expect(offered.payment.status, PaymentStatus.unknown);
    expect(offered.crewPay, 35);
    expect((offered.shovel, offered.note), (true, 'Gate code 1234'));
    expect((offered.propertyName, offered.address), ('Home', '12 Frost Lane'));
    expect(offered.customerName, '');
    expect(offered.customerPhone, '');

    final claimed = await crew.claimJob(job.id);
    expect((claimed.status, claimed.crewId), (JobStatus.claimed, crewId));
    expect(claimed.claimedAt, isNotNull);
    expect(claimed.customerName, 'Casey Winter');
    expect(claimed.customerPhone, '(807) 555-0199');
    expect(claimed.total, 0);
    await expectApiError(rival.claimJob(job.id), 409, 'already_claimed');
    expect(await rival.jobs(scope: 'open'), isEmpty);
    await expectApiError(rival.job(job.id), 404, 'not_found');
    final assigned = await customer.job(job.id);
    expect(assigned.status, JobStatus.claimed);
    expect((assigned.crewName, assigned.crewInitials), ('Riley Plough', 'RP'));
    expect(assigned.canCustomerCancel, isTrue);

    final started = await crew.startJob(job.id);
    expect(started.status, JobStatus.inProgress);
    expect(started.startedAt, isNotNull);
    expect(
      (await crew.startJob(job.id)).startedAt,
      isMoment(started.startedAt!),
    );
    await expectApiError(customer.cancelJob(job.id), 409, 'job_started');

    final completed = await crew.completeJob(
      job.id,
      crewNote: 'Salted the steps too.',
    );
    expect(completed.status, JobStatus.done);
    expect(completed.crewNote, 'Salted the steps too.');
    expect(completed.duration, isNotNull);
    expect(completed.crewPay, 35);

    // Done: the hold is captured and the property is free again.
    final finished = await customer.job(job.id);
    expect(finished.status, JobStatus.done);
    expect(finished.stepIndex, 3);
    expect(finished.crewNote, 'Salted the steps too.');
    expect(finished.total, 65);
    expect(finished.payment.status, PaymentStatus.captured);
    expect(finished.payment.capturedAt, isNotNull);
    expect(finished.payment.error, isNull);
    expect(gateway.intentForJob(job.id)!.status, 'succeeded');
    await expectApiError(customer.cancelJob(job.id), 409, 'invalid_state');
    expect((await customer.properties()).single.activeJob, isNull);
    final charged = await customer.billing();
    expect(charged.balanceDue, 0);
    final charge = charged.charges.single;
    expect(charge.jobId, job.id);
    expect(charge.propertyName, 'Home');
    expect(
      (charge.status, charge.total, charge.shovel),
      (PaymentStatus.captured, 65, true),
    );
    expect(charge.date, isMoment(finished.completedAt!));

    final today = await admin.adminDashboard();
    expect(today.counts.doneToday, 1);
    expect(today.counts.revenueToday, 65);
    expect(today.counts.openJobs, 0);
    expect(today.counts.paymentIssues, 0);
    expect(today.liveJobs, isEmpty);
    final account = await admin.customer(customerId);
    expect(account.customer.hasCard, isTrue);
    expect(account.card?.last4, '4242');
    expect((account.billed, account.outstanding), (65, 0));
    expect(account.jobs.single.crewPay, 35);

    // The crew member earned the plough pay plus the shovelling bonus.
    final pay = await crew.crewPay('me');
    expect((pay.crewId, pay.name), (crewId, 'Riley Plough'));
    expect((pay.earnedToday, pay.jobsToday), (35, 1));
    expect((pay.earnedThisWeek, pay.jobsThisWeek), (35, 1));
    expect((pay.earnedAllTime, pay.unpaidTotal), (35, 35));
    expect(pay.unpaidJobs.single.id, job.id);
    expect(pay.unpaidJobs.single.paidOut, isFalse);
    expect(pay.payouts, isEmpty);
    expect((await crew.jobs()).single.id, job.id);
    final member = (await admin.crew()).active.firstWhere(
      (c) => c.id == crewId,
    );
    expect((member.unpaidTotal, member.unpaidJobs), (35, 1));
    expect((member.earnedThisWeek, member.jobsThisWeek), (35, 1));

    final paid = await admin.recordPayout(crewId, note: 'e-transfer');
    expect((paid.payout.crewId, paid.payout.amount), (crewId, 35));
    expect((paid.payout.jobCount, paid.payout.note), (1, 'e-transfer'));
    expect(paid.payout.paidAt, isNotNull);
    expect(paid.pay.unpaidTotal, 0);
    expect(paid.pay.unpaidJobs, isEmpty);
    expect(paid.pay.payouts.single.id, paid.payout.id);
    final settled = await crew.crewPay('me');
    expect((settled.unpaidTotal, settled.earnedAllTime), (0, 35));
    expect(settled.payouts.single.amount, 35);
    expect((await admin.job(job.id)).paidOut, isTrue);
    expect((await crew.job(job.id)).paidOut, isTrue);
    await expectApiError(admin.recordPayout(crewId), 409, 'nothing_to_pay');
  });

  test('the hosted card page saves the card on its way back', () async {
    server.gateway.autoCompleteSetup = false;
    final customer = await signUp(server, 'Casey Winter');

    final setupUrl = await customer.createCardSetupSession();
    expect((await customer.billing()).pendingSetup, isTrue);
    final sessionId = server.completeCardSetup(setupUrl, last4: '0005');
    final page = await server.returnFromCardSetup(sessionId);
    expect(page.statusCode, 200);
    expect(page.headers['content-type'], startsWith('text/html'));
    expect(page.body, contains('Card saved'));

    final billing = await customer.billing();
    expect(billing.card?.last4, '0005');
    expect(billing.pendingSetup, isFalse);
    expect(billing.needsCard, isFalse);

    // Saving another card replaces the first.
    final again = await customer.createCardSetupSession();
    server.completeCardSetup(again, last4: '4444');
    expect((await customer.refreshBilling()).card?.last4, '4444');
  });
}

import 'package:redefine_core/redefine_core.dart';
import 'package:redefine_e2e/redefine_e2e.dart';
import 'package:test/test.dart';

import 'support/harness.dart';

void main() {
  late TestServer server;
  late FakePaymentGateway gateway;
  late ApiClient admin, customer;
  late Property property;

  setUp(() async {
    server = await startServer();
    gateway = server.gateway;
    admin = await signUp(server, 'Avery Admin', role: 'admin');
    customer = await signUp(server, 'Casey Winter');
    property = await activeProperty(customer, admin);
    await saveCard(customer);
  });

  test('a refused hold creates no job', () async {
    gateway.authorizeOutcomes.addAll([
      PaymentOutcome.declined,
      PaymentOutcome.authRequired,
      PaymentOutcome.unavailable,
    ]);

    final declined = await expectApiError(
      customer.requestJob(propertyId: property.id, shovel: true),
      402,
      'card_declined',
    );
    expect(declined.message, gateway.declineMessage);
    await expectApiError(
      customer.requestJob(propertyId: property.id),
      402,
      'card_auth_required',
    );
    await expectApiError(
      customer.requestJob(propertyId: property.id),
      502,
      'payment_unavailable',
    );

    expect(gateway.intents, isEmpty);
    expect(await customer.jobs(), isEmpty);
    expect(await admin.jobs(), isEmpty);
    expect((await customer.properties()).single.activeJob, isNull);
    expect((await customer.billing()).charges, isEmpty);

    final job = await customer.requestJob(propertyId: property.id);
    expect(job.payment.status, PaymentStatus.authorized);
  });

  test('a property has one unfinished job at a time', () async {
    final job = await customer.requestJob(propertyId: property.id);

    final refused = await expectApiError(
      customer.requestJob(propertyId: property.id, shovel: true),
      409,
      'job_active',
    );
    expect(refused.extra['jobId'], job.id);
    final onBehalf = await expectApiError(
      admin.requestJob(propertyId: property.id, payment: 'manual'),
      409,
      'job_active',
    );
    expect(onBehalf.extra['jobId'], job.id);
    expect((await customer.jobs()).map((j) => j.id), [job.id]);
    expect(gateway.intents, hasLength(1));
  });

  test('cancelling before the work starts releases the hold', () async {
    final open = await customer.requestJob(
      propertyId: property.id,
      shovel: true,
    );
    final cancelled = await customer.cancelJob(open.id);
    expect(
      (cancelled.status, cancelled.cancelledBy),
      (JobStatus.cancelled, 'customer'),
    );
    expect(cancelled.cancelledAt, isNotNull);
    expect(cancelled.payment.status, PaymentStatus.released);
    expect(gateway.intentForJob(open.id)!.status, 'canceled');
    expect((await customer.cancelJob(open.id)).status, JobStatus.cancelled);
    expect((await customer.properties()).single.activeJob, isNull);
    expect((await customer.billing()).charges, isEmpty);

    // Still possible once a crew member has accepted.
    final crew = await hireCrew(server, admin, 'Riley Plough');
    final accepted = await customer.requestJob(propertyId: property.id);
    await crew.claimJob(accepted.id);
    final withdrawn = await customer.cancelJob(accepted.id);
    expect((withdrawn.status, withdrawn.stepIndex), (JobStatus.cancelled, 1));
    expect(withdrawn.payment.status, PaymentStatus.released);
    expect(gateway.intentForJob(accepted.id)!.status, 'canceled');
    await expectApiError(crew.startJob(accepted.id), 409, 'invalid_state');
    await expectApiError(crew.claimJob(open.id), 409, 'invalid_state');
    expect((await crew.jobs()).single.status, JobStatus.cancelled);
    expect((await crew.crewPay('me')).earnedAllTime, 0);
    expect((await admin.adminDashboard()).counts.cancelledToday, 2);
    expect((await admin.jobs(status: [JobStatus.cancelled])).map((j) => j.id), [
      accepted.id,
      open.id,
    ]);
  });

  test('only the admin can cancel a job that is under way', () async {
    final crew = await hireCrew(server, admin, 'Riley Plough');
    final job = await customer.requestJob(propertyId: property.id);
    await crew.claimJob(job.id);
    await crew.startJob(job.id);
    await expectApiError(customer.cancelJob(job.id), 409, 'job_started');

    final cancelled = await admin.cancelJob(job.id);
    expect(
      (cancelled.status, cancelled.cancelledBy, cancelled.stepIndex),
      (JobStatus.cancelled, 'admin', 2),
    );
    expect(cancelled.payment.status, PaymentStatus.released);
    expect(gateway.intentForJob(job.id)!.status, 'canceled');
    await expectApiError(crew.completeJob(job.id), 409, 'invalid_state');
    expect((await crew.crewPay('me')).unpaidTotal, 0);
  });

  test('a job the admin requests is held on the saved card', () async {
    final byCard = await admin.requestJob(propertyId: property.id);
    expect(
      (byCard.source, byCard.payment.mode, byCard.payment.status),
      ('admin', PaymentMode.stripe, PaymentStatus.authorized),
    );
    expect((await customer.jobs()).single.id, byCard.id);
    await admin.cancelJob(byCard.id);

    final byHand = await admin.requestJob(
      propertyId: property.id,
      payment: 'manual',
    );
    expect(
      (byHand.payment.mode, byHand.payment.status),
      (PaymentMode.manual, PaymentStatus.none),
    );
    expect(gateway.intentForJob(byHand.id), isNull);

    // Without a card on file the job is billed by hand.
    final walkIn = await signUp(server, 'Dana Frost');
    final cottage = await activeProperty(walkIn, admin, name: 'Cottage');
    await expectApiError(
      admin.requestJob(propertyId: cottage.id, payment: 'card'),
      402,
      'card_required',
    );
    final manual = await admin.requestJob(propertyId: cottage.id);
    expect(manual.payment.mode, PaymentMode.manual);
    expect(gateway.intents, hasLength(1));
  });

  test('a failed charge leaves the job done and can be retried', () async {
    final crew = await hireCrew(server, admin, 'Riley Plough');
    final customerId = customer.currentUser!.linkedId!;
    final job = await customer.requestJob(propertyId: property.id);
    gateway.captureOutcomes.add(PaymentOutcome.declined);

    expect((await plough(crew, job.id)).status, JobStatus.done);
    final unpaid = await customer.job(job.id);
    expect(unpaid.status, JobStatus.done);
    expect(unpaid.payment.status, PaymentStatus.failed);
    expect(unpaid.payment.error, gateway.declineMessage);
    final owing = await customer.billing();
    expect(
      (owing.balanceDue, owing.charges.single.status),
      (45, PaymentStatus.failed),
    );
    final issues = await admin.adminDashboard();
    expect(issues.counts.paymentIssues, 1);
    expect(issues.paymentIssues.single.id, job.id);
    var account = await admin.customer(customerId);
    expect((account.billed, account.outstanding), (0, 45));
    // Crew pay does not wait for the customer's money.
    expect((await crew.crewPay('me')).unpaidTotal, 25);

    final retried = await admin.retryJobPayment(job.id);
    expect(retried.payment.status, PaymentStatus.captured);
    expect(retried.payment.error, isNull);
    account = await admin.customer(customerId);
    expect((account.billed, account.outstanding), (45, 0));
    expect((await customer.billing()).balanceDue, 0);
    await expectApiError(admin.retryJobPayment(job.id), 409, 'invalid_state');
  });

  test('a charge whose answer got lost is not made again', () async {
    final crew = await hireCrew(server, admin, 'Riley Plough');
    final job = await customer.requestJob(propertyId: property.id);
    // The hold has lapsed, so finishing the job charges the card afresh.
    // The charge goes through; its answer never reaches the server.
    gateway.expireHold(gateway.intentForJob(job.id)!.id);
    gateway.lostReplies.add(true);

    expect((await plough(crew, job.id)).status, JobStatus.done);
    final unpaid = await admin.job(job.id);
    expect(unpaid.payment.status, PaymentStatus.failed);
    expect(unpaid.payment.error, contains('Retry the payment'));

    final retried = await admin.retryJobPayment(job.id);
    expect(retried.payment.status, PaymentStatus.captured);
    expect(
      gateway.intents.where((i) => i.status == 'succeeded'),
      hasLength(1),
      reason: 'the customer paid once',
    );
    expect((await customer.billing()).balanceDue, 0);
  });

  test('a hold whose answer got lost still ends up with the job', () async {
    gateway.lostReplies.add(true);

    final job = await customer.requestJob(propertyId: property.id);
    expect(job.payment.status, PaymentStatus.authorized);
    expect(gateway.intents.single.status, 'requires_capture');
    await customer.cancelJob(job.id);
    expect(gateway.intents.single.status, 'canceled');
  });

  test('a failed charge can be settled by hand instead', () async {
    final crew = await hireCrew(server, admin, 'Riley Plough');
    final job = await customer.requestJob(propertyId: property.id);
    gateway.captureOutcomes.add(PaymentOutcome.authRequired);
    await plough(crew, job.id);
    expect((await admin.job(job.id)).payment.status, PaymentStatus.failed);

    final paid = await admin.markJobPaid(job.id);
    expect(paid.payment.mode, PaymentMode.stripe);
    expect(paid.payment.status, PaymentStatus.paid);
    expect(paid.payment.error, isNull);
    expect(gateway.intentForJob(job.id)!.status, 'canceled');
    expect(
      (await customer.billing()).charges.single.status,
      PaymentStatus.paid,
    );
  });

  test('a double-tapped request makes one job and one hold', () async {
    gateway.latency = const Duration(milliseconds: 50);

    final outcomes = await Future.wait([
      for (var tap = 0; tap < 2; tap++)
        customer
            .requestJob(propertyId: property.id)
            .then<Object>((j) => j, onError: (Object e) => e),
    ]);
    final job = outcomes.whereType<Job>().single;
    final refused = outcomes.whereType<ApiException>().single;
    expect(refused.statusCode, 409);
    expect(refused.code, anyOf('invalid_state', 'job_active'));
    expect((await customer.jobs()).single.id, job.id);
    expect(gateway.intents.where((i) => i.status == 'requires_capture'), [
      gateway.intentForJob(job.id),
    ]);
  });

  test('two crew members race for a job and one gets it', () async {
    final riley = await hireCrew(server, admin, 'Riley Plough');
    final sam = await hireCrew(server, admin, 'Sam Drift');
    final job = await customer.requestJob(propertyId: property.id);

    final outcomes = await Future.wait([
      for (final crew in [riley, sam])
        crew.claimJob(job.id).then<Object>((j) => j, onError: (Object e) => e),
    ]);
    final won = outcomes.whereType<Job>().single;
    final lost = outcomes.whereType<ApiException>().single;
    expect((lost.statusCode, lost.code), (409, 'already_claimed'));
    expect(won.status, JobStatus.claimed);
    expect(won.crewId, (await admin.job(job.id)).crewId);
    expect(
      won.crewId,
      anyOf(riley.currentUser!.linkedId, sam.currentUser!.linkedId),
    );
  });

  test('a failed save answers 503 and the action can be repeated', () async {
    final crew = await hireCrew(server, admin, 'Riley Plough');
    final job = await customer.requestJob(propertyId: property.id);

    server.failNextSave();
    final failed = await expectApiError(
      crew.claimJob(job.id),
      503,
      'storage_unavailable',
    );
    expect(failed.isNetwork, isFalse);
    expect(crew.isSignedIn, isTrue);
    final claimed = await crew.claimJob(job.id);
    expect(
      (claimed.status, claimed.crewId),
      (JobStatus.claimed, crew.currentUser!.linkedId),
    );
  });

  test('an open job nobody takes in time is cancelled by the server', () async {
    final job = await customer.requestJob(propertyId: property.id);
    final settings = await admin.updateSettings(openJobExpiryHours: 1);
    expect(settings.openJobExpiryHours, 1);

    server.advance(const Duration(minutes: 61));
    final expired = await customer.job(job.id);
    expect(
      (expired.status, expired.cancelledBy),
      (JobStatus.cancelled, 'system'),
    );
    // The hold is let go right after, without holding that request up.
    final released = await eventually(
      () => customer.job(job.id),
      (j) => j.payment.status == PaymentStatus.released,
    );
    expect(released.payment.error, isNull);
    expect(gateway.intentForJob(job.id)!.status, 'canceled');
    expect((await customer.properties()).single.activeJob, isNull);
  });
}

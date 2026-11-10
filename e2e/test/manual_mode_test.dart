import 'package:redefine_core/redefine_core.dart';
import 'package:redefine_e2e/redefine_e2e.dart';
import 'package:test/test.dart';

import 'support/harness.dart';

void main() {
  late TestServer server;
  late ApiClient lia, sarah, marcus;

  setUp(() async {
    server = await startServer(stripe: false, seed: true);
    lia = await signIn(server, 'lia@redefine.co');
    sarah = await signIn(server, 'sarah.m@gmail.com');
    marcus = await signIn(server, 'marcus@redefine.co');
  });

  test('a finished job is due until the admin marks it paid', () async {
    expect((await sarah.settings()).paymentsMode, PaymentMode.manual);
    final before = await sarah.billing();
    expect(before.mode, PaymentMode.manual);
    expect(before.needsCard, isFalse);
    expect(before.card, isNull);
    expect(before.balanceDue, 0);
    await expectApiError(
      sarah.createCardSetupSession(),
      409,
      'payments_manual',
    );

    final job = await sarah.requestJob(propertyId: 'prop_maple');
    expect(job.payment.mode, PaymentMode.manual);
    expect(job.payment.status, PaymentStatus.none);
    expect((job.price, job.shovelPrice, job.total), (45, 0, 45));
    expect(
      (await sarah.billing()).charges.map((c) => c.jobId),
      isNot(contains(job.id)),
    );

    await plough(marcus, job.id);
    final done = await sarah.job(job.id);
    expect(done.status, JobStatus.done);
    expect(done.payment.status, PaymentStatus.due);
    expect(done.payment.capturedAt, isNull);
    final owing = await sarah.billing();
    expect(owing.balanceDue, 45);
    expect(
      (owing.charges.first.jobId, owing.charges.first.status),
      (job.id, PaymentStatus.due),
    );

    final issues = await lia.adminDashboard();
    expect(issues.counts.paymentIssues, 2);
    expect(issues.paymentIssues.map((j) => j.id), [job.id, 'job_cedar_1']);
    expect((issues.counts.doneToday, issues.counts.revenueToday), (1, 45));
    expect((await lia.jobs(payment: [PaymentStatus.due])).map((j) => j.id), [
      job.id,
      'job_cedar_1',
    ]);
    await expectApiError(lia.retryJobPayment(job.id), 409, 'invalid_state');

    final paid = await lia.markJobPaid(job.id);
    expect(paid.payment.mode, PaymentMode.manual);
    expect(paid.payment.status, PaymentStatus.paid);
    expect(paid.payment.capturedAt, isNotNull);
    final cleared = await sarah.billing();
    expect(cleared.balanceDue, 0);
    expect(cleared.charges.first.status, PaymentStatus.paid);
    expect((await lia.adminDashboard()).counts.paymentIssues, 1);
    await expectApiError(lia.markJobPaid('job_cedar_2'), 409, 'invalid_state');
  });

  test('the admin requests and cancels a plough for a customer', () async {
    await expectApiError(
      lia.requestJob(propertyId: 'prop_maple', payment: 'card'),
      409,
      'payments_manual',
    );
    final job = await lia.requestJob(
      propertyId: 'prop_maple',
      shovel: true,
      note: 'Phoned in',
    );
    expect((job.source, job.customerId), ('admin', 'cust_sarah'));
    expect((job.total, job.crewPay), (65, 35));
    expect(job.payment.mode, PaymentMode.manual);
    expect((await sarah.jobs()).first.id, job.id);
    expect((await sarah.properties()).first.activeJob?.id, job.id);

    final cancelled = await lia.cancelJob(job.id);
    expect(
      (cancelled.status, cancelled.cancelledBy),
      (JobStatus.cancelled, 'admin'),
    );
    expect((await sarah.properties()).first.activeJob, isNull);
    expect(await marcus.jobs(scope: 'open'), hasLength(1));
  });

  test('crew can release a job and the admin can step in', () async {
    final jordan = await signIn(server, 'jordan@redefine.co');
    const jobId = 'job_cedar_2';

    expect((await marcus.claimJob(jobId)).status, JobStatus.claimed);
    expect((await marcus.claimJob(jobId)).status, JobStatus.claimed);
    final released = await marcus.unclaimJob(jobId);
    expect((released.status, released.crewId), (JobStatus.open, ''));
    expect(released.claimedAt, isNull);
    await expectApiError(marcus.startJob(jobId), 409, 'invalid_state');
    expect(await marcus.jobs(), hasLength(3));

    await jordan.claimJob(jobId);
    final reopened = await lia.unclaimJob(jobId);
    expect((reopened.status, reopened.crewName), (JobStatus.open, ''));
    await expectApiError(lia.completeJob(jobId), 409, 'invalid_state');

    await jordan.claimJob(jobId);
    final done = await lia.completeJob(jobId, crewNote: 'Confirmed by phone.');
    expect((done.status, done.crewId), (JobStatus.done, 'crew_jordan'));
    expect(done.payment.status, PaymentStatus.due);
    expect(done.crewNote, 'Confirmed by phone.');
    expect((await jordan.completeJob(jobId)).status, JobStatus.done);
    expect((await jordan.crewPay('me')).unpaidTotal, 30 + 40);
  });
}

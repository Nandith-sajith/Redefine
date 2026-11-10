import 'package:redefine_api/src/payments/fake_gateway.dart';
import 'package:redefine_api/src/payments/gateway.dart';
import 'package:test/test.dart';

void main() {
  late FakePaymentGateway gateway;

  setUp(() => gateway = FakePaymentGateway());

  Future<String> customer() => gateway.createCustomer(
    appCustomerId: 'cust_sarah',
    name: 'Sarah Mitchell',
    email: 'sarah.m@gmail.com',
  );

  Future<HoldResult> hold(
    String stripeCustomerId, {
    int amount = 65,
    String jobId = 'job_1',
  }) => gateway.authorize(
    jobId: jobId,
    stripeCustomerId: stripeCustomerId,
    paymentMethodId: 'pm_fake_1',
    amountDollars: amount,
  );

  test('reports a stripe-test mode unless told otherwise', () {
    expect(gateway.mode, 'stripe-test');
    expect(FakePaymentGateway(mode: 'stripe-live').mode, 'stripe-live');
  });

  test('card setup completes automatically by default', () async {
    final cus = await customer();
    final session = await gateway.createSetupSession(
      stripeCustomerId: cus,
      appCustomerId: 'cust_sarah',
      successUrl: 'https://api/billing/return?session_id={CHECKOUT_SESSION_ID}',
      cancelUrl: 'https://api/billing/return?cancelled=1',
    );
    expect(session.url, startsWith('https://'));

    final card = await gateway.fetchSetupResult(
      session.id,
      expectedStripeCustomerId: cus,
    );
    expect(card!.brand, 'visa');
    expect(card.last4, '4242');
    expect(card.paymentMethodId, isNotEmpty);
    expect(
      await gateway.fetchSetupResult(
        session.id,
        expectedStripeCustomerId: 'cus_other',
      ),
      isNull,
    );
  });

  test('card setup can be left pending and completed by the test', () async {
    gateway.autoCompleteSetup = false;
    final cus = await customer();
    final session = await gateway.createSetupSession(
      stripeCustomerId: cus,
      appCustomerId: 'cust_sarah',
      successUrl: 's',
      cancelUrl: 'c',
    );
    expect(
      await gateway.fetchSetupResult(session.id, expectedStripeCustomerId: cus),
      isNull,
    );

    gateway.completeSetup(session.id, brand: 'mastercard', last4: '4444');
    final card = await gateway.fetchSetupResult(
      session.id,
      expectedStripeCustomerId: cus,
    );
    expect(card!.brand, 'mastercard');
    expect(card.last4, '4444');
    expect(() => gateway.completeSetup('cs_unknown'), throwsArgumentError);
  });

  test('hold, capture and cancel move the intent through its states', () async {
    final cus = await customer();
    final held = await hold(cus);
    expect(held.isOk, isTrue);
    final intent = gateway.intent(held.paymentIntentId!)!;
    expect(intent.status, 'requires_capture');
    expect(intent.amountDollars, 65);
    expect(gateway.intentForJob('job_1'), same(intent));

    final captured = await gateway.capture(
      jobId: 'job_1',
      paymentIntentId: intent.id,
    );
    expect(captured.isOk, isTrue);
    expect(captured.paymentIntentId, intent.id);
    expect(intent.status, 'succeeded');
    await expectLater(
      gateway.cancel(intent.id),
      throwsA(isA<PaymentException>()),
    );

    final second = await hold(cus, jobId: 'job_2');
    await gateway.cancel(second.paymentIntentId!);
    await gateway.cancel(second.paymentIntentId!);
    expect(gateway.intent(second.paymentIntentId!)!.status, 'canceled');
    expect(gateway.intents, hasLength(2));
  });

  test('scripted outcomes are consumed in order, then ok again', () async {
    final cus = await customer();
    gateway.authorizeOutcomes.addAll([
      PaymentOutcome.declined,
      PaymentOutcome.authRequired,
      PaymentOutcome.unavailable,
    ]);
    gateway.declineMessage = 'Insufficient funds.';

    final declined = await hold(cus);
    expect(declined.outcome, PaymentOutcome.declined);
    expect(declined.message, 'Insufficient funds.');
    expect(declined.paymentIntentId, isNull);
    expect(
      (await hold(cus, jobId: 'job_2')).outcome,
      PaymentOutcome.authRequired,
    );
    final error = await hold(cus, jobId: 'job_3');
    expect(error.outcome, PaymentOutcome.unavailable);
    expect(error.inDoubt, isFalse, reason: 'the service did answer');
    expect(gateway.intents, isEmpty);
    expect((await hold(cus, jobId: 'job_4')).isOk, isTrue);
  });

  test('the same call again gets the first answer', () async {
    final cus = await customer();
    gateway.authorizeOutcomes.add(PaymentOutcome.declined);
    expect((await hold(cus)).outcome, PaymentOutcome.declined);
    expect((await hold(cus)).outcome, PaymentOutcome.declined);
    expect(gateway.intents, isEmpty);

    final held = await hold(cus, jobId: 'job_2');
    final again = await hold(cus, jobId: 'job_2');
    expect(again.paymentIntentId, held.paymentIntentId);
    expect(gateway.intents, hasLength(1));

    // An error answer is not remembered: the call can be made again.
    gateway.authorizeOutcomes.add(PaymentOutcome.unavailable);
    expect(
      (await hold(cus, jobId: 'job_3')).outcome,
      PaymentOutcome.unavailable,
    );
    expect((await hold(cus, jobId: 'job_3')).isOk, isTrue);
  });

  test(
    'a lost reply leaves the caller in doubt; asking again settles it',
    () async {
      final cus = await customer();
      gateway.lostReplies.add(true);
      final lost = await hold(cus);
      expect(lost.outcome, PaymentOutcome.unavailable);
      expect(lost.inDoubt, isTrue);
      expect(lost.paymentIntentId, isNull);
      // The hold was placed all the same.
      final intent = gateway.intents.single;
      expect(intent.status, 'requires_capture');
      final again = await hold(cus);
      expect(again.isOk, isTrue);
      expect(again.paymentIntentId, intent.id);
      expect(gateway.intents, hasLength(1));

      // The same for a fresh charge of an expired hold.
      gateway.expireHold(intent.id);
      gateway.lostReplies.add(true);
      final capture = await gateway.capture(
        jobId: 'job_1',
        paymentIntentId: intent.id,
      );
      expect(
        (capture.outcome, capture.inDoubt),
        (PaymentOutcome.unavailable, true),
      );
      final charge = gateway.intentForJob('job_1')!;
      expect(charge.status, 'succeeded');
      final repeated = await gateway.capture(
        jobId: 'job_1',
        paymentIntentId: intent.id,
      );
      expect(repeated.paymentIntentId, charge.id);
      expect(gateway.intents.where((i) => i.status == 'succeeded'), [charge]);
    },
  );

  test('a job that was paid is never charged again', () async {
    final cus = await customer();
    final first = await gateway.chargeNow(
      jobId: 'job_1',
      stripeCustomerId: cus,
      paymentMethodId: 'pm_fake_1',
      amountDollars: 65,
    );
    final second = await gateway.chargeNow(
      jobId: 'job_1',
      stripeCustomerId: cus,
      paymentMethodId: 'pm_fake_2',
      amountDollars: 65,
      attempt: 7,
    );
    expect(second.isOk, isTrue);
    expect(second.paymentIntentId, first.paymentIntentId);
    expect(gateway.intents, hasLength(1));
  });

  test('a scripted capture failure leaves the hold in place', () async {
    final cus = await customer();
    final held = await hold(cus);
    gateway.captureOutcomes.add(PaymentOutcome.declined);

    final failed = await gateway.capture(
      jobId: 'job_1',
      paymentIntentId: held.paymentIntentId!,
    );
    expect(failed.outcome, PaymentOutcome.declined);
    expect(gateway.intent(held.paymentIntentId!)!.status, 'requires_capture');

    gateway.chargeOutcomes.add(PaymentOutcome.authRequired);
    final charge = await gateway.chargeNow(
      jobId: 'job_1',
      stripeCustomerId: cus,
      paymentMethodId: 'pm_fake_1',
      amountDollars: 65,
      attempt: 1,
    );
    expect(charge.outcome, PaymentOutcome.authRequired);

    final retried = await gateway.chargeNow(
      jobId: 'job_1',
      stripeCustomerId: cus,
      paymentMethodId: 'pm_fake_1',
      amountDollars: 65,
      attempt: 2,
    );
    expect(retried.isOk, isTrue);
    expect(gateway.intent(retried.paymentIntentId!)!.status, 'succeeded');
  });

  test('capturing an expired hold charges afresh under a new intent', () async {
    final cus = await customer();
    final held = await hold(cus, amount: 45);
    gateway.expireHold(held.paymentIntentId!);

    final captured = await gateway.capture(
      jobId: 'job_1',
      paymentIntentId: held.paymentIntentId!,
    );
    expect(captured.isOk, isTrue);
    expect(captured.paymentIntentId, isNot(held.paymentIntentId));
    final charge = gateway.intent(captured.paymentIntentId!)!;
    expect(charge.status, 'succeeded');
    expect(charge.amountDollars, 45);
    expect(gateway.intentForJob('job_1'), same(charge));
    expect(() => gateway.expireHold(charge.id), throwsArgumentError);
  });

  test(
    'while unavailable every call fails the way the real one would',
    () async {
      final cus = await customer();
      final held = await hold(cus);
      gateway.unavailable = true;

      final noHold = await hold(cus, jobId: 'job_2');
      expect(
        (noHold.outcome, noHold.inDoubt),
        (PaymentOutcome.unavailable, true),
      );
      final noCapture = await gateway.capture(
        jobId: 'job_1',
        paymentIntentId: held.paymentIntentId!,
      );
      expect(
        (noCapture.outcome, noCapture.inDoubt),
        (PaymentOutcome.unavailable, true),
      );
      expect(gateway.intents, hasLength(1), reason: 'nothing was carried out');
      await expectLater(customer(), throwsA(isA<PaymentException>()));
      await expectLater(
        gateway.cancel(held.paymentIntentId!),
        throwsA(isA<PaymentException>()),
      );
      expect(gateway.intent(held.paymentIntentId!)!.status, 'requires_capture');

      gateway.unavailable = false;
      await gateway.cancel(held.paymentIntentId!);
    },
  );

  test('records every call with its arguments', () async {
    final cus = await customer();
    await hold(cus);
    await gateway.cancel(gateway.intents.single.id);

    expect(gateway.calls.map((c) => c.method), [
      'createCustomer',
      'authorize',
      'cancel',
    ]);
    expect(gateway.callsTo('authorize').single.args, {
      'jobId': 'job_1',
      'stripeCustomerId': cus,
      'paymentMethodId': 'pm_fake_1',
      'amountDollars': 65,
      'attempt': 0,
    });
    expect(gateway.callsTo('capture'), isEmpty);
  });

  test('calls take a real event-loop turn', () async {
    var done = false;
    final pending = customer().then((_) => done = true);
    await Future<void>.value();
    expect(done, isFalse);
    await pending;
    expect(done, isTrue);
  });
}

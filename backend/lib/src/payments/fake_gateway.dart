import 'dart:collection';

import 'gateway.dart';

const _serviceError = 'Fake: the payment service answered with an error.';
const _noReply = 'Fake: no reply from the payment service.';
const _noHold = HoldResult.unavailable(_noReply, inDoubt: true);
const _noCapture = CaptureResult.unavailable(_noReply, inDoubt: true);

/// One recorded call to a [FakePaymentGateway].
class GatewayCall {
  /// Name of the gateway method (`authorize`, `capture`, ...).
  final String method;

  /// The arguments it was called with, by parameter name.
  final Map<String, Object?> args;

  const GatewayCall(this.method, this.args);

  @override
  String toString() => '$method$args';
}

/// A payment intent held by a [FakePaymentGateway].
class FakeIntent {
  /// The payment intent id (`pi_fake_<n>`).
  final String id;

  /// The job the hold or charge was made for.
  final String jobId;

  /// The payment-side customer that was charged.
  final String stripeCustomerId;

  /// The card that was charged.
  final String paymentMethodId;

  /// The held or charged amount.
  final int amountDollars;

  /// `requires_capture` (hold), `succeeded` (charged) or `canceled`.
  String status;

  FakeIntent._(
    this.id,
    this.jobId,
    this.stripeCustomerId,
    this.paymentMethodId,
    this.amountDollars,
    this.status,
  );
}

/// In-memory [PaymentGateway] for tests: everything succeeds unless scripted
/// otherwise, and every call is recorded.
///
/// Like the real service it remembers what it answered to a hold, capture or
/// charge: the same call again (same job and attempt) gets the first answer
/// instead of being carried out twice.
class FakePaymentGateway implements PaymentGateway {
  @override
  final String mode;

  /// Every call made so far, oldest first.
  final List<GatewayCall> calls = [];

  /// Outcomes for the next [authorize] calls (first in, first out); `ok`
  /// once empty. A scripted `unavailable` is an error answer from the
  /// service: nothing happened and nothing is in doubt.
  final Queue<PaymentOutcome> authorizeOutcomes = Queue();

  /// Outcomes for the next [capture] calls; `ok` once empty.
  final Queue<PaymentOutcome> captureOutcomes = Queue();

  /// Outcomes for the next [chargeNow] calls; `ok` once empty.
  final Queue<PaymentOutcome> chargeOutcomes = Queue();

  /// While true every call fails as if the payment service could not be
  /// reached: result-returning calls answer `unavailable` and in doubt, the
  /// others throw. Nothing is carried out.
  bool unavailable = false;

  /// Whether the answers to the next hold, capture and charge calls get lost
  /// (first in, first out; none once empty). Such a call is carried out all
  /// the same, but the caller sees `unavailable` and in doubt.
  final Queue<bool> lostReplies = Queue();

  /// When true (default) a setup session is complete as soon as it is
  /// created; when false call [completeSetup] first.
  bool autoCompleteSetup = true;

  /// Simulated network delay of every call.
  Duration latency = Duration.zero;

  /// Message used for scripted declines.
  String declineMessage = 'Your card was declined.';

  final Map<String, FakeIntent> _intents = {};
  final Map<String, PaymentResult> _answers = {};
  final Map<String, String> _customers = {};
  final Map<String, ({String customer, SavedCard? card})> _sessions = {};
  int _seq = 0;

  FakePaymentGateway({this.mode = 'stripe-test'});

  /// The recorded calls to [method].
  List<GatewayCall> callsTo(String method) =>
      calls.where((c) => c.method == method).toList();

  /// Every intent created so far, oldest first.
  List<FakeIntent> get intents => _intents.values.toList();

  /// The intent with [id], or null.
  FakeIntent? intent(String id) => _intents[id];

  /// The newest intent created for [jobId], or null.
  FakeIntent? intentForJob(String jobId) =>
      _intents.values.where((i) => i.jobId == jobId).lastOrNull;

  /// Marks setup session [sessionId] as completed with the given card.
  void completeSetup(
    String sessionId, {
    String brand = 'visa',
    String last4 = '4242',
    int expMonth = 12,
    int expYear = 2030,
  }) {
    final session = _sessions[sessionId];
    if (session == null) throw ArgumentError.value(sessionId, 'sessionId');
    _sessions[sessionId] = (
      customer: session.customer,
      card: SavedCard(
        paymentMethodId: 'pm_fake_${++_seq}',
        brand: brand,
        last4: last4,
        expMonth: expMonth,
        expYear: expYear,
      ),
    );
  }

  /// Simulates a hold that expired on the payment side: capturing it falls
  /// back to a fresh charge, as the real gateway does.
  void expireHold(String paymentIntentId) {
    final intent = _intents[paymentIntentId];
    if (intent == null || intent.status != 'requires_capture') {
      throw ArgumentError.value(paymentIntentId, 'paymentIntentId');
    }
    intent.status = 'canceled';
  }

  @override
  Future<String> createCustomer({
    required String appCustomerId,
    required String name,
    required String email,
  }) async {
    await _enter('createCustomer', {
      'appCustomerId': appCustomerId,
      'name': name,
      'email': email,
    });
    _failIfDown('createCustomer');
    final id = 'cus_fake_${++_seq}';
    _customers[id] = appCustomerId;
    return id;
  }

  @override
  Future<SetupSession> createSetupSession({
    required String stripeCustomerId,
    required String appCustomerId,
    required String successUrl,
    required String cancelUrl,
  }) async {
    await _enter('createSetupSession', {
      'stripeCustomerId': stripeCustomerId,
      'appCustomerId': appCustomerId,
      'successUrl': successUrl,
      'cancelUrl': cancelUrl,
    });
    _failIfDown('createSetupSession');
    if (!_customers.containsKey(stripeCustomerId)) {
      throw PaymentException('Fake: no such customer $stripeCustomerId.');
    }
    final id = 'cs_fake_${++_seq}';
    _sessions[id] = (customer: stripeCustomerId, card: null);
    if (autoCompleteSetup) completeSetup(id);
    return SetupSession(id: id, url: 'https://checkout.fake/setup/$id');
  }

  @override
  Future<SavedCard?> fetchSetupResult(
    String sessionId, {
    required String expectedStripeCustomerId,
  }) async {
    await _enter('fetchSetupResult', {
      'sessionId': sessionId,
      'expectedStripeCustomerId': expectedStripeCustomerId,
    });
    _failIfDown('fetchSetupResult');
    final session = _sessions[sessionId];
    if (session == null) {
      throw PaymentException('Fake: no such setup session $sessionId.');
    }
    return session.customer == expectedStripeCustomerId ? session.card : null;
  }

  @override
  Future<HoldResult> authorize({
    required String jobId,
    required String stripeCustomerId,
    required String paymentMethodId,
    required int amountDollars,
    int attempt = 0,
  }) async {
    await _enter('authorize', {
      'jobId': jobId,
      'stripeCustomerId': stripeCustomerId,
      'paymentMethodId': paymentMethodId,
      'amountDollars': amountDollars,
      'attempt': attempt,
    });
    return _answer('hold-$jobId-$attempt', _noHold, () {
      switch (_next(authorizeOutcomes)) {
        case PaymentOutcome.ok:
          final intent = _newIntent(
            jobId,
            stripeCustomerId,
            paymentMethodId,
            amountDollars,
            'requires_capture',
          );
          return HoldResult.ok(intent.id);
        case PaymentOutcome.declined:
          return HoldResult.declined(declineMessage);
        case PaymentOutcome.authRequired:
          return const HoldResult.authRequired();
        case PaymentOutcome.unavailable:
          return const HoldResult.unavailable(_serviceError);
      }
    });
  }

  @override
  Future<CaptureResult> capture({
    required String jobId,
    required String paymentIntentId,
    int attempt = 0,
  }) async {
    await _enter('capture', {
      'jobId': jobId,
      'paymentIntentId': paymentIntentId,
      'attempt': attempt,
    });
    return _answer('capture-$jobId-$attempt', _noCapture, () {
      final outcome = _next(captureOutcomes);
      if (outcome != PaymentOutcome.ok) return _failedCapture(outcome);
      final intent = _intents[paymentIntentId];
      switch (intent?.status) {
        case 'requires_capture':
          intent!.status = 'succeeded';
          return CaptureResult.ok(intent.id);
        case 'succeeded':
          return CaptureResult.ok(intent!.id);
        case 'canceled':
          return _charge(
            jobId,
            intent!.stripeCustomerId,
            intent.paymentMethodId,
            intent.amountDollars,
          );
        default:
          return CaptureResult.unavailable(
            'Fake: no such payment intent $paymentIntentId.',
          );
      }
    });
  }

  @override
  Future<CaptureResult> chargeNow({
    required String jobId,
    required String stripeCustomerId,
    required String paymentMethodId,
    required int amountDollars,
    int attempt = 0,
  }) async {
    await _enter('chargeNow', {
      'jobId': jobId,
      'stripeCustomerId': stripeCustomerId,
      'paymentMethodId': paymentMethodId,
      'amountDollars': amountDollars,
      'attempt': attempt,
    });
    return _answer('charge-$jobId-$attempt', _noCapture, () {
      final outcome = _next(chargeOutcomes);
      if (outcome != PaymentOutcome.ok) return _failedCapture(outcome);
      return _charge(jobId, stripeCustomerId, paymentMethodId, amountDollars);
    });
  }

  @override
  Future<void> cancel(String paymentIntentId) async {
    await _enter('cancel', {'paymentIntentId': paymentIntentId});
    _failIfDown('cancel');
    final intent = _intents[paymentIntentId];
    if (intent == null) {
      throw PaymentException('Fake: no such payment intent $paymentIntentId.');
    }
    if (intent.status == 'succeeded') {
      throw PaymentException(
        'Fake: $paymentIntentId is already captured and cannot be cancelled.',
      );
    }
    intent.status = 'canceled';
  }

  Future<void> _enter(String method, Map<String, Object?> args) async {
    calls.add(GatewayCall(method, args));
    // Always a real event-loop turn, like a network call, so other requests
    // can interleave exactly where they would against the real gateway.
    await Future<void>.delayed(latency);
  }

  void _failIfDown(String method) {
    if (unavailable) {
      throw PaymentException('Fake: payment service is down ($method).');
    }
  }

  /// The answer to the call made under idempotency [key]: the remembered
  /// one, else what [act] does now. [noReply] stands in when the service
  /// cannot be reached or its answer is lost on the way back.
  R _answer<R extends PaymentResult>(String key, R noReply, R Function() act) {
    if (unavailable) return noReply;
    var answer = _answers[key] as R?;
    if (answer == null) {
      answer = act();
      if (answer.outcome != PaymentOutcome.unavailable) _answers[key] = answer;
    }
    final lost = lostReplies.isNotEmpty && lostReplies.removeFirst();
    return lost ? noReply : answer;
  }

  PaymentOutcome _next(Queue<PaymentOutcome> scripted) =>
      scripted.isEmpty ? PaymentOutcome.ok : scripted.removeFirst();

  CaptureResult _failedCapture(PaymentOutcome outcome) => switch (outcome) {
    PaymentOutcome.declined => CaptureResult.declined(declineMessage),
    PaymentOutcome.authRequired => const CaptureResult.authRequired(),
    _ => const CaptureResult.unavailable(_serviceError),
  };

  /// Charges the card, unless a payment for [jobId] already succeeded.
  CaptureResult _charge(
    String jobId,
    String stripeCustomerId,
    String paymentMethodId,
    int amountDollars,
  ) {
    final paid = _intents.values
        .where((i) => i.jobId == jobId && i.status == 'succeeded')
        .firstOrNull;
    final charge =
        paid ??
        _newIntent(
          jobId,
          stripeCustomerId,
          paymentMethodId,
          amountDollars,
          'succeeded',
        );
    return CaptureResult.ok(charge.id);
  }

  FakeIntent _newIntent(
    String jobId,
    String stripeCustomerId,
    String paymentMethodId,
    int amountDollars,
    String status,
  ) {
    final intent = FakeIntent._(
      'pi_fake_${++_seq}',
      jobId,
      stripeCustomerId,
      paymentMethodId,
      amountDollars,
      status,
    );
    return _intents[intent.id] = intent;
  }
}

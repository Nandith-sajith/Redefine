/// How a card operation ended.
enum PaymentOutcome {
  /// The hold was placed / the money was captured.
  ok,

  /// The card was declined; `message` says why.
  declined,

  /// The card needs customer authentication and cannot be used off-session.
  authRequired,

  /// The payment service could not be reached or answered unexpectedly.
  unavailable,
}

/// A hosted card-setup page the customer is sent to.
class SetupSession {
  /// The session id to pass to [PaymentGateway.fetchSetupResult].
  final String id;

  /// The hosted page to open in the customer's browser.
  final String url;

  const SetupSession({required this.id, required this.url});
}

/// A card saved through a completed setup session.
class SavedCard {
  /// The reusable payment method to charge (private to the server).
  final String paymentMethodId;

  /// Card network, e.g. `visa`.
  final String brand;

  /// Last four digits of the card number.
  final String last4;

  /// Expiry month, 1-12.
  final int expMonth;

  /// Four-digit expiry year.
  final int expYear;

  const SavedCard({
    required this.paymentMethodId,
    required this.brand,
    required this.last4,
    required this.expMonth,
    required this.expYear,
  });
}

/// Common shape of [HoldResult] and [CaptureResult].
abstract class PaymentResult {
  /// How the operation ended.
  final PaymentOutcome outcome;

  /// The payment intent that now holds/charged the money; set only when ok.
  final String? paymentIntentId;

  /// Reason for a decline (customer-presentable) or an outage (for logs and
  /// `payment.error`); null when ok or authRequired.
  final String? message;

  /// True when the payment service gave no usable answer, so the operation
  /// may or may not have happened. Repeat the call with the SAME attempt
  /// number: the service then gives its first answer instead of acting
  /// twice. Only ever true together with [PaymentOutcome.unavailable].
  final bool inDoubt;

  const PaymentResult(
    this.outcome, {
    this.paymentIntentId,
    this.message,
    this.inDoubt = false,
  });

  /// Whether the hold was placed / the money was captured.
  bool get isOk => outcome == PaymentOutcome.ok;

  @override
  String toString() =>
      '$runtimeType(${outcome.name}'
      '${inDoubt ? ', in doubt' : ''}'
      '${paymentIntentId == null ? '' : ', $paymentIntentId'}'
      '${message == null ? '' : ', $message'})';
}

/// Result of [PaymentGateway.authorize].
class HoldResult extends PaymentResult {
  /// The hold was placed as [paymentIntentId].
  const HoldResult.ok(String paymentIntentId)
    : super(PaymentOutcome.ok, paymentIntentId: paymentIntentId);

  /// The card was declined; [message] is the customer-presentable reason.
  const HoldResult.declined(String message)
    : super(PaymentOutcome.declined, message: message);

  /// The card needs authentication the customer is not present for.
  const HoldResult.authRequired() : super(PaymentOutcome.authRequired);

  /// The payment service failed; [message] is for logs.
  const HoldResult.unavailable(String message, {super.inDoubt})
    : super(PaymentOutcome.unavailable, message: message);
}

/// Result of [PaymentGateway.capture] and [PaymentGateway.chargeNow].
///
/// When ok, [paymentIntentId] may differ from the hold that was captured
/// (an expired hold is replaced by a fresh charge): store it.
class CaptureResult extends PaymentResult {
  /// The money was captured under [paymentIntentId].
  const CaptureResult.ok(String paymentIntentId)
    : super(PaymentOutcome.ok, paymentIntentId: paymentIntentId);

  /// The charge was declined; [message] is the customer-presentable reason.
  const CaptureResult.declined(String message)
    : super(PaymentOutcome.declined, message: message);

  /// The card needs authentication the customer is not present for.
  const CaptureResult.authRequired() : super(PaymentOutcome.authRequired);

  /// The payment service failed; [message] is for logs.
  const CaptureResult.unavailable(String message, {super.inDoubt})
    : super(PaymentOutcome.unavailable, message: message);
}

/// Thrown by the gateway calls that have no result type when the payment
/// service fails. The `errors` middleware answers 502 `payment_unavailable`;
/// [message] is for logs, not for customers.
class PaymentException implements Exception {
  /// What failed, for logs.
  final String message;
  const PaymentException(this.message);

  @override
  String toString() => 'PaymentException: $message';
}

/// Card payments. Absent (null) when the server runs in manual mode.
abstract interface class PaymentGateway {
  /// `stripe-test` or `stripe-live`.
  String get mode;

  /// Creates the payment-side customer; returns its id.
  /// Throws [PaymentException].
  Future<String> createCustomer({
    required String appCustomerId,
    required String name,
    required String email,
  });

  /// Starts a hosted card-setup session. Throws [PaymentException].
  Future<SetupSession> createSetupSession({
    required String stripeCustomerId,
    required String appCustomerId,
    required String successUrl,
    required String cancelUrl,
  });

  /// The card saved by setup session [sessionId], or null while the session
  /// is not successfully completed or belongs to another customer.
  /// Throws [PaymentException].
  Future<SavedCard?> fetchSetupResult(
    String sessionId, {
    required String expectedStripeCustomerId,
  });

  /// Places a hold of [amountDollars] on the saved card. Never throws for
  /// payment failures. Use a new [attempt] to retry after a failure, but the
  /// same one after a result that is [PaymentResult.inDoubt].
  Future<HoldResult> authorize({
    required String jobId,
    required String stripeCustomerId,
    required String paymentMethodId,
    required int amountDollars,
    int attempt = 0,
  });

  /// Captures a hold; an expired hold is replaced by a fresh charge of the
  /// same card and amount. Never throws for payment failures. Use a new
  /// [attempt] to retry after a failure, but the same one after a result
  /// that is [PaymentResult.inDoubt].
  Future<CaptureResult> capture({
    required String jobId,
    required String paymentIntentId,
    int attempt = 0,
  });

  /// Charges [amountDollars] immediately, without a prior hold; a payment
  /// that already succeeded for [jobId] is returned instead of charging
  /// again. Never throws for payment failures. Use a new [attempt] to retry
  /// after a failure, but the same one after a result that is
  /// [PaymentResult.inDoubt]; the attempt numbers are shared with the
  /// fallback charge made by [capture].
  Future<CaptureResult> chargeNow({
    required String jobId,
    required String stripeCustomerId,
    required String paymentMethodId,
    required int amountDollars,
    int attempt = 0,
  });

  /// Releases a hold; an already-released hold counts as success.
  /// Throws [PaymentException].
  Future<void> cancel(String paymentIntentId);
}

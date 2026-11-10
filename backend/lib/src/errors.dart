/// An error the API reports to the caller as `{error, code, ...extra}`.
///
/// Throw one from anywhere under the `errors` middleware; the factories cover
/// every status/code pair in the contract.
class ApiError implements Exception {
  /// HTTP status of the response.
  final int status;

  /// Machine-readable code (`validation`, `not_found`, ...).
  final String code;

  /// Human-readable sentence shown to the user.
  final String message;

  /// Extra top-level fields merged into the error body (e.g. `jobId`).
  final Map<String, Object?> extra;

  const ApiError(this.status, this.code, this.message, {this.extra = const {}});

  /// 400: malformed JSON, body not an object, body too large.
  factory ApiError.badRequest(String message) =>
      ApiError(400, 'bad_request', message);

  /// 400: a field is missing or invalid; [message] names the field.
  factory ApiError.validation(String message) =>
      ApiError(400, 'validation', message);

  /// 401: missing, unknown or expired token.
  factory ApiError.unauthorized() =>
      const ApiError(401, 'unauthorized', 'Sign in to continue.');

  /// 401: wrong email or password on login.
  factory ApiError.invalidCredentials() => const ApiError(
    401,
    'invalid_credentials',
    'The email or password is incorrect.',
  );

  /// 402: stripe mode and the customer has no saved card.
  factory ApiError.cardRequired() => const ApiError(
    402,
    'card_required',
    'Add a payment card before requesting a plough.',
  );

  /// 402: the hold was declined.
  factory ApiError.cardDeclined([String? message]) => ApiError(
    402,
    'card_declined',
    message == null || message.isEmpty ? 'The card was declined.' : message,
  );

  /// 402: the card needs extra authentication and cannot be used off-session.
  factory ApiError.cardAuthRequired() => const ApiError(
    402,
    'card_auth_required',
    'The card needs extra authentication. Save the card again to continue.',
  );

  /// 403: authenticated but the role may not use the route.
  factory ApiError.forbidden() => const ApiError(
    403,
    'forbidden',
    'This account is not allowed to do that.',
  );

  /// 403: crew member still awaiting approval.
  factory ApiError.crewPending() => const ApiError(
    403,
    'crew_pending',
    'Your crew application has not been approved yet.',
  );

  /// 403: crew member was rejected.
  factory ApiError.crewRejected() => const ApiError(
    403,
    'crew_rejected',
    'Your crew application was not approved.',
  );

  /// 403: admin signup without a valid invite code.
  factory ApiError.inviteRequired() => const ApiError(
    403,
    'invite_required',
    'A valid invite code is required to create an admin account.',
  );

  /// 404: unknown id, or a resource the caller may not see.
  factory ApiError.notFound([String what = 'Resource']) =>
      ApiError(404, 'not_found', '$what not found.');

  /// 409: signup with an existing email.
  factory ApiError.emailTaken() => const ApiError(
    409,
    'email_taken',
    'An account with that email already exists.',
  );

  /// 409: the property already has an unfinished job; the body carries `jobId`.
  factory ApiError.jobActive(String jobId) => ApiError(
    409,
    'job_active',
    'This property already has a plough request in progress.',
    extra: {'jobId': jobId},
  );

  /// 409: another crew member claimed the job first.
  factory ApiError.alreadyClaimed() => const ApiError(
    409,
    'already_claimed',
    'Another crew member already took this job.',
  );

  /// 409: the customer tried to cancel after work started.
  factory ApiError.jobStarted() => const ApiError(
    409,
    'job_started',
    'The crew has already started this job, so it can no longer be cancelled.',
  );

  /// 409: accept/decline/send on a quote in the wrong status.
  factory ApiError.quoteNotOpen() =>
      const ApiError(409, 'quote_not_open', 'This quote is no longer open.');

  /// 409: any other illegal transition; [message] says why.
  factory ApiError.invalidState(String message) =>
      ApiError(409, 'invalid_state', message);

  /// 409: card setup requested while the server is in manual mode.
  factory ApiError.paymentsManual() => const ApiError(
    409,
    'payments_manual',
    'Card payments are not enabled; jobs are billed manually.',
  );

  /// 409: payout with zero unpaid balance.
  factory ApiError.nothingToPay() => const ApiError(
    409,
    'nothing_to_pay',
    'There is no unpaid balance for this crew member.',
  );

  /// 429: too many failed logins, or another limit on anonymous callers.
  factory ApiError.rateLimited([String? message]) => ApiError(
    429,
    'rate_limited',
    message ?? 'Too many attempts. Wait a minute and try again.',
  );

  /// 502: Stripe unreachable or an unexpected Stripe error.
  factory ApiError.paymentUnavailable([String? message]) => ApiError(
    502,
    'payment_unavailable',
    message == null || message.isEmpty
        ? 'The payment service is unavailable. Try again shortly.'
        : message,
  );

  /// 503: the database write failed; the client may retry.
  factory ApiError.storageUnavailable() => const ApiError(
    503,
    'storage_unavailable',
    'Your change could not be saved. Try again.',
  );

  /// 500: anything else.
  factory ApiError.internal() =>
      const ApiError(500, 'internal', 'Something went wrong on our side.');

  /// The JSON error body.
  Map<String, Object?> toJson() => {'error': message, 'code': code, ...extra};

  @override
  String toString() => 'ApiError($status $code: $message)';
}

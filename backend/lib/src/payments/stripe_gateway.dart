import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../auth/tokens.dart';
import 'gateway.dart';

/// [PaymentGateway] over the Stripe REST API (form-encoded, no SDK).
class StripeGateway implements PaymentGateway {
  final String _secretKey;
  final http.Client _client;
  final String _baseUrl;
  final Duration _timeout;
  final String _currency;

  // How often creating each customer has failed with an answer from Stripe.
  final Map<String, int> _customerFailures = {};

  /// [client] is injectable for tests; it is closed by [close].
  StripeGateway({
    required String secretKey,
    http.Client? client,
    String baseUrl = 'https://api.stripe.com',
    Duration timeout = const Duration(seconds: 20),
    String currency = 'cad',
  }) : _secretKey = secretKey,
       _client = client ?? http.Client(),
       _baseUrl = baseUrl,
       _timeout = timeout,
       _currency = currency {
    if (secretKey.isEmpty) throw ArgumentError.value('', 'secretKey');
  }

  @override
  String get mode =>
      _secretKey.startsWith('sk_live_') || _secretKey.startsWith('rk_live_')
      ? 'stripe-live'
      : 'stripe-test';

  /// Closes the HTTP client.
  void close() => _client.close();

  @override
  Future<String> createCustomer({
    required String appCustomerId,
    required String name,
    required String email,
  }) async {
    // The stable key lets parallel requests share one customer. Stripe
    // replays a stored failure for a day though, so after one the next try
    // needs a key of its own.
    final failures = _customerFailures[appCustomerId] ?? 0;
    final reply = await _post(
      '/v1/customers',
      {'name': name, 'email': email, 'metadata[appCustomerId]': appCustomerId},
      idempotencyKey: failures == 0
          ? 'cust-$appCustomerId'
          : 'cust-$appCustomerId-$failures',
    );
    if (!reply.ok) {
      if (!reply.inDoubt) _customerFailures[appCustomerId] = failures + 1;
      throw reply.failure('create customer');
    }
    _customerFailures.remove(appCustomerId);
    return reply.string('id', 'create customer');
  }

  @override
  Future<SetupSession> createSetupSession({
    required String stripeCustomerId,
    required String appCustomerId,
    required String successUrl,
    required String cancelUrl,
  }) async {
    final reply = await _post(
      '/v1/checkout/sessions',
      {
        'mode': 'setup',
        'customer': stripeCustomerId,
        'client_reference_id': appCustomerId,
        'payment_method_types[0]': 'card',
        'success_url': successUrl,
        'cancel_url': cancelUrl,
      },
      // Each call must open a fresh session, so the key is unique per call.
      idempotencyKey: 'setup-$appCustomerId-${newId('k')}',
    );
    if (!reply.ok) throw reply.failure('create setup session');
    return SetupSession(
      id: reply.string('id', 'create setup session'),
      url: reply.string('url', 'create setup session'),
    );
  }

  @override
  Future<SavedCard?> fetchSetupResult(
    String sessionId, {
    required String expectedStripeCustomerId,
  }) async {
    final reply = await _get(
      '/v1/checkout/sessions/${Uri.encodeComponent(sessionId)}',
      query: const {'expand[]': 'setup_intent.payment_method'},
    );
    if (!reply.ok) throw reply.failure('fetch setup session');
    final session = reply.body;
    final setupIntent = session['setup_intent'];
    if (session['status'] != 'complete' ||
        session['customer'] != expectedStripeCustomerId ||
        setupIntent is! Map<String, dynamic> ||
        setupIntent['status'] != 'succeeded') {
      return null;
    }
    final method = setupIntent['payment_method'];
    final card = method is Map<String, dynamic> ? method['card'] : null;
    if (method is! Map<String, dynamic> ||
        method['id'] is! String ||
        card is! Map<String, dynamic> ||
        card['exp_month'] is! int ||
        card['exp_year'] is! int) {
      throw const PaymentException(
        'Stripe fetch setup session: the saved card is missing from the reply.',
      );
    }
    return SavedCard(
      paymentMethodId: method['id'] as String,
      brand: card['brand'] as String? ?? 'card',
      last4: card['last4'] as String? ?? '',
      expMonth: card['exp_month'] as int,
      expYear: card['exp_year'] as int,
    );
  }

  @override
  Future<HoldResult> authorize({
    required String jobId,
    required String stripeCustomerId,
    required String paymentMethodId,
    required int amountDollars,
    int attempt = 0,
  }) async {
    final r = await _confirmIntent(
      jobId: jobId,
      stripeCustomerId: stripeCustomerId,
      paymentMethodId: paymentMethodId,
      amountCents: _cents(amountDollars),
      hold: true,
      idempotencyKey: 'hold-$jobId-$attempt',
    );
    return switch (r.outcome) {
      PaymentOutcome.ok => HoldResult.ok(r.id!),
      PaymentOutcome.declined => HoldResult.declined(r.message!),
      PaymentOutcome.authRequired => const HoldResult.authRequired(),
      PaymentOutcome.unavailable => HoldResult.unavailable(
        r.message!,
        inDoubt: r.inDoubt,
      ),
    };
  }

  @override
  Future<CaptureResult> chargeNow({
    required String jobId,
    required String stripeCustomerId,
    required String paymentMethodId,
    required int amountDollars,
    int attempt = 0,
  }) => _charge(
    jobId: jobId,
    stripeCustomerId: stripeCustomerId,
    paymentMethodId: paymentMethodId,
    amountCents: _cents(amountDollars),
    attempt: attempt,
  );

  @override
  Future<CaptureResult> capture({
    required String jobId,
    required String paymentIntentId,
    int attempt = 0,
  }) async {
    final path = '/v1/payment_intents/${Uri.encodeComponent(paymentIntentId)}';
    try {
      final reply = await _post(
        '$path/capture',
        const {},
        idempotencyKey: 'capture-$jobId-$attempt',
      );
      if (reply.ok) {
        final status = reply.body['status'];
        return status == 'succeeded'
            ? CaptureResult.ok(paymentIntentId)
            : CaptureResult.unavailable(
                'Unexpected payment status "$status" after capture.',
              );
      }
      if (reply.status == 402) {
        return reply.errorCode == 'authentication_required'
            ? const CaptureResult.authRequired()
            : CaptureResult.declined(reply.declineMessage);
      }
      if (reply.errorCode != 'payment_intent_unexpected_state') {
        return CaptureResult.unavailable(
          reply.failure('capture').message,
          inDoubt: reply.inDoubt,
        );
      }

      final lookup = await _get(path);
      if (!lookup.ok) {
        return CaptureResult.unavailable(
          lookup.failure('fetch payment intent').message,
          inDoubt: lookup.inDoubt,
        );
      }
      final intent = lookup.body;
      switch (intent['status']) {
        case 'succeeded':
          return CaptureResult.ok(paymentIntentId);
        case 'canceled':
          final customer = intent['customer'];
          final method = intent['payment_method'];
          final amount = intent['amount'];
          if (customer is! String || method is! String || amount is! int) {
            return const CaptureResult.declined(
              'The card hold expired before the job was completed.',
            );
          }
          return _charge(
            jobId: jobId,
            stripeCustomerId: customer,
            paymentMethodId: method,
            amountCents: amount,
            attempt: attempt,
          );
        default:
          return CaptureResult.unavailable(
            'The card hold cannot be captured (status "${intent['status']}").',
          );
      }
    } on PaymentException catch (e) {
      // No readable answer: the capture may have gone through.
      return CaptureResult.unavailable(e.message, inDoubt: true);
    }
  }

  @override
  Future<void> cancel(String paymentIntentId) async {
    final path = '/v1/payment_intents/${Uri.encodeComponent(paymentIntentId)}';
    // No idempotency key: cancelling twice is harmless (see below), while a
    // key would make Stripe replay one stored failure to every retry for a
    // day.
    final reply = await _post('$path/cancel', const {});
    if (reply.ok) return;
    if (reply.errorCode == 'payment_intent_unexpected_state') {
      final lookup = await _get(path);
      if (lookup.ok && lookup.body['status'] == 'canceled') return;
    }
    throw reply.failure('cancel hold');
  }

  Future<CaptureResult> _charge({
    required String jobId,
    required String stripeCustomerId,
    required String paymentMethodId,
    required int amountCents,
    required int attempt,
  }) async {
    // An earlier charge whose answer never arrived, or arrived after its
    // idempotency key had expired, must not be made a second time.
    final String? paid;
    try {
      paid = await _paidIntent(jobId, stripeCustomerId);
    } on PaymentException catch (e) {
      return CaptureResult.unavailable(e.message, inDoubt: true);
    }
    if (paid != null) return CaptureResult.ok(paid);

    final r = await _confirmIntent(
      jobId: jobId,
      stripeCustomerId: stripeCustomerId,
      paymentMethodId: paymentMethodId,
      amountCents: amountCents,
      hold: false,
      idempotencyKey: 'charge-$jobId-$attempt',
    );
    return switch (r.outcome) {
      PaymentOutcome.ok => CaptureResult.ok(r.id!),
      PaymentOutcome.declined => CaptureResult.declined(r.message!),
      PaymentOutcome.authRequired => const CaptureResult.authRequired(),
      PaymentOutcome.unavailable => CaptureResult.unavailable(
        r.message!,
        inDoubt: r.inDoubt,
      ),
    };
  }

  /// The id of a payment that already succeeded for [jobId], looked for
  /// among the customer's 100 newest payments; null when there is none.
  Future<String?> _paidIntent(String jobId, String stripeCustomerId) async {
    final reply = await _get(
      '/v1/payment_intents',
      query: {'customer': stripeCustomerId, 'limit': '100'},
    );
    if (!reply.ok) throw reply.failure('list payments');
    final intents = reply.body['data'];
    if (intents is! List) {
      throw const PaymentException(
        'Stripe list payments: "data" missing in the reply.',
      );
    }
    for (final intent in intents) {
      if (intent is! Map<String, dynamic>) continue;
      final id = intent['id'];
      final metadata = intent['metadata'];
      if (id is String &&
          intent['status'] == 'succeeded' &&
          metadata is Map &&
          metadata['jobId'] == jobId) {
        return id;
      }
    }
    return null;
  }

  /// Creates and confirms an off-session payment intent: a hold (manual
  /// capture) or an immediate charge.
  Future<({PaymentOutcome outcome, String? id, String? message, bool inDoubt})>
  _confirmIntent({
    required String jobId,
    required String stripeCustomerId,
    required String paymentMethodId,
    required int amountCents,
    required bool hold,
    required String idempotencyKey,
  }) async {
    final _Reply reply;
    try {
      reply = await _post('/v1/payment_intents', {
        'amount': '$amountCents',
        'currency': _currency,
        'customer': stripeCustomerId,
        'payment_method': paymentMethodId,
        'payment_method_types[0]': 'card',
        'capture_method': hold ? 'manual' : 'automatic',
        'confirm': 'true',
        'off_session': 'true',
        'metadata[jobId]': jobId,
      }, idempotencyKey: idempotencyKey);
    } on PaymentException catch (e) {
      // No readable answer: Stripe may have acted on the request.
      return (
        outcome: PaymentOutcome.unavailable,
        id: null,
        message: e.message,
        inDoubt: true,
      );
    }
    const authRequired = (
      outcome: PaymentOutcome.authRequired,
      id: null,
      message: null,
      inDoubt: false,
    );
    final operation = hold ? 'place hold' : 'charge card';
    if (reply.ok) {
      final status = reply.body['status'];
      final id = reply.body['id'];
      if (status == (hold ? 'requires_capture' : 'succeeded') && id is String) {
        return (
          outcome: PaymentOutcome.ok,
          id: id,
          message: null,
          inDoubt: false,
        );
      }
      if (status == 'requires_action') return authRequired;
      return (
        outcome: PaymentOutcome.unavailable,
        id: null,
        message: 'Stripe $operation: unexpected payment status "$status".',
        inDoubt: false,
      );
    }
    if (reply.status == 402) {
      return reply.errorCode == 'authentication_required'
          ? authRequired
          : (
              outcome: PaymentOutcome.declined,
              id: null,
              message: reply.declineMessage,
              inDoubt: false,
            );
    }
    return (
      outcome: PaymentOutcome.unavailable,
      id: null,
      message: reply.failure(operation).message,
      inDoubt: reply.inDoubt,
    );
  }

  int _cents(int amountDollars) {
    if (amountDollars < 1) {
      throw ArgumentError.value(amountDollars, 'amountDollars');
    }
    return amountDollars * 100;
  }

  Future<_Reply> _post(
    String path,
    Map<String, String> form, {
    String? idempotencyKey,
  }) => _send(
    'POST $path',
    // A Map body is sent as application/x-www-form-urlencoded.
    () => _client.post(
      Uri.parse('$_baseUrl$path'),
      headers: {
        'authorization': 'Bearer $_secretKey',
        'idempotency-key': ?idempotencyKey,
      },
      body: form,
    ),
  );

  Future<_Reply> _get(String path, {Map<String, String>? query}) => _send(
    'GET $path',
    () => _client.get(
      Uri.parse('$_baseUrl$path').replace(queryParameters: query),
      headers: {'authorization': 'Bearer $_secretKey'},
    ),
  );

  Future<_Reply> _send(
    String operation,
    Future<http.Response> Function() request,
  ) async {
    final http.Response response;
    try {
      response = await request().timeout(_timeout);
    } on Exception catch (e) {
      throw PaymentException('Stripe $operation did not complete: $e');
    }
    try {
      return _Reply(
        response.statusCode,
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>,
      );
    } on Object {
      throw PaymentException(
        'Stripe $operation returned an unreadable reply '
        '(HTTP ${response.statusCode}).',
      );
    }
  }
}

class _Reply {
  final int status;
  final Map<String, dynamic> body;

  _Reply(this.status, this.body);

  bool get ok => status == 200;

  /// Whether this error says nothing about the request's fate: Stripe is
  /// still working on an earlier request with the same idempotency key
  /// (409) or turned this one away unseen (429). Either way the same key
  /// must be used again.
  bool get inDoubt => status == 409 || status == 429;

  Map<String, dynamic>? get _error {
    final error = body['error'];
    return error is Map<String, dynamic> ? error : null;
  }

  String? get errorCode => _error?['code'] as String?;

  /// Stripe's customer-facing reason for a 402.
  String get declineMessage {
    final message = _error?['message'];
    return message is String && message.isNotEmpty
        ? message
        : 'The card was declined.';
  }

  /// A required string field of a successful reply.
  String string(String field, String operation) {
    final value = body[field];
    if (value is String && value.isNotEmpty) return value;
    throw PaymentException('Stripe $operation: "$field" missing in the reply.');
  }

  PaymentException failure(String operation) {
    final error = _error;
    final detail = [
      error?['type'],
      error?['code'],
      error?['message'],
    ].whereType<String>().join(' / ');
    return PaymentException(
      'Stripe $operation failed: HTTP $status${detail.isEmpty ? '' : ' $detail'}',
    );
  }
}

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:redefine_api/src/payments/gateway.dart';
import 'package:redefine_api/src/payments/stripe_gateway.dart';
import 'package:test/test.dart';

const _key = 'sk_test_abc123';

http.Response _json(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);

http.Response _stripeError(
  int status,
  String type,
  String code,
  String message,
) => _json({
  'error': {'type': type, 'code': code, 'message': message},
}, status);

/// Replays [replies] in order and records what was sent.
class _Stripe {
  final List<http.Request> requests = [];
  final List<FutureOr<http.Response> Function(http.Request)> replies;

  _Stripe(this.replies);

  late final StripeGateway gateway = StripeGateway(
    secretKey: _key,
    client: MockClient((request) async {
      requests.add(request);
      if (requests.length > replies.length) {
        fail('Unexpected Stripe call: ${request.method} ${request.url}');
      }
      return replies[requests.length - 1](request);
    }),
  );

  http.Request get only => requests.single;
}

_Stripe _stripe(List<http.Response> replies) =>
    _Stripe([for (final r in replies) (_) => r]);

Matcher _result(
  PaymentOutcome outcome, {
  Object? id,
  Object? message,
  bool inDoubt = false,
}) => isA<PaymentResult>()
    .having((r) => r.outcome, 'outcome', outcome)
    .having((r) => r.paymentIntentId, 'paymentIntentId', id)
    .having((r) => r.message, 'message', message)
    .having((r) => r.inDoubt, 'inDoubt', inDoubt);

/// The customer's payments as `GET /v1/payment_intents` lists them.
http.Response _payments([List<Map<String, Object?>> intents = const []]) =>
    _json({'object': 'list', 'data': intents, 'has_more': false});

void main() {
  group('mode', () {
    test('is derived from the key prefix', () {
      expect(StripeGateway(secretKey: 'sk_test_x').mode, 'stripe-test');
      expect(StripeGateway(secretKey: 'sk_live_x').mode, 'stripe-live');
      expect(StripeGateway(secretKey: 'rk_live_x').mode, 'stripe-live');
      expect(StripeGateway(secretKey: 'rk_test_x').mode, 'stripe-test');
    });

    test('an empty key is rejected', () {
      expect(() => StripeGateway(secretKey: ''), throwsArgumentError);
    });
  });

  group('createCustomer', () {
    test('posts a form with the bearer key and an idempotency key', () async {
      final stripe = _stripe([
        _json({'id': 'cus_123', 'object': 'customer'}),
      ]);
      final id = await stripe.gateway.createCustomer(
        appCustomerId: 'cust_sarah',
        name: 'Sarah Mitchell & Co',
        email: 'sarah.m+snow@gmail.com',
      );

      expect(id, 'cus_123');
      final request = stripe.only;
      expect(request.method, 'POST');
      expect(request.url.toString(), 'https://api.stripe.com/v1/customers');
      expect(request.headers['authorization'], 'Bearer $_key');
      expect(
        request.headers['content-type'],
        startsWith('application/x-www-form-urlencoded'),
      );
      expect(request.headers['idempotency-key'], 'cust-cust_sarah');
      expect(request.bodyFields, {
        'name': 'Sarah Mitchell & Co',
        'email': 'sarah.m+snow@gmail.com',
        'metadata[appCustomerId]': 'cust_sarah',
      });
      // Reserved characters must be percent-encoded on the wire.
      expect(request.body, contains('Sarah+Mitchell+%26+Co'));
      expect(request.body, contains('sarah.m%2Bsnow%40gmail.com'));
      expect(request.body, contains('metadata%5BappCustomerId%5D=cust_sarah'));
    });

    test('throws PaymentException on a Stripe error', () async {
      final stripe = _stripe([
        _stripeError(
          401,
          'invalid_request_error',
          'api_key_invalid',
          'Invalid API Key provided',
        ),
      ]);
      await expectLater(
        stripe.gateway.createCustomer(
          appCustomerId: 'c',
          name: 'n',
          email: 'e@x.co',
        ),
        throwsA(
          isA<PaymentException>().having(
            (e) => e.message,
            'message',
            allOf(contains('HTTP 401'), isNot(contains(_key))),
          ),
        ),
      );
    });

    test('throws PaymentException when Stripe is unreachable', () async {
      final gateway = StripeGateway(
        secretKey: _key,
        client: MockClient((_) => throw http.ClientException('no route')),
      );
      await expectLater(
        gateway.createCustomer(appCustomerId: 'c', name: 'n', email: 'e@x.co'),
        throwsA(isA<PaymentException>()),
      );
    });

    test('throws PaymentException on a non-JSON reply', () async {
      final stripe = _stripe([http.Response('<html>Bad gateway</html>', 502)]);
      await expectLater(
        stripe.gateway.createCustomer(
          appCustomerId: 'c',
          name: 'n',
          email: 'e@x.co',
        ),
        throwsA(isA<PaymentException>()),
      );
    });

    test(
      'after an error answer the next try uses a new idempotency key',
      () async {
        // Stripe replays a stored failure for a day under the same key.
        final stripe = _Stripe([
          (_) => _stripeError(500, 'api_error', 'internal', 'boom'),
          (_) => _stripeError(400, 'invalid_request_error', 'bad', 'nope'),
          // Nothing arrived, or Stripe is still busy with the first request:
          // the same key again gets that request's answer.
          (_) => throw http.ClientException('reset'),
          (_) => _stripeError(409, 'idempotency_error', 'in_use', 'busy'),
          (_) => _json({'id': 'cus_123'}),
          (_) => _json({'id': 'cus_456'}),
        ]);
        Future<String> create(String id) => stripe.gateway.createCustomer(
          appCustomerId: id,
          name: 'n',
          email: 'e@x.co',
        );
        for (var i = 0; i < 4; i++) {
          await expectLater(
            create('cust_sarah'),
            throwsA(isA<PaymentException>()),
          );
        }
        expect(await create('cust_sarah'), 'cus_123');
        expect(await create('cust_anna'), 'cus_456');

        expect(stripe.requests.map((r) => r.headers['idempotency-key']), [
          'cust-cust_sarah',
          'cust-cust_sarah-1',
          'cust-cust_sarah-2',
          'cust-cust_sarah-2',
          'cust-cust_sarah-2',
          'cust-cust_anna',
        ]);
      },
    );
  });

  group('createSetupSession', () {
    Future<SetupSession> create(
      _Stripe stripe,
    ) => stripe.gateway.createSetupSession(
      stripeCustomerId: 'cus_123',
      appCustomerId: 'cust_sarah',
      successUrl:
          'https://api.example.com/billing/return?session_id={CHECKOUT_SESSION_ID}',
      cancelUrl: 'https://api.example.com/billing/return?cancelled=1',
    );

    test('opens a setup-mode Checkout session for the customer', () async {
      final stripe = _stripe([
        _json({'id': 'cs_test_1', 'url': 'https://checkout.stripe.com/c/1'}),
      ]);
      final session = await create(stripe);

      expect(session.id, 'cs_test_1');
      expect(session.url, 'https://checkout.stripe.com/c/1');
      final request = stripe.only;
      expect(
        request.url.toString(),
        'https://api.stripe.com/v1/checkout/sessions',
      );
      expect(request.bodyFields, {
        'mode': 'setup',
        'customer': 'cus_123',
        'client_reference_id': 'cust_sarah',
        'payment_method_types[0]': 'card',
        'success_url':
            'https://api.example.com/billing/return?session_id={CHECKOUT_SESSION_ID}',
        'cancel_url': 'https://api.example.com/billing/return?cancelled=1',
      });
    });

    test('uses a fresh idempotency key for every session', () async {
      final stripe = _stripe([
        _json({'id': 'cs_1', 'url': 'https://checkout.stripe.com/c/1'}),
        _json({'id': 'cs_2', 'url': 'https://checkout.stripe.com/c/2'}),
      ]);
      await create(stripe);
      await create(stripe);

      final keys = stripe.requests
          .map((r) => r.headers['idempotency-key']!)
          .toList();
      expect(keys[0], startsWith('setup-cust_sarah-'));
      expect(keys[1], startsWith('setup-cust_sarah-'));
      expect(keys[0], isNot(keys[1]));
    });

    test('throws PaymentException when the reply has no url', () async {
      final stripe = _stripe([
        _json({'id': 'cs_1', 'url': null}),
      ]);
      await expectLater(create(stripe), throwsA(isA<PaymentException>()));
    });
  });

  group('fetchSetupResult', () {
    Map<String, dynamic> session({
      String status = 'complete',
      String customer = 'cus_123',
      String intentStatus = 'succeeded',
      Object? paymentMethod = const {
        'id': 'pm_1',
        'card': {
          'brand': 'visa',
          'last4': '4242',
          'exp_month': 4,
          'exp_year': 2031,
        },
      },
    }) => {
      'id': 'cs_test_1',
      'status': status,
      'customer': customer,
      'setup_intent': {
        'id': 'seti_1',
        'status': intentStatus,
        'payment_method': paymentMethod,
      },
    };

    test('returns the saved card of a completed session', () async {
      final stripe = _stripe([_json(session())]);
      final card = await stripe.gateway.fetchSetupResult(
        'cs_test_1',
        expectedStripeCustomerId: 'cus_123',
      );

      expect(card, isNotNull);
      expect(card!.paymentMethodId, 'pm_1');
      expect(card.brand, 'visa');
      expect(card.last4, '4242');
      expect(card.expMonth, 4);
      expect(card.expYear, 2031);

      final request = stripe.only;
      expect(request.method, 'GET');
      expect(request.url.path, '/v1/checkout/sessions/cs_test_1');
      expect(request.url.queryParameters, {
        'expand[]': 'setup_intent.payment_method',
      });
      expect(request.headers['authorization'], 'Bearer $_key');
      expect(request.headers.containsKey('idempotency-key'), isFalse);
    });

    test('returns null while the session is still open', () async {
      final stripe = _stripe([
        _json({
          'id': 'cs_test_1',
          'status': 'open',
          'customer': 'cus_123',
          'setup_intent': null,
        }),
      ]);
      expect(
        await stripe.gateway.fetchSetupResult(
          'cs_test_1',
          expectedStripeCustomerId: 'cus_123',
        ),
        isNull,
      );
    });

    test('returns null when the setup intent did not succeed', () async {
      final stripe = _stripe([
        _json(session(intentStatus: 'requires_payment_method')),
      ]);
      expect(
        await stripe.gateway.fetchSetupResult(
          'cs_test_1',
          expectedStripeCustomerId: 'cus_123',
        ),
        isNull,
      );
    });

    test('returns null for a session of another customer', () async {
      final stripe = _stripe([_json(session(customer: 'cus_other'))]);
      expect(
        await stripe.gateway.fetchSetupResult(
          'cs_test_1',
          expectedStripeCustomerId: 'cus_123',
        ),
        isNull,
      );
    });

    test('throws when the payment method was not expanded', () async {
      final stripe = _stripe([_json(session(paymentMethod: 'pm_1'))]);
      await expectLater(
        stripe.gateway.fetchSetupResult(
          'cs_test_1',
          expectedStripeCustomerId: 'cus_123',
        ),
        throwsA(isA<PaymentException>()),
      );
    });

    test('throws PaymentException for an unknown session', () async {
      final stripe = _stripe([
        _stripeError(
          404,
          'invalid_request_error',
          'resource_missing',
          'No such checkout.session',
        ),
      ]);
      await expectLater(
        stripe.gateway.fetchSetupResult(
          'cs_gone',
          expectedStripeCustomerId: 'cus_123',
        ),
        throwsA(isA<PaymentException>()),
      );
    });
  });

  group('authorize', () {
    Future<HoldResult> hold(_Stripe stripe, {int attempt = 0}) =>
        stripe.gateway.authorize(
          jobId: 'job_abc',
          stripeCustomerId: 'cus_123',
          paymentMethodId: 'pm_1',
          amountDollars: 65,
          attempt: attempt,
        );

    test('places a manual-capture, off-session hold in cents', () async {
      final stripe = _stripe([
        _json({'id': 'pi_1', 'status': 'requires_capture'}),
      ]);
      expect(await hold(stripe), _result(PaymentOutcome.ok, id: 'pi_1'));

      final request = stripe.only;
      expect(request.method, 'POST');
      expect(
        request.url.toString(),
        'https://api.stripe.com/v1/payment_intents',
      );
      expect(request.headers['idempotency-key'], 'hold-job_abc-0');
      expect(request.bodyFields, {
        'amount': '6500',
        'currency': 'cad',
        'customer': 'cus_123',
        'payment_method': 'pm_1',
        'payment_method_types[0]': 'card',
        'capture_method': 'manual',
        'confirm': 'true',
        'off_session': 'true',
        'metadata[jobId]': 'job_abc',
      });
    });

    test('puts the attempt number in the idempotency key', () async {
      final stripe = _stripe([
        _json({'id': 'pi_2', 'status': 'requires_capture'}),
      ]);
      await hold(stripe, attempt: 2);
      expect(stripe.only.headers['idempotency-key'], 'hold-job_abc-2');
    });

    test('maps a 402 to declined with Stripe\'s message', () async {
      final stripe = _stripe([
        _stripeError(
          402,
          'card_error',
          'card_declined',
          'Your card has insufficient funds.',
        ),
      ]);
      expect(
        await hold(stripe),
        _result(
          PaymentOutcome.declined,
          message: 'Your card has insufficient funds.',
        ),
      );
    });

    test('maps a 402 authentication_required to authRequired', () async {
      final stripe = _stripe([
        _stripeError(
          402,
          'card_error',
          'authentication_required',
          'This payment requires authentication.',
        ),
      ]);
      expect(await hold(stripe), _result(PaymentOutcome.authRequired));
    });

    test('maps a requires_action intent to authRequired', () async {
      final stripe = _stripe([
        _json({'id': 'pi_1', 'status': 'requires_action'}),
      ]);
      expect(await hold(stripe), _result(PaymentOutcome.authRequired));
    });

    test('maps other Stripe errors to unavailable', () async {
      final stripe = _stripe([
        _stripeError(500, 'api_error', 'internal', 'Something went wrong'),
      ]);
      expect(
        await hold(stripe),
        _result(PaymentOutcome.unavailable, message: contains('HTTP 500')),
      );
    });

    test('maps an unexpected intent status to unavailable', () async {
      final stripe = _stripe([
        _json({'id': 'pi_1', 'status': 'processing'}),
      ]);
      expect(
        await hold(stripe),
        _result(PaymentOutcome.unavailable, message: contains('processing')),
      );
    });

    test('maps a network failure to unavailable instead of throwing', () async {
      final gateway = StripeGateway(
        secretKey: _key,
        client: MockClient((_) => throw http.ClientException('reset')),
      );
      expect(
        await gateway.authorize(
          jobId: 'job_abc',
          stripeCustomerId: 'cus_123',
          paymentMethodId: 'pm_1',
          amountDollars: 65,
        ),
        _result(PaymentOutcome.unavailable, message: isNotEmpty, inDoubt: true),
      );
    });

    test('is in doubt only when Stripe may still act on the request', () async {
      // Busy with the same key, turned away unseen, or an unreadable reply.
      for (final reply in [
        _stripeError(409, 'idempotency_error', 'idempotency_key_in_use', 'x'),
        _stripeError(429, 'rate_limit_error', 'rate_limit', 'Slow down'),
        http.Response('<html>Bad gateway</html>', 502),
      ]) {
        expect(
          await hold(_stripe([reply])),
          _result(
            PaymentOutcome.unavailable,
            message: isNotEmpty,
            inDoubt: true,
          ),
        );
      }
      // An error answer is final (and stored under the key for a day).
      for (final reply in [
        _stripeError(500, 'api_error', 'internal', 'boom'),
        _stripeError(400, 'invalid_request_error', 'parameter_invalid', 'x'),
        _stripeError(401, 'invalid_request_error', 'api_key_invalid', 'x'),
      ]) {
        expect(
          await hold(_stripe([reply])),
          _result(PaymentOutcome.unavailable, message: isNotEmpty),
        );
      }
    });

    test('gives up after the timeout', () async {
      final gateway = StripeGateway(
        secretKey: _key,
        timeout: const Duration(milliseconds: 30),
        client: MockClient((_) => Completer<http.Response>().future),
      );
      expect(
        await gateway.authorize(
          jobId: 'job_abc',
          stripeCustomerId: 'cus_123',
          paymentMethodId: 'pm_1',
          amountDollars: 65,
        ),
        _result(PaymentOutcome.unavailable, message: isNotEmpty, inDoubt: true),
      );
    });

    test('rejects a non-positive amount before calling Stripe', () async {
      final stripe = _stripe([]);
      await expectLater(
        stripe.gateway.authorize(
          jobId: 'job_abc',
          stripeCustomerId: 'cus_123',
          paymentMethodId: 'pm_1',
          amountDollars: 0,
        ),
        throwsArgumentError,
      );
      expect(stripe.requests, isEmpty);
    });
  });

  group('capture', () {
    final unexpectedState = _stripeError(
      400,
      'invalid_request_error',
      'payment_intent_unexpected_state',
      'This PaymentIntent could not be captured because it has a status of '
          'canceled.',
    );

    Future<CaptureResult> capture(_Stripe stripe, {int attempt = 0}) => stripe
        .gateway
        .capture(jobId: 'job_abc', paymentIntentId: 'pi_1', attempt: attempt);

    test('captures the hold', () async {
      final stripe = _stripe([
        _json({'id': 'pi_1', 'status': 'succeeded'}),
      ]);
      expect(await capture(stripe), _result(PaymentOutcome.ok, id: 'pi_1'));

      final request = stripe.only;
      expect(request.method, 'POST');
      expect(request.url.path, '/v1/payment_intents/pi_1/capture');
      expect(request.headers['idempotency-key'], 'capture-job_abc-0');
      expect(
        request.headers['content-type'],
        startsWith('application/x-www-form-urlencoded'),
      );
      expect(request.body, isEmpty);
    });

    test('puts the attempt number in the idempotency key', () async {
      final stripe = _stripe([
        _json({'id': 'pi_1', 'status': 'succeeded'}),
      ]);
      await capture(stripe, attempt: 3);
      expect(stripe.only.headers['idempotency-key'], 'capture-job_abc-3');
    });

    test('treats an already captured intent as captured', () async {
      final stripe = _stripe([
        unexpectedState,
        _json({'id': 'pi_1', 'status': 'succeeded'}),
      ]);
      expect(await capture(stripe), _result(PaymentOutcome.ok, id: 'pi_1'));

      expect(stripe.requests, hasLength(2));
      expect(stripe.requests[1].method, 'GET');
      expect(stripe.requests[1].url.path, '/v1/payment_intents/pi_1');
    });

    const expiredHold = {
      'id': 'pi_1',
      'status': 'canceled',
      'customer': 'cus_123',
      'payment_method': 'pm_1',
      'amount': 6500,
      'metadata': {'jobId': 'job_abc'},
    };

    test('charges afresh when the hold has expired', () async {
      final stripe = _stripe([
        unexpectedState,
        _json(expiredHold),
        // The job's own expired hold and other jobs' payments do not count.
        _payments([
          expiredHold,
          {
            'id': 'pi_0',
            'status': 'succeeded',
            'metadata': {'jobId': 'job_other'},
          },
        ]),
        _json({'id': 'pi_2', 'status': 'succeeded'}),
      ]);
      expect(
        await capture(stripe, attempt: 1),
        _result(PaymentOutcome.ok, id: 'pi_2'),
      );

      final list = stripe.requests[2];
      expect(list.method, 'GET');
      expect(list.url.path, '/v1/payment_intents');
      expect(list.url.queryParameters, {'customer': 'cus_123', 'limit': '100'});
      expect(list.headers.containsKey('idempotency-key'), isFalse);

      final charge = stripe.requests[3];
      expect(charge.method, 'POST');
      expect(charge.url.path, '/v1/payment_intents');
      expect(charge.headers['idempotency-key'], 'charge-job_abc-1');
      expect(charge.bodyFields, {
        'amount': '6500',
        'currency': 'cad',
        'customer': 'cus_123',
        'payment_method': 'pm_1',
        'payment_method_types[0]': 'card',
        'capture_method': 'automatic',
        'confirm': 'true',
        'off_session': 'true',
        'metadata[jobId]': 'job_abc',
      });
    });

    test('reports a declined fallback charge as declined', () async {
      final stripe = _stripe([
        unexpectedState,
        _json(expiredHold),
        _payments(),
        _stripeError(402, 'card_error', 'card_declined', 'Your card expired.'),
      ]);
      expect(
        await capture(stripe),
        _result(PaymentOutcome.declined, message: 'Your card expired.'),
      );
    });

    test(
      'an expired hold is not charged afresh when the job was paid already',
      () async {
        // An earlier fallback charge went through, but its answer was lost.
        final stripe = _stripe([
          unexpectedState,
          _json(expiredHold),
          _payments([
            {
              'id': 'pi_7',
              'status': 'requires_payment_method',
              'metadata': {'jobId': 'job_abc'},
            },
            {
              'id': 'pi_2',
              'status': 'succeeded',
              'metadata': {'jobId': 'job_abc'},
            },
          ]),
        ]);
        expect(
          await capture(stripe, attempt: 5),
          _result(PaymentOutcome.ok, id: 'pi_2'),
        );
        expect(stripe.requests.where((r) => r.method == 'POST'), hasLength(1));
      },
    );

    test(
      'without the list of payments nothing is charged and all is in doubt',
      () async {
        for (final list in [
          _stripeError(500, 'api_error', 'internal', 'boom'),
          _json({'object': 'list'}),
        ]) {
          final stripe = _stripe([unexpectedState, _json(expiredHold), list]);
          expect(
            await capture(stripe),
            _result(
              PaymentOutcome.unavailable,
              message: isNotEmpty,
              inDoubt: true,
            ),
          );
        }
      },
    );

    test('a fallback charge without an answer is in doubt', () async {
      final stripe = _Stripe([
        (_) => unexpectedState,
        (_) => _json(expiredHold),
        (_) => _payments(),
        (_) => throw http.ClientException('reset'),
      ]);
      expect(
        await capture(stripe),
        _result(PaymentOutcome.unavailable, message: isNotEmpty, inDoubt: true),
      );
      expect(
        stripe.requests.last.headers['idempotency-key'],
        'charge-job_abc-0',
      );
    });

    test('an expired hold without a reusable card is declined', () async {
      final stripe = _stripe([
        unexpectedState,
        _json({
          'id': 'pi_1',
          'status': 'canceled',
          'customer': 'cus_123',
          'payment_method': null,
          'amount': 6500,
        }),
      ]);
      expect(
        await capture(stripe),
        _result(PaymentOutcome.declined, message: contains('expired')),
      );
      expect(stripe.requests, hasLength(2));
    });

    test('a hold in any other state is unavailable', () async {
      final stripe = _stripe([
        unexpectedState,
        _json({'id': 'pi_1', 'status': 'requires_payment_method'}),
      ]);
      expect(
        await capture(stripe),
        _result(
          PaymentOutcome.unavailable,
          message: contains('requires_payment_method'),
        ),
      );
    });

    test('maps a 402 on capture to declined', () async {
      final stripe = _stripe([
        _stripeError(402, 'card_error', 'card_declined', 'Declined.'),
      ]);
      expect(
        await capture(stripe),
        _result(PaymentOutcome.declined, message: 'Declined.'),
      );
    });

    test('maps Stripe outages to unavailable at every step', () async {
      final down = _stripeError(503, 'api_error', 'unavailable', 'Try later');
      expect(
        await capture(_stripe([down])),
        _result(PaymentOutcome.unavailable, message: contains('HTTP 503')),
      );
      expect(
        await capture(_stripe([unexpectedState, down])),
        _result(PaymentOutcome.unavailable, message: contains('HTTP 503')),
      );
      final gateway = StripeGateway(
        secretKey: _key,
        client: MockClient((_) => throw http.ClientException('reset')),
      );
      expect(
        await gateway.capture(jobId: 'job_abc', paymentIntentId: 'pi_1'),
        _result(PaymentOutcome.unavailable, message: isNotEmpty, inDoubt: true),
      );
    });
  });

  group('chargeNow', () {
    test(
      'creates an automatic-capture intent keyed charge-<job>-<n>',
      () async {
        final stripe = _stripe([
          _payments(),
          _json({'id': 'pi_9', 'status': 'succeeded'}),
        ]);
        final result = await stripe.gateway.chargeNow(
          jobId: 'job_abc',
          stripeCustomerId: 'cus_123',
          paymentMethodId: 'pm_2',
          amountDollars: 45,
          attempt: 4,
        );

        expect(result, _result(PaymentOutcome.ok, id: 'pi_9'));
        expect(result, isA<CaptureResult>());
        expect(stripe.requests.first.method, 'GET');
        expect(stripe.requests.first.url.queryParameters, {
          'customer': 'cus_123',
          'limit': '100',
        });
        final request = stripe.requests.last;
        expect(request.method, 'POST');
        expect(request.url.path, '/v1/payment_intents');
        expect(request.headers['idempotency-key'], 'charge-job_abc-4');
        expect(request.bodyFields['amount'], '4500');
        expect(request.bodyFields['capture_method'], 'automatic');
        expect(request.bodyFields['payment_method'], 'pm_2');
        expect(request.bodyFields['off_session'], 'true');
      },
    );

    test('maps declines and authentication demands', () async {
      Future<CaptureResult> charge(_Stripe stripe) => stripe.gateway.chargeNow(
        jobId: 'job_abc',
        stripeCustomerId: 'cus_123',
        paymentMethodId: 'pm_2',
        amountDollars: 45,
      );
      expect(
        await charge(
          _stripe([
            _payments(),
            _stripeError(402, 'card_error', 'card_declined', 'No.'),
          ]),
        ),
        _result(PaymentOutcome.declined, message: 'No.'),
      );
      expect(
        await charge(
          _stripe([
            _payments(),
            _stripeError(402, 'card_error', 'authentication_required', 'SCA'),
          ]),
        ),
        _result(PaymentOutcome.authRequired),
      );
      expect(
        await charge(
          _stripe([
            _payments(),
            _json({'id': 'pi_9', 'status': 'requires_capture'}),
          ]),
        ),
        _result(PaymentOutcome.unavailable, message: isNotEmpty),
      );
    });

    test('returns the payment a job already has instead of charging', () async {
      final stripe = _stripe([
        _payments([
          {
            'id': 'pi_other',
            'status': 'succeeded',
            'metadata': {'jobId': 'job_other'},
          },
          {
            'id': 'pi_paid',
            'status': 'succeeded',
            'metadata': {'jobId': 'job_abc'},
          },
        ]),
      ]);
      final result = await stripe.gateway.chargeNow(
        jobId: 'job_abc',
        stripeCustomerId: 'cus_123',
        paymentMethodId: 'pm_2',
        amountDollars: 45,
        attempt: 3,
      );
      expect(result, _result(PaymentOutcome.ok, id: 'pi_paid'));
      expect(stripe.only.method, 'GET');
    });
  });

  group('cancel', () {
    final alreadyCanceled = _stripeError(
      400,
      'invalid_request_error',
      'payment_intent_unexpected_state',
      'You cannot cancel this PaymentIntent because it has a status of '
          'canceled.',
    );

    test('releases the hold', () async {
      final stripe = _stripe([
        _json({'id': 'pi_1', 'status': 'canceled'}),
      ]);
      await stripe.gateway.cancel('pi_1');

      final request = stripe.only;
      expect(request.method, 'POST');
      expect(request.url.path, '/v1/payment_intents/pi_1/cancel');
      expect(request.headers['authorization'], 'Bearer $_key');
    });

    test('a failed release can be repeated at once', () async {
      // With an idempotency key Stripe would replay the stored 500 for a day.
      final stripe = _stripe([
        _stripeError(500, 'api_error', 'internal', 'boom'),
        _json({'id': 'pi_1', 'status': 'canceled'}),
      ]);
      await expectLater(
        stripe.gateway.cancel('pi_1'),
        throwsA(isA<PaymentException>()),
      );
      await stripe.gateway.cancel('pi_1');
      for (final request in stripe.requests) {
        expect(request.method, 'POST');
        expect(request.headers.containsKey('idempotency-key'), isFalse);
      }
    });

    test('an already cancelled hold counts as released', () async {
      final stripe = _stripe([
        alreadyCanceled,
        _json({'id': 'pi_1', 'status': 'canceled'}),
      ]);
      await stripe.gateway.cancel('pi_1');
      expect(stripe.requests[1].method, 'GET');
      expect(stripe.requests[1].url.path, '/v1/payment_intents/pi_1');
    });

    test('a captured payment cannot be released', () async {
      final stripe = _stripe([
        alreadyCanceled,
        _json({'id': 'pi_1', 'status': 'succeeded'}),
      ]);
      await expectLater(
        stripe.gateway.cancel('pi_1'),
        throwsA(isA<PaymentException>()),
      );
    });

    test('throws PaymentException on any other failure', () async {
      await expectLater(
        _stripe([
          _stripeError(500, 'api_error', 'internal', 'boom'),
        ]).gateway.cancel('pi_1'),
        throwsA(isA<PaymentException>()),
      );
      final gateway = StripeGateway(
        secretKey: _key,
        client: MockClient((_) => throw http.ClientException('reset')),
      );
      await expectLater(
        gateway.cancel('pi_1'),
        throwsA(isA<PaymentException>()),
      );
    });
  });
}

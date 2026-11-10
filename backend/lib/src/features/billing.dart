import 'package:shelf/shelf.dart';

import '../app.dart';
import '../data/store.dart';
import '../errors.dart';
import '../http.dart';
import '../payments/gateway.dart';
import '../routes.dart';
import '../time.dart';
import 'views.dart';

/// Stripe closes an unfinished Checkout session after a day.
const _setupLifetime = Duration(hours: 24);
const _lookupInterval = Duration(seconds: 2);

/// A customer who asks for the card page again this soon gets the session
/// that was just opened instead of another one.
const _sessionReuse = Duration(seconds: 10);

/// The customer's saved card and charges.
void mountBilling(Routes r, App app) {
  final store = app.store;
  // When each customer's pending setup session was last looked up at Stripe.
  final lastLookup = <String, DateTime>{};
  // The setup session each customer was last sent to, and when.
  final recentSetups =
      <String, ({Future<SetupSession> session, DateTime openedAt})>{};

  bool setupPending(Doc customer) {
    final startedAt = parseTime(customer['pendingSetupAt']);
    return customer['pendingSetupSessionId'] != null &&
        startedAt != null &&
        app.now().difference(startedAt) < _setupLifetime;
  }

  Response billing(AuthCtx ctx) {
    final customer = store.require(
      Collections.customers,
      ctx.customerId!,
      what: 'Customer',
    );
    return jsonOk(
      Views.of(store, ctx).billing(
        customer,
        mode: app.paymentsMode,
        pendingSetup: setupPending(customer),
      ),
    );
  }

  /// Asks Stripe whether the customer's pending setup session has completed
  /// and, if so, saves the card. Returns whether a card was saved. Stripe is
  /// asked at most once per [_lookupInterval] per customer, whoever calls.
  Future<bool> syncCard(String customerId) async {
    final gateway = app.payments;
    final customer = store.get(Collections.customers, customerId);
    final sessionId = customer?['pendingSetupSessionId'] as String?;
    final stripeCustomerId = customer?['stripeCustomerId'] as String?;
    if (gateway == null ||
        customer == null ||
        sessionId == null ||
        stripeCustomerId == null) {
      return false;
    }
    if (!setupPending(customer)) {
      store.tx((tx) => tx.patch(Collections.customers, customerId, _noSetup));
      lastLookup.remove(customerId);
      return false;
    }
    final now = app.now();
    final last = lastLookup[customerId];
    if (last != null && now.difference(last) < _lookupInterval) return false;
    lastLookup[customerId] = now;
    final card = await gateway.fetchSetupResult(
      sessionId,
      expectedStripeCustomerId: stripeCustomerId,
    );
    if (card == null) return false;
    lastLookup.remove(customerId);
    return store.tx((tx) {
      final current = tx.require(Collections.customers, customerId);
      // A newer setup session was started while Stripe answered.
      if (current['pendingSetupSessionId'] != sessionId) return false;
      tx.patch(Collections.customers, customerId, {
        ..._noSetup,
        'stripePaymentMethodId': card.paymentMethodId,
        'card': {
          'brand': card.brand,
          'last4': card.last4,
          'expMonth': card.expMonth,
          'expYear': card.expYear,
          'updatedAt': isoTime(app.now()),
        },
      });
      return true;
    });
  }

  r.get(
    '/billing',
    (Request req) => billing(authOf(req, roles: {Role.customer})),
  );

  /// Opens a hosted card-setup session for the customer, creating the
  /// Stripe customer first when there is none yet.
  Future<SetupSession> openSetup(
    PaymentGateway gateway,
    String customerId,
  ) async {
    final customer = store.require(
      Collections.customers,
      customerId,
      what: 'Customer',
    );
    var stripeCustomerId = customer['stripeCustomerId'] as String?;
    if (stripeCustomerId == null) {
      final created = await gateway.createCustomer(
        appCustomerId: customerId,
        name: customer['name'] as String,
        email: customer['email'] as String,
      );
      // A parallel request may have stored one already; keep the first.
      stripeCustomerId =
          store.tx(
                (tx) => tx.update(
                  Collections.customers,
                  customerId,
                  (draft) => draft['stripeCustomerId'] ??= created,
                ),
              )['stripeCustomerId']
              as String;
    }
    final base = app.config.publicBaseUrl;
    final session = await gateway.createSetupSession(
      stripeCustomerId: stripeCustomerId,
      appCustomerId: customerId,
      successUrl: '$base/billing/return?session_id={CHECKOUT_SESSION_ID}',
      cancelUrl: '$base/billing/return?cancelled=1',
    );
    store.tx(
      (tx) => tx.patch(Collections.customers, customerId, {
        'pendingSetupSessionId': session.id,
        'pendingSetupAt': isoTime(app.now()),
      }),
    );
    lastLookup.remove(customerId);
    return session;
  }

  r.post('/billing/setup-session', (Request req) async {
    final ctx = authOf(req, roles: {Role.customer});
    final gateway = app.payments ?? (throw ApiError.paymentsManual());
    final customerId = ctx.customerId!;
    final now = app.now();
    recentSetups.removeWhere(
      (_, setup) => now.difference(setup.openedAt) >= _sessionReuse,
    );
    final recent = recentSetups[customerId];
    if (recent != null) {
      // Repeated taps and parallel requests share one session instead of
      // each opening a new one at Stripe.
      final session = await recent.session;
      final pending = store.get(
        Collections.customers,
        customerId,
      )?['pendingSetupSessionId'];
      if (pending == session.id) return jsonOk({'url': session.url});
    }
    final opening = openSetup(gateway, customerId);
    recentSetups[customerId] = (session: opening, openedAt: now);
    try {
      return jsonOk({'url': (await opening).url});
    } on Object {
      // A failed attempt must not stand in the way of the next one.
      if (identical(recentSetups[customerId]?.session, opening)) {
        recentSetups.remove(customerId);
      }
      rethrow;
    }
  });

  r.post('/billing/refresh', (Request req) async {
    final ctx = authOf(req, roles: {Role.customer});
    await syncCard(ctx.customerId!);
    return billing(ctx);
  });

  r.get('/billing/return', (Request req) async {
    if (req.url.queryParameters.containsKey('cancelled')) {
      return _page(
        'Card setup cancelled',
        'No card was saved. You can close this tab and return to the app.',
      );
    }
    final sessionId = queryString(req, 'session_id');
    final customer = sessionId == null || sessionId.length > 200
        ? null
        : store.firstWhere(
            Collections.customers,
            (c) => c['pendingSetupSessionId'] == sessionId,
          );
    var saved = false;
    if (customer != null) {
      try {
        saved = await syncCard(customer['id'] as String);
      } on PaymentException catch (e) {
        // The app re-checks through /billing/refresh; the page stays calm.
        app.log('payments: card sync on return failed: ${e.message}');
      }
    }
    return saved
        ? _page(
            'Card saved',
            'Card saved. You can close this tab and return to the app.',
          )
        : _page(
            'Return to the app',
            'You can close this tab and return to the app to continue.',
          );
  });
}

const _noSetup = {'pendingSetupSessionId': null, 'pendingSetupAt': null};

Response _page(String title, String message) => Response.ok(
  '''
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>$title · Redefine</title>
<style>
  body { margin: 0; min-height: 100vh; display: flex; align-items: center;
    justify-content: center; background: #F4F7F5; color: #16241F;
    font-family: system-ui, -apple-system, "Segoe UI", sans-serif; }
  main { max-width: 22rem; margin: 1.5rem; padding: 2rem; background: #fff;
    border-radius: 1rem; border-top: 6px solid #0E6D55; text-align: center;
    box-shadow: 0 8px 24px rgba(14, 109, 85, 0.12); }
  h1 { margin: 0 0 0.75rem; font-size: 1.35rem; color: #0E6D55; }
  p { margin: 0; line-height: 1.5; }
</style>
</head>
<body>
<main>
<h1>$title</h1>
<p>$message</p>
</main>
</body>
</html>
''',
  headers: const {
    'content-type': 'text/html; charset=utf-8',
    'cache-control': 'no-store',
  },
);

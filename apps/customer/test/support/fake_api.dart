import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:redefine_customer/api.dart';
import 'package:redefine_customer/main.dart';
import 'package:redefine_ui/redefine_ui.dart';

typedef Json = Map<String, Object?>;

http.Response jsonResponse(Object? body, [int status = 200]) => http.Response.bytes(
  utf8.encode(jsonEncode(body)),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

http.Response errorResponse(int status, String code, String message, [Json extra = const {}]) =>
    jsonResponse({'error': message, 'code': code, ...extra}, status);

String _iso(DateTime time) => time.toUtc().toIso8601String();

/// An in-memory stand-in for the customer's side of the Redefine API, served
/// through a [MockClient]. It follows the contract closely enough for the
/// screens: role-shaped JSON, the documented error codes, holds and releases.
class FakeApi {
  FakeApi({this.mode = 'manual'});

  static const token = 'token_sarah';
  static const stripeUrl = 'https://checkout.stripe.test/c/pay/cs_test_1';
  static const Json user = {
    'id': 'user_sarah',
    'name': 'Sarah Mitchell',
    'email': 'sarah.m@gmail.com',
    'role': 'customer',
    'initials': 'SM',
    'color': 'teal',
    'phone': '(807) 555-0142',
    'linkedId': 'cust_sarah',
    'crewStatus': null,
  };

  /// `stripe` or `manual`.
  String mode;
  int shovelPrice = 20;
  Json? card;
  bool pendingSetup = false;

  /// Oldest first, as the API lists them.
  final properties = <Json>[];

  /// Newest first.
  final jobs = <Json>[];

  /// Every request as `METHOD /path`, in order.
  final requests = <String>[];

  /// The last JSON body posted to each route.
  final bodies = <String, Json>{};

  /// A response to give once, instead of the real one, the next time the
  /// route (`METHOD /path`) is called.
  final failOnce = <String, http.Response>{};

  /// A response to give instead of the real one for as long as the route
  /// (`METHOD /path`) is listed here.
  final failing = <String, http.Response>{};

  /// While true every call fails as if the network were down.
  bool down = false;
  int _nextId = 1;

  late final client = MockClient(_handle);

  ApiClient apiClient({bool signedIn = false}) => ApiClient(
    baseUrl: 'http://api.test',
    httpClient: client,
    tokenStore: MemoryTokenStore(signedIn ? token : null),
  );

  int count(String route) => requests.where((r) => r == route).length;

  // ---- Seeding --------------------------------------------------------------

  Json addProperty({
    required String id,
    required String name,
    String address = '1 Test Rd',
    String illustration = 'house',
    String status = 'active',
    int? price,
    String note = '',
  }) {
    final property = <String, Object?>{
      'id': id,
      'name': name,
      'address': address,
      'illustration': illustration,
      'note': note,
      'status': status,
      'price': price,
      'quoteId': 'quote_$id',
      'createdAt': _iso(DateTime.now().subtract(const Duration(days: 30))),
    };
    properties.add(property);
    return property;
  }

  /// Adds a job on [property]; a `done` job was completed [ago] ago after 47
  /// minutes on site.
  Json addJob(
    Json property, {
    String status = 'open',
    bool shovel = false,
    String note = '',
    String crewNote = '',
    String paymentStatus = 'none',
    String? paymentMode,
    String? paymentError,
    Duration ago = const Duration(minutes: 6),
  }) {
    final price = property['price']! as int;
    final extra = shovel ? shovelPrice : 0;
    final end = DateTime.now().subtract(ago);
    final finished = status == 'done';
    final claimed = status != 'open' && status != 'cancelled';
    final started = status == 'inProgress' || finished;
    final job = <String, Object?>{
      'id': 'job_${_nextId++}',
      'propertyId': property['id'],
      'customerId': 'cust_sarah',
      'propertyName': property['name'],
      'address': property['address'],
      'illustration': property['illustration'],
      'customerName': 'Sarah Mitchell',
      'customerInitials': 'SM',
      'customerPhone': '(807) 555-0142',
      'shovel': shovel,
      'price': price,
      'shovelPrice': extra,
      'total': price + extra,
      'status': status,
      'crewName': claimed ? 'Marcus Reid' : '',
      'crewInitials': claimed ? 'MR' : '',
      'crewColor': claimed ? 'lime' : '',
      'note': note,
      'crewNote': crewNote,
      'source': 'customer',
      'requestedAt': _iso(end.subtract(const Duration(minutes: 90))),
      'claimedAt': claimed ? _iso(end.subtract(const Duration(minutes: 60))) : null,
      'startedAt': started ? _iso(end.subtract(const Duration(minutes: 47))) : null,
      'completedAt': finished ? _iso(end) : null,
      'cancelledAt': status == 'cancelled' ? _iso(end) : null,
      'cancelledBy': status == 'cancelled' ? 'customer' : null,
      'payment': <String, Object?>{
        'mode': paymentMode ?? mode,
        'status': paymentStatus,
        'error': paymentError,
        'holdExpiresAt': null,
        'capturedAt': paymentStatus == 'captured' ? _iso(end) : null,
      },
    };
    jobs.insert(0, job);
    return job;
  }

  /// The crew finishes [job]; the hold is captured, or the job becomes due.
  void complete(Json job) {
    final payment = job['payment']! as Json;
    final now = DateTime.now();
    job
      ..['status'] = 'done'
      ..['crewName'] = 'Marcus Reid'
      ..['crewInitials'] = 'MR'
      ..['claimedAt'] ??= _iso(now.subtract(const Duration(minutes: 40)))
      ..['startedAt'] ??= _iso(now.subtract(const Duration(minutes: 30)))
      ..['completedAt'] = _iso(now);
    if (payment['mode'] == 'stripe') {
      payment
        ..['status'] = 'captured'
        ..['capturedAt'] = _iso(now);
    } else {
      payment['status'] = 'due';
    }
  }

  void saveCard({String brand = 'visa', String last4 = '4242'}) {
    pendingSetup = false;
    card = {
      'brand': brand,
      'last4': last4,
      'expMonth': 4,
      'expYear': 2031,
      'updatedAt': _iso(DateTime.now()),
    };
  }

  // ---- Views ----------------------------------------------------------------

  Json? _activeJobOf(Object? propertyId) => jobs
      .where(
        (j) =>
            j['propertyId'] == propertyId &&
            const {'open', 'claimed', 'inProgress'}.contains(j['status']),
      )
      .firstOrNull;

  Json _propertyView(Json property) => {...property, 'activeJob': _activeJobOf(property['id'])};

  Json _billing() {
    const charged = {'authorized', 'captured', 'failed', 'due', 'paid'};
    String statusOf(Json job) => (job['payment']! as Json)['status']! as String;
    final charges = jobs.where((j) => charged.contains(statusOf(j))).toList();
    return {
      'mode': mode,
      'card': card,
      'pendingSetup': pendingSetup,
      'balanceDue': charges
          .where((j) => const {'due', 'failed'}.contains(statusOf(j)))
          .fold<int>(0, (sum, j) => sum + (j['total']! as int)),
      'charges': [
        for (final j in charges)
          {
            'jobId': j['id'],
            'propertyName': j['propertyName'],
            'date': j['completedAt'] ?? j['requestedAt'],
            'total': j['total'],
            'shovel': j['shovel'],
            'status': statusOf(j),
          },
      ],
    };
  }

  // ---- Routes ---------------------------------------------------------------

  Future<http.Response> _handle(http.Request request) async {
    final route = '${request.method} ${request.url.path}';
    requests.add(route);
    if (down) throw http.ClientException('Connection refused');
    final body = request.body.isEmpty
        ? const <String, Object?>{}
        : jsonDecode(request.body) as Json;
    if (request.method == 'POST') bodies[route] = body;
    final failure = failOnce.remove(route) ?? failing[route];
    if (failure != null) return failure;

    if (route == 'POST /auth/login') {
      return body['email'] == user['email'] && body['password'] == 'redefine'
          ? jsonResponse({'token': token, 'user': user})
          : errorResponse(401, 'invalid_credentials', 'Wrong email or password.');
    }
    if (route == 'POST /auth/signup') {
      final account = {
        ...user,
        'name': body['name'],
        'email': body['email'],
        'phone': body['phone'] ?? '',
      };
      return jsonResponse({'token': token, 'user': account}, 201);
    }
    if (request.headers['authorization'] != 'Bearer $token') {
      return errorResponse(401, 'unauthorized', 'Sign in to continue.');
    }

    switch (route) {
      case 'GET /auth/me':
        return jsonResponse(user);
      case 'POST /auth/logout':
        return jsonResponse({'ok': true});
      case 'GET /settings':
        return jsonResponse({'shovelPrice': shovelPrice, 'currency': 'cad', 'paymentsMode': mode});
      case 'GET /billing' || 'POST /billing/refresh':
        return jsonResponse(_billing());
      case 'POST /billing/setup-session':
        if (mode != 'stripe') {
          return errorResponse(409, 'payments_manual', 'Card payments are not enabled.');
        }
        pendingSetup = true;
        return jsonResponse({'url': stripeUrl});
      case 'GET /properties':
        return jsonResponse(properties.map(_propertyView).toList());
      case 'POST /properties':
        final created = addProperty(
          id: 'prop_${_nextId++}',
          name: body['name']! as String,
          address: body['address']! as String,
          illustration: body['illustration'] as String? ?? 'house',
          note: body['note'] as String? ?? '',
          status: 'quoteRequested',
        )..['createdAt'] = _iso(DateTime.now());
        return jsonResponse({
          'property': _propertyView(created),
          'quote': {'id': created['quoteId'], 'propertyId': created['id'], 'status': 'pending'},
        }, 201);
      case 'GET /jobs':
        final propertyId = request.url.queryParameters['propertyId'];
        return jsonResponse([
          for (final j in jobs)
            if (propertyId == null || j['propertyId'] == propertyId) j,
        ]);
      case 'POST /jobs':
        return _requestJob(body);
    }

    final parts = request.url.pathSegments;
    if (parts.length >= 2 && parts[0] == 'jobs') {
      final job = jobs.where((j) => j['id'] == parts[1]).firstOrNull;
      if (job == null) return errorResponse(404, 'not_found', 'Job not found.');
      if (request.method == 'GET' && parts.length == 2) return jsonResponse(job);
      if (route.endsWith('/cancel')) return _cancelJob(job);
    }
    if (parts.length == 3 && parts[0] == 'quotes') {
      final property = properties.where((p) => p['quoteId'] == parts[1]).firstOrNull;
      if (property == null) return errorResponse(404, 'not_found', 'Quote not found.');
      if (property['status'] != 'quoted') {
        return errorResponse(409, 'quote_not_open', 'This quote is no longer open.');
      }
      final accepted = parts[2] == 'accept';
      property['status'] = accepted ? 'active' : 'declined';
      return jsonResponse({
        'quote': {'id': parts[1], 'status': accepted ? 'accepted' : 'declined'},
        'property': _propertyView(property),
      });
    }
    if (parts.length == 3 && parts[0] == 'properties' && parts[2] == 'request-quote') {
      final property = properties.where((p) => p['id'] == parts[1]).firstOrNull;
      if (property == null) return errorResponse(404, 'not_found', 'Property not found.');
      if (property['status'] != 'declined') {
        return errorResponse(409, 'invalid_state', 'This property already has a quote.');
      }
      property
        ..['status'] = 'quoteRequested'
        ..['price'] = null;
      return jsonResponse({
        'property': _propertyView(property),
        'quote': {'id': property['quoteId'], 'status': 'pending'},
      });
    }
    return errorResponse(404, 'not_found', 'Not found.');
  }

  http.Response _requestJob(Json body) {
    final property = properties.where((p) => p['id'] == body['propertyId']).firstOrNull;
    if (property == null) return errorResponse(404, 'not_found', 'Property not found.');
    final unfinished = _activeJobOf(property['id']);
    if (unfinished != null) {
      return errorResponse(409, 'job_active', 'This property already has a request.', {
        'jobId': unfinished['id'],
      });
    }
    if (mode == 'stripe' && card == null) {
      return errorResponse(402, 'card_required', 'Add a card before requesting a plough.');
    }
    final job = addJob(
      property,
      shovel: body['shovel'] == true,
      note: body['note'] as String? ?? '',
      paymentStatus: mode == 'stripe' ? 'authorized' : 'none',
      ago: Duration.zero,
    )..['requestedAt'] = _iso(DateTime.now());
    return jsonResponse(job, 201);
  }

  http.Response _cancelJob(Json job) {
    if (job['status'] == 'inProgress') {
      return errorResponse(409, 'job_started', 'The crew has already started this job.');
    }
    if (job['status'] == 'done') {
      return errorResponse(409, 'invalid_state', 'A completed job cannot be cancelled.');
    }
    final payment = job['payment']! as Json;
    job
      ..['status'] = 'cancelled'
      ..['cancelledBy'] = 'customer'
      ..['cancelledAt'] = _iso(DateTime.now());
    if (payment['status'] == 'authorized') payment['status'] = 'released';
    return jsonResponse(job);
  }
}

// ---- Driving the app --------------------------------------------------------

/// Lets in-flight requests finish, the frames they cause build and a route
/// transition (up to 800 ms) run out. Timed pumps, never pumpAndSettle: the
/// app polls and shows running clocks.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Boots the real app against [server], already signed in unless [signedIn]
/// is false. End the test with [unmount].
Future<SessionController> pumpApp(
  WidgetTester tester,
  FakeApi server, {
  bool signedIn = true,
}) async {
  // Tall enough that nothing the tests tap is scrolled out of view.
  tester.view.physicalSize = const Size(1000, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final session = useApi(server.apiClient(signedIn: signedIn));
  addTearDown(session.dispose);
  await tester.pumpWidget(const CustomerApp());
  await settle(tester);
  return session;
}

/// Takes the app off screen so that its polls, clocks and SnackBars stop.
Future<void> unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 1));
}

/// Taps the confirm button of the dialog on screen.
Future<void> confirm(WidgetTester tester, String label) async {
  await tester.tap(find.widgetWithText(FilledButton, label));
  await settle(tester);
}

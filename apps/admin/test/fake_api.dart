// A small in-memory stand-in for the Redefine API, shaped like the contract's
// admin views, for widget tests. No network is involved.

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

typedef Json = Map<String, dynamic>;

String _ago(Duration duration) => DateTime.now().toUtc().subtract(duration).toIso8601String();

http.Response _json(Object body, [int status = 200]) => http.Response.bytes(
  utf8.encode(jsonEncode(body)),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

http.Response _error(int status, String code, String message, [Json extra = const {}]) =>
    _json({'error': message, 'code': code, ...extra}, status);

class FakeApi {
  static const adminEmail = 'lia@redefine.co';
  static const password = 'redefine';

  /// `METHOD /path` or `METHOD /path?query`, in the order they arrived.
  final requests = <String>[];

  /// The JSON body of the latest POST to each `METHOD /path`.
  final bodies = <String, Json>{};

  final _queries = <(String, Map<String, String>)>[];

  final tokens = <String>{};

  /// While true every request fails as if the server were unreachable.
  bool down = false;

  /// When set, `POST /jobs` answers 409 `job_active` naming this job.
  String? blockNewJobsWith;

  /// While true a job that asks for a card hold is refused with 402.
  bool declineCards = false;

  /// While set, `POST /jobs` does not answer until this completes.
  Completer<void>? holdNewJobs;

  /// While true the payment service cannot be reached: cancelling a job
  /// leaves its card hold in place, with the server's explanation.
  bool releaseFails = false;

  final Json admin = {
    'id': 'user_lia',
    'name': 'Lia Robinson',
    'email': adminEmail,
    'role': 'admin',
    'initials': 'LR',
    'color': 'lime',
    'phone': '',
    'linkedId': null,
    'crewStatus': null,
  };

  final Json settings = {
    'shovelPrice': 20,
    'crewShovelBonus': 10,
    'openJobExpiryHours': 48,
    'currency': 'cad',
    'paymentsMode': 'manual',
  };

  final customers = <String, Json>{
    'cust_sarah': {
      'id': 'cust_sarah',
      'name': 'Sarah Mitchell',
      'initials': 'SM',
      'color': 'teal',
      'email': 'sarah.m@gmail.com',
      'phone': '(807) 555-0142',
      'createdAt': _ago(const Duration(days: 40)),
      'card': null,
    },
    'cust_anna': {
      'id': 'cust_anna',
      'name': 'Anna Tomlinson',
      'initials': 'AT',
      'color': 'lime',
      'email': 'anna.t@gmail.com',
      'phone': '',
      'createdAt': _ago(const Duration(days: 30)),
      'card': null,
    },
    'cust_paul': {
      'id': 'cust_paul',
      'name': 'Paul Larson',
      'initials': 'PL',
      'color': 'paper',
      'email': 'paul.l@gmail.com',
      'phone': '',
      'createdAt': _ago(const Duration(days: 5)),
      'card': null,
    },
  };

  final properties = <String, Json>{
    'prop_maple': {
      'id': 'prop_maple',
      'customerId': 'cust_sarah',
      'name': 'Maple Street home',
      'address': '412 Maple St, Thunder Bay, ON',
      'illustration': 'house',
      'note': '',
      'status': 'active',
      'price': 45,
      'crewPay': 25,
      'quoteId': 'quote_maple',
      'createdAt': _ago(const Duration(days: 40)),
    },
    'prop_cabin': {
      'id': 'prop_cabin',
      'customerId': 'cust_sarah',
      'name': 'Cabin',
      'address': '88 Lakeside Rd',
      'illustration': 'cabin',
      'note': 'Long gravel driveway, about 60 m.',
      'status': 'quoteRequested',
      'price': null,
      'crewPay': null,
      'quoteId': 'quote_cabin',
      'createdAt': _ago(const Duration(hours: 2)),
    },
    'prop_cedar': {
      'id': 'prop_cedar',
      'customerId': 'cust_anna',
      'name': 'Cedar Ave home',
      'address': '78 Cedar Ave',
      'illustration': 'bungalow',
      'note': '',
      'status': 'active',
      'price': 55,
      'crewPay': 30,
      'quoteId': 'quote_cedar',
      'createdAt': _ago(const Duration(days: 30)),
    },
    'prop_birch': {
      'id': 'prop_birch',
      'customerId': 'cust_paul',
      'name': 'Birch Road home',
      'address': '21 Birch Rd',
      'illustration': 'townhouse',
      'note': '',
      'status': 'quoted',
      'price': 60,
      'crewPay': 35,
      'quoteId': 'quote_birch',
      'createdAt': _ago(const Duration(days: 5)),
    },
  };

  final quotes = <String, Json>{
    'quote_cabin': {
      'id': 'quote_cabin',
      'propertyId': 'prop_cabin',
      'status': 'pending',
      'note': 'Long gravel driveway, about 60 m.',
      'price': null,
      'crewPay': null,
      'createdAt': _ago(const Duration(hours: 2)),
      'sentAt': null,
      'decidedAt': null,
    },
    'quote_birch': {
      'id': 'quote_birch',
      'propertyId': 'prop_birch',
      'status': 'sent',
      'note': '',
      'price': 60,
      'crewPay': 35,
      'createdAt': _ago(const Duration(days: 5)),
      'sentAt': _ago(const Duration(days: 4)),
      'decidedAt': null,
    },
  };

  final crew = <String, Json>{
    'crew_marcus': {
      'id': 'crew_marcus',
      'userId': 'user_marcus',
      'name': 'Marcus Reid',
      'initials': 'MR',
      'color': 'lime',
      'email': 'marcus@redefine.co',
      'phone': '(807) 555-0111',
      'status': 'active',
      'appliedAt': _ago(const Duration(days: 60)),
    },
    'crew_jordan': {
      'id': 'crew_jordan',
      'userId': 'user_jordan',
      'name': 'Jordan Park',
      'initials': 'JP',
      'color': 'teal',
      'email': 'jordan@redefine.co',
      'phone': '',
      'status': 'active',
      'appliedAt': _ago(const Duration(days: 50)),
    },
    'crew_tasha': {
      'id': 'crew_tasha',
      'userId': 'user_tasha',
      'name': 'Tasha Rivera',
      'initials': 'TR',
      'color': 'teal',
      'email': 'tasha@redefine.co',
      'phone': '(807) 555-0177',
      'status': 'pending',
      'appliedAt': _ago(const Duration(hours: 3)),
    },
  };

  /// Newest request first.
  late final jobs = <Json>[
    _job(
      'job_open',
      'prop_cedar',
      shovel: true,
      requested: const Duration(minutes: 10),
      note: 'Please clear the side door too.',
    ),
    _job(
      'job_paid',
      'prop_maple',
      status: 'done',
      crewId: 'crew_marcus',
      requested: const Duration(days: 2, hours: 1),
      completed: const Duration(days: 2),
      payment: 'paid',
    ),
    _job(
      'job_due',
      'prop_cedar',
      status: 'done',
      crewId: 'crew_jordan',
      requested: const Duration(days: 3, hours: 1),
      completed: const Duration(days: 3),
      payment: 'due',
      crewNote: 'Salted the steps.',
    ),
  ];

  final payouts = <Json>[];

  late final client = MockClient(_handle);

  String issueToken() {
    final token = 'token_${tokens.length + 1}';
    tokens.add(token);
    return token;
  }

  int count(String request) => requests.where((r) => r == request).length;

  /// The query parameters of every `METHOD /path` request, in the order they
  /// arrived.
  List<Map<String, String>> queriesOf(String route) => [
    for (final (sent, query) in _queries)
      if (sent == route) query,
  ];

  /// A new open request, as if a customer had just asked for a plough.
  void addOpenJob(String id, String propertyId) => addJob(id, propertyId, requested: Duration.zero);

  /// Adds a job requested [requested] ago, keeping the newest request first.
  void addJob(
    String id,
    String propertyId, {
    String status = 'open',
    String? crewId,
    required Duration requested,
    Duration? completed,
    String payment = 'none',
  }) {
    final job = _job(
      id,
      propertyId,
      status: status,
      crewId: crewId,
      requested: requested,
      completed: completed,
      payment: payment,
    );
    final older = jobs.indexWhere((j) => !_requestedAt(j).isAfter(_requestedAt(job)));
    jobs.insert(older < 0 ? jobs.length : older, job);
  }

  DateTime _requestedAt(Json job) => DateTime.parse(job['requestedAt'] as String);

  Json _job(
    String id,
    String propertyId, {
    String status = 'open',
    bool shovel = false,
    String? crewId,
    required Duration requested,
    Duration? completed,
    String payment = 'none',
    String paymentMode = 'manual',
    String note = '',
    String crewNote = '',
    String source = 'customer',
  }) {
    final property = properties[propertyId]!;
    final customer = customers[property['customerId']]!;
    final member = crewId == null ? null : crew[crewId]!;
    final price = property['price'] as int;
    final shovelPrice = shovel ? settings['shovelPrice'] as int : 0;
    return {
      'id': id,
      'propertyId': propertyId,
      'customerId': customer['id'],
      'propertyName': property['name'],
      'address': property['address'],
      'illustration': property['illustration'],
      'customerName': customer['name'],
      'customerInitials': customer['initials'],
      'customerPhone': customer['phone'],
      'shovel': shovel,
      'price': price,
      'shovelPrice': shovelPrice,
      'total': price + shovelPrice,
      'crewPay': (property['crewPay'] as int) + (shovel ? settings['crewShovelBonus'] as int : 0),
      'status': status,
      'crewId': crewId,
      'crewName': member?['name'] ?? '',
      'crewInitials': member?['initials'] ?? '',
      'crewColor': member?['color'] ?? '',
      'note': note,
      'crewNote': crewNote,
      'source': source,
      'requestedAt': _ago(requested),
      'claimedAt': completed == null ? null : _ago(requested - const Duration(minutes: 5)),
      'startedAt': completed == null ? null : _ago(completed + const Duration(minutes: 40)),
      'completedAt': completed == null ? null : _ago(completed),
      'cancelledAt': null,
      'cancelledBy': null,
      'payment': {
        'mode': paymentMode,
        'status': payment,
        'error': null,
        'holdExpiresAt': null,
        'capturedAt': null,
      },
      'paidOut': false,
    };
  }

  bool _live(Json job) => const ['open', 'claimed', 'inProgress'].contains(job['status']);

  bool _owing(Json job) {
    final status = (job['payment'] as Json)['status'];
    return status == 'due' || status == 'failed';
  }

  Json? _jobById(String id) => jobs.where((j) => j['id'] == id).firstOrNull;

  /// Releases the card hold of a cancelled job, as the server does on cancel
  /// and again on its own later when the first try could not get through.
  void _releaseHold(Json job) {
    final payment = job['payment'] as Json;
    if (releaseFails) {
      payment['error'] =
          'The card hold could not be released yet. It will be retried automatically.';
    } else {
      payment
        ..['status'] = 'released'
        ..['error'] = null;
    }
  }

  /// The server's periodic retry of the holds it could not release.
  void retryReleases() {
    for (final job in jobs) {
      final held = (job['payment'] as Json)['status'] == 'authorized';
      if (job['status'] == 'cancelled' && held) _releaseHold(job);
    }
  }

  Json _quoteView(Json quote) {
    final property = properties[quote['propertyId']]!;
    final customer = customers[property['customerId']]!;
    return {
      ...quote,
      'customerId': customer['id'],
      'customerName': customer['name'],
      'customerInitials': customer['initials'],
      'customerColor': customer['color'],
      'email': customer['email'],
      'phone': customer['phone'],
      'propertyName': property['name'],
      'address': property['address'],
      'illustration': property['illustration'],
    };
  }

  Json _propertyView(Json property) => {
    ...property,
    'customerName': customers[property['customerId']]!['name'],
    'activeJob': jobs.where((j) => j['propertyId'] == property['id'] && _live(j)).firstOrNull,
  };

  Iterable<Json> _unpaidJobsOf(String crewId) =>
      jobs.where((j) => j['crewId'] == crewId && j['status'] == 'done' && j['paidOut'] != true);

  Json _crewView(Json member) {
    final done = jobs.where((j) => j['crewId'] == member['id'] && j['status'] == 'done');
    final unpaid = _unpaidJobsOf(member['id'] as String);
    return {
      ...member,
      'jobsThisWeek': done.length,
      'earnedThisWeek': done.fold<int>(0, (sum, j) => sum + (j['crewPay'] as int)),
      'unpaidTotal': unpaid.fold<int>(0, (sum, j) => sum + (j['crewPay'] as int)),
      'unpaidJobs': unpaid.length,
    };
  }

  /// A job as crew see it: no customer price, no payment.
  Json _crewJobView(Json job) => {
    for (final entry in job.entries)
      if (!const ['price', 'shovelPrice', 'total', 'payment'].contains(entry.key))
        entry.key: entry.value,
    'customerName': '',
    'customerInitials': '',
    'customerPhone': '',
  };

  Json _payView(String crewId) {
    final member = crew[crewId]!;
    final done = jobs.where((j) => j['crewId'] == crewId && j['status'] == 'done').toList();
    final unpaid = _unpaidJobsOf(crewId).toList();
    final earned = done.fold<int>(0, (sum, j) => sum + (j['crewPay'] as int));
    return {
      'crewId': crewId,
      'name': member['name'],
      'earnedToday': 0,
      'jobsToday': 0,
      'earnedThisWeek': earned,
      'jobsThisWeek': done.length,
      'earnedAllTime': earned,
      'unpaidTotal': unpaid.fold<int>(0, (sum, j) => sum + (j['crewPay'] as int)),
      'unpaidJobs': unpaid.map(_crewJobView).toList(),
      'payouts': payouts.where((p) => p['crewId'] == crewId).toList(),
    };
  }

  Json _customerView(Json customer, {bool detail = false}) {
    final owned = properties.values.where((p) => p['customerId'] == customer['id']).toList();
    final theirs = jobs.where((j) => j['customerId'] == customer['id']).toList();
    int sumOf(bool Function(String status) test) => theirs
        .where((j) => test((j['payment'] as Json)['status'] as String))
        .fold<int>(0, (sum, j) => sum + (j['total'] as int));
    return {
      'id': customer['id'],
      'name': customer['name'],
      'initials': customer['initials'],
      'color': customer['color'],
      'email': customer['email'],
      'phone': customer['phone'],
      'createdAt': customer['createdAt'],
      'propertyCount': owned.length,
      'activeProperties': owned.where((p) => p['status'] == 'active').length,
      'jobCount': theirs.length,
      // The newest request, whatever became of it.
      'lastJobAt': theirs.isEmpty ? null : theirs.first['requestedAt'],
      'hasCard': customer['card'] != null,
      'addresses': [for (final p in owned) p['address']],
      if (detail) ...{
        'card': customer['card'],
        'properties': owned.map(_propertyView).toList(),
        'jobs': theirs,
        'totals': {
          'billed': sumOf((s) => s == 'captured' || s == 'paid'),
          'outstanding': sumOf((s) => s == 'due' || s == 'failed'),
        },
      },
    };
  }

  Json _dashboard() {
    final pendingQuotes = quotes.values.where((q) => q['status'] == 'pending').toList();
    final pendingCrew = crew.values.where((m) => m['status'] == 'pending').toList();
    final issues = jobs.where(_owing).toList();
    int withStatus(String status) => jobs.where((j) => j['status'] == status).length;
    return {
      'serverTime': DateTime.now().toUtc().toIso8601String(),
      'counts': {
        'pendingQuotes': pendingQuotes.length,
        'sentQuotes': quotes.values.where((q) => q['status'] == 'sent').length,
        'pendingCrew': pendingCrew.length,
        'openJobs': withStatus('open'),
        'claimedJobs': withStatus('claimed'),
        'inProgressJobs': withStatus('inProgress'),
        'doneToday': 0,
        'cancelledToday': withStatus('cancelled'),
        'revenueToday': 0,
        'paymentIssues': issues.length,
      },
      'pendingQuotes': pendingQuotes.map(_quoteView).toList(),
      'liveJobs': jobs.where(_live).toList().reversed.toList(),
      'pendingCrew': pendingCrew.map(_crewView).toList(),
      'paymentIssues': issues,
    };
  }

  Future<http.Response> _handle(http.Request request) async {
    final route = '${request.method} ${request.url.path}';
    requests.add(request.url.hasQuery ? '$route?${request.url.query}' : route);
    _queries.add((route, request.url.queryParameters));
    if (down) throw http.ClientException('Connection refused');
    final body = request.body.isEmpty ? <String, dynamic>{} : jsonDecode(request.body) as Json;
    if (request.method == 'POST') bodies[route] = body;

    if (route == 'POST /auth/login') {
      if (body['email'] != adminEmail || body['password'] != password) {
        return _error(401, 'invalid_credentials', 'Wrong email or password.');
      }
      return _json({'token': issueToken(), 'user': admin});
    }
    final token = request.headers['authorization']?.replaceFirst('Bearer ', '');
    if (!tokens.contains(token)) return _error(401, 'unauthorized', 'Please sign in again.');

    final query = request.url.queryParameters;
    switch ([request.method, ...request.url.pathSegments]) {
      case ['GET', 'auth', 'me']:
        return _json(admin);
      case ['POST', 'auth', 'logout']:
        tokens.remove(token);
        return _json({'ok': true});
      case ['GET', 'settings']:
        return _json(settings);
      case ['POST', 'settings']:
        settings.addAll(body);
        return _json(settings);
      case ['GET', 'dashboard', 'admin']:
        return _json(_dashboard());

      case ['GET', 'quotes', final id]:
        final quote = quotes[id];
        return quote == null ? _notFound : _json(_quoteView(quote));
      case ['POST', 'quotes', final id, 'send']:
        final quote = quotes[id];
        if (quote == null) return _notFound;
        if (quote['status'] != 'pending' && quote['status'] != 'sent') {
          return _error(409, 'quote_not_open', 'This quote has already been answered.');
        }
        quote
          ..['status'] = 'sent'
          ..['price'] = body['price']
          ..['crewPay'] = body['crewPay']
          ..['sentAt'] = _ago(Duration.zero);
        properties[quote['propertyId']]!
          ..['status'] = 'quoted'
          ..['price'] = body['price']
          ..['crewPay'] = body['crewPay'];
        return _json(_quoteView(quote));

      case ['GET', 'jobs']:
        final statuses = query['status']?.split(',');
        final payments = query['payment']?.split(',');
        // Both ends compared with the time of the request, inclusive.
        final from = DateTime.tryParse(query['from'] ?? '');
        final to = DateTime.tryParse(query['to'] ?? '');
        return _json([
          for (final job in jobs)
            if ((statuses == null || statuses.contains(job['status'])) &&
                (payments == null || payments.contains((job['payment'] as Json)['status'])) &&
                (from == null || !_requestedAt(job).isBefore(from)) &&
                (to == null || !_requestedAt(job).isAfter(to)))
              job,
        ]);
      case ['POST', 'jobs']:
        await holdNewJobs?.future;
        final blocker = blockNewJobsWith;
        if (blocker != null) {
          return _error(409, 'job_active', 'This property already has a plough on the way.', {
            'jobId': blocker,
          });
        }
        final onCard = body['payment'] == 'card';
        if (onCard && declineCards) {
          return _error(402, 'card_declined', 'The card was declined.');
        }
        final job = _job(
          'job_new_${jobs.length}',
          body['propertyId'] as String,
          shovel: body['shovel'] == true,
          requested: Duration.zero,
          note: body['note'] as String? ?? '',
          source: 'admin',
          paymentMode: onCard ? 'stripe' : 'manual',
          payment: onCard ? 'authorized' : 'none',
        );
        jobs.insert(0, job);
        return _json(job, 201);
      case ['GET', 'jobs', final id]:
        final job = _jobById(id);
        return job == null ? _notFound : _json(job);
      case ['POST', 'jobs', final id, final action]:
        final job = _jobById(id);
        if (job == null) return _notFound;
        final payment = job['payment'] as Json;
        switch (action) {
          case 'cancel' when _live(job):
            job
              ..['status'] = 'cancelled'
              ..['cancelledAt'] = _ago(Duration.zero)
              ..['cancelledBy'] = 'admin';
            if (payment['status'] == 'authorized') _releaseHold(job);
          case 'mark-paid' when _owing(job):
            payment['status'] = 'paid';
          default:
            return _error(409, 'invalid_state', "That's no longer possible for this job.");
        }
        return _json(job);

      case ['GET', 'customers']:
        return _json(customers.values.map(_customerView).toList());
      case ['GET', 'customers', final id]:
        final customer = customers[id];
        return customer == null ? _notFound : _json(_customerView(customer, detail: true));
      case ['POST', 'properties', final id, 'price']:
        final property = properties[id];
        if (property == null) return _notFound;
        property
          ..['price'] = body['price']
          ..['crewPay'] = body['crewPay'];
        return _json(_propertyView(property));

      case ['GET', 'crew']:
        List<Json> withStatus(String status) =>
            crew.values.where((m) => m['status'] == status).map(_crewView).toList();
        return _json({
          'active': withStatus('active'),
          'pending': withStatus('pending'),
          'rejected': withStatus('rejected'),
        });
      case ['POST', 'crew', final id, 'approve' || 'reject']:
        final member = crew[id];
        if (member == null) return _notFound;
        member['status'] = request.url.pathSegments.last == 'approve' ? 'active' : 'rejected';
        return _json(_crewView(member));
      case ['GET', 'crew', final id, 'pay']:
        return crew.containsKey(id) ? _json(_payView(id)) : _notFound;
      case ['POST', 'crew', final id, 'payouts']:
        if (!crew.containsKey(id)) return _notFound;
        final unpaid = _unpaidJobsOf(id).toList();
        if (unpaid.isEmpty) {
          return _error(409, 'nothing_to_pay', 'There is nothing to pay out.');
        }
        final payout = {
          'id': 'payout_${payouts.length + 1}',
          'crewId': id,
          'amount': unpaid.fold<int>(0, (sum, j) => sum + (j['crewPay'] as int)),
          'jobCount': unpaid.length,
          'paidAt': _ago(Duration.zero),
          'note': '',
        };
        for (final job in unpaid) {
          job['paidOut'] = true;
        }
        payouts.insert(0, payout);
        return _json({'payout': payout, 'pay': _payView(id)});
    }
    return _notFound;
  }

  static final _notFound = _error(404, 'not_found', "We couldn't find that.");
}

// A small in-memory stand-in for the Redefine API as a crew member sees it
// (contract: crew views of Job and CrewPay), for widget tests. No network is
// involved.

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

typedef Json = Map<String, dynamic>;

DateTime _past(Duration ago) => DateTime.now().toUtc().subtract(ago);

String? _iso(DateTime? time) => time?.toUtc().toIso8601String();

http.Response _json(Object body, [int status = 200]) => http.Response.bytes(
  utf8.encode(jsonEncode(body)),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

http.Response _error(int status, String code, String message) =>
    _json({'error': message, 'code': code}, status);

/// One stored job; [toJson] is the crew member's view of it.
class FakeJob {
  FakeJob({
    required this.id,
    required this.propertyName,
    required this.address,
    required this.customerName,
    required this.customerInitials,
    required this.crewPay,
    required this.customerTotal,
    required this.requestedAt,
    this.customerPhone = '',
    this.shovel = false,
    this.status = 'open',
    this.crewId,
    this.note = '',
    this.crewNote = '',
    this.claimedAt,
    this.startedAt,
    this.completedAt,
    this.cancelledAt,
    this.cancelledBy,
    this.paidOut = false,
  });

  final String id, propertyName, address;
  final String customerName, customerInitials, customerPhone;
  final bool shovel;
  final int crewPay;

  /// What the customer pays. Crew must never see it.
  final int customerTotal;
  final String note;
  final DateTime requestedAt;
  String status;
  String? crewId;
  String crewNote;
  DateTime? claimedAt, startedAt, completedAt, cancelledAt;
  String? cancelledBy;
  bool paidOut;

  Json toJson(String viewer, {bool leakPrices = false}) {
    final mine = crewId == viewer;
    return {
      'id': id,
      'propertyId': 'prop_$id',
      'customerId': 'cust_$id',
      'propertyName': propertyName,
      'address': address,
      'illustration': 'house',
      'customerName': mine ? customerName : '',
      'customerInitials': mine ? customerInitials : '',
      'customerPhone': mine ? customerPhone : '',
      'shovel': shovel,
      'crewPay': crewPay,
      'status': status,
      'crewId': crewId,
      'crewName': mine ? 'Marcus Reid' : '',
      'crewInitials': mine ? 'MR' : '',
      'crewColor': mine ? 'lime' : '',
      'note': note,
      'crewNote': crewNote,
      'source': 'customer',
      'requestedAt': _iso(requestedAt),
      'claimedAt': _iso(claimedAt),
      'startedAt': _iso(startedAt),
      'completedAt': _iso(completedAt),
      'cancelledAt': _iso(cancelledAt),
      'cancelledBy': cancelledBy,
      'paidOut': paidOut,
      // Not part of the crew view; only sent to prove the app ignores it.
      if (leakPrices) ...{
        'price': customerTotal,
        'shovelPrice': 0,
        'total': customerTotal,
        'payment': {'mode': 'manual', 'status': 'due'},
      },
    };
  }
}

class FakeApi {
  static const crewEmail = 'marcus@redefine.co';
  static const password = 'redefine';
  static const crewId = 'crew_marcus';

  /// `METHOD /path` or `METHOD /path?query`, in the order they arrived.
  final requests = <String>[];

  /// The JSON body of the latest POST to each `METHOD /path`.
  final bodies = <String, Json>{};

  final tokens = <String>{};

  /// `pending` | `active` | `rejected`: what the office decided.
  String crewStatus = 'active';

  /// How long the server takes to answer a request. Requests are still
  /// handled in the order they were sent.
  Duration latency = Duration.zero;

  /// While true every request fails as if the server were unreachable,
  /// including the ones already on their way.
  bool down = false;

  /// While true the job and pay routes answer 503.
  bool jobsUnavailable = false;

  /// While true only the pay summary answers 503.
  bool payUnavailable = false;

  /// Jobs another crew member accepts the moment this one tries to.
  final raced = <String>{};

  /// Sends the customer's prices along with every job, which the real server
  /// never does for crew.
  bool leakPrices = false;

  final jobs = <String, FakeJob>{
    for (final job in [
      FakeJob(
        id: 'job_cedar',
        propertyName: 'Cedar Ave home',
        address: '78 Cedar Ave, Thunder Bay, ON',
        customerName: 'Anna Tomlinson',
        customerInitials: 'AT',
        customerPhone: '(807) 555-0177',
        shovel: true,
        crewPay: 40,
        customerTotal: 75,
        note: 'Please mind the hedge by the gate.',
        requestedAt: _past(const Duration(minutes: 10)),
      ),
      FakeJob(
        id: 'job_maple_1',
        propertyName: 'Maple Street home',
        address: '412 Maple St, Thunder Bay, ON',
        customerName: 'Sarah Mitchell',
        customerInitials: 'SM',
        customerPhone: '(807) 555-0142',
        crewPay: 25,
        customerTotal: 45,
        status: 'done',
        crewId: crewId,
        crewNote: 'Cleared right up to the garage door.',
        requestedAt: _past(const Duration(days: 2, hours: 2)),
        claimedAt: _past(const Duration(days: 2, hours: 1, minutes: 30)),
        startedAt: _past(const Duration(days: 2, hours: 1)),
        completedAt: _past(const Duration(days: 2, minutes: 13)),
      ),
      FakeJob(
        id: 'job_maple_2',
        propertyName: 'Maple Street home',
        address: '412 Maple St, Thunder Bay, ON',
        customerName: 'Sarah Mitchell',
        customerInitials: 'SM',
        customerPhone: '(807) 555-0142',
        shovel: true,
        crewPay: 35,
        customerTotal: 65,
        status: 'done',
        crewId: crewId,
        requestedAt: _past(const Duration(days: 9, hours: 2)),
        claimedAt: _past(const Duration(days: 9, hours: 1, minutes: 30)),
        startedAt: _past(const Duration(days: 9, hours: 1)),
        completedAt: _past(const Duration(days: 9)),
      ),
      FakeJob(
        id: 'job_maple_3',
        propertyName: 'Maple Street home',
        address: '412 Maple St, Thunder Bay, ON',
        customerName: 'Sarah Mitchell',
        customerInitials: 'SM',
        customerPhone: '(807) 555-0142',
        crewPay: 25,
        customerTotal: 45,
        status: 'done',
        crewId: crewId,
        paidOut: true,
        requestedAt: _past(const Duration(days: 16, hours: 2)),
        claimedAt: _past(const Duration(days: 16, hours: 1, minutes: 30)),
        startedAt: _past(const Duration(days: 16, hours: 1)),
        completedAt: _past(const Duration(days: 16)),
      ),
      FakeJob(
        id: 'job_birch',
        propertyName: 'Birch Road home',
        address: '21 Birch Rd, Thunder Bay, ON',
        customerName: 'Paul Larson',
        customerInitials: 'PL',
        crewPay: 35,
        customerTotal: 70,
        status: 'cancelled',
        crewId: crewId,
        cancelledBy: 'customer',
        requestedAt: _past(const Duration(days: 1, hours: 3)),
        claimedAt: _past(const Duration(days: 1, hours: 2)),
        cancelledAt: _past(const Duration(days: 1, hours: 1)),
      ),
    ])
      job.id: job,
  };

  final payouts = <Json>[
    {
      'id': 'payout_1',
      'crewId': crewId,
      'amount': 25,
      'jobCount': 1,
      'paidAt': _iso(_past(const Duration(days: 14))),
      'note': 'E-transfer',
    },
  ];

  Json get user => {
    'id': 'user_marcus',
    'name': 'Marcus Reid',
    'email': crewEmail,
    'role': 'crew',
    'initials': 'MR',
    'color': 'lime',
    'phone': '(807) 555-0111',
    'linkedId': crewId,
    'crewStatus': crewStatus,
  };

  /// A token the server already accepts, for tests that start signed in.
  String issueToken() {
    final token = 'token_${tokens.length + 1}';
    tokens.add(token);
    return token;
  }

  Json _view(FakeJob job) => job.toJson(crewId, leakPrices: leakPrices);

  List<FakeJob> get _done => [
    for (final job in jobs.values)
      if (job.crewId == crewId && job.status == 'done') job,
  ]..sort((a, b) => b.completedAt!.compareTo(a.completedAt!));

  /// `GET /crew/me/pay`, with "today" and "this week" in the device's time.
  Json pay() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final monday = today.subtract(Duration(days: now.weekday - 1));
    List<FakeJob> since(DateTime start) => [
      for (final job in _done)
        if (!job.completedAt!.toLocal().isBefore(start)) job,
    ];
    int sum(Iterable<FakeJob> of) => of.fold(0, (total, job) => total + job.crewPay);
    final unpaid = _done.where((job) => !job.paidOut).toList();
    return {
      'crewId': crewId,
      'name': 'Marcus Reid',
      'earnedToday': sum(since(today)),
      'jobsToday': since(today).length,
      'earnedThisWeek': sum(since(monday)),
      'jobsThisWeek': since(monday).length,
      'earnedAllTime': sum(_done),
      'unpaidTotal': sum(unpaid),
      'unpaidJobs': unpaid.map(_view).toList(),
      'payouts': payouts,
    };
  }

  late final client = MockClient((request) async {
    final path = request.url.path;
    final route = '${request.method} $path';
    requests.add(request.url.hasQuery ? '$route?${request.url.query}' : route);
    if (latency > Duration.zero) await Future<void>.delayed(latency);
    if (down) throw http.ClientException('Connection refused');
    final body = request.body.isEmpty ? <String, dynamic>{} : jsonDecode(request.body) as Json;
    if (request.method == 'POST') bodies[route] = body;

    if (route == 'POST /auth/login') {
      if (body['email'] != crewEmail || body['password'] != password) {
        return _error(401, 'invalid_credentials', 'The email or password is incorrect.');
      }
      return _json({'token': issueToken(), 'user': user});
    }

    final bearer = request.headers['authorization']?.replaceFirst('Bearer ', '');
    if (!tokens.contains(bearer)) return _error(401, 'unauthorized', 'Sign in to continue.');
    switch (route) {
      case 'GET /auth/me':
        return _json(user);
      case 'POST /auth/logout':
        tokens.remove(bearer);
        return _json({'ok': true});
    }

    // Everything below is for approved crew only.
    if (crewStatus == 'rejected') {
      return _error(403, 'crew_rejected', 'Your crew application was not approved.');
    }
    if (crewStatus != 'active') {
      return _error(403, 'crew_pending', 'Your crew application has not been approved yet.');
    }
    if (jobsUnavailable) {
      return _error(503, 'storage_unavailable', 'The server is having trouble. Try again.');
    }

    if (route == 'GET /crew/me/pay') {
      if (payUnavailable) {
        return _error(503, 'storage_unavailable', 'The server is having trouble. Try again.');
      }
      return _json(pay());
    }
    if (route == 'GET /jobs') {
      if (request.url.queryParameters['scope'] == 'open') {
        final open = jobs.values.where((job) => job.status == 'open').toList()
          ..sort((a, b) => a.requestedAt.compareTo(b.requestedAt));
        return _json(open.map(_view).toList());
      }
      DateTime activity(FakeJob job) =>
          job.completedAt ?? job.cancelledAt ?? job.startedAt ?? job.claimedAt ?? job.requestedAt;
      final mine = jobs.values.where((job) => job.crewId == crewId).toList()
        ..sort((a, b) => activity(b).compareTo(activity(a)));
      return _json(mine.map(_view).toList());
    }

    final match = RegExp(r'^/jobs/([^/]+)(?:/([a-z]+))?$').firstMatch(path);
    final job = match == null ? null : jobs[match.group(1)];
    if (match == null || job == null) return _error(404, 'not_found', 'Job not found.');
    final action = match.group(2);
    final mine = job.crewId == crewId;
    final now = DateTime.now().toUtc();

    if (request.method == 'POST' && action == 'claim') {
      if (raced.remove(job.id)) {
        job
          ..status = 'claimed'
          ..crewId = 'crew_jordan'
          ..claimedAt = now;
      }
      if (job.status == 'cancelled') {
        return _error(409, 'invalid_state', 'This job was cancelled.');
      }
      if (!mine) {
        if (job.status != 'open') {
          return _error(409, 'already_claimed', 'Another crew member already took this job.');
        }
        job
          ..status = 'claimed'
          ..crewId = crewId
          ..claimedAt = now;
      }
      return _json(_view(job));
    }

    // Crew see open jobs and their own; everything else does not exist.
    if (!mine && job.status != 'open') return _error(404, 'not_found', 'Job not found.');
    if (request.method == 'GET' && action == null) return _json(_view(job));
    if (request.method != 'POST') return _error(404, 'not_found', 'Not found.');

    switch (action) {
      case 'unclaim':
        if (job.status != 'claimed') {
          return _error(
            409,
            'invalid_state',
            'Only an accepted job that has not been started can be released.',
          );
        }
        job
          ..status = 'open'
          ..crewId = null
          ..claimedAt = null;
      case 'start':
        if (job.status == 'open') {
          return _error(409, 'invalid_state', 'Accept the job before starting it.');
        }
        if (job.status == 'claimed') {
          job
            ..status = 'inProgress'
            ..startedAt = now;
        } else if (job.status != 'inProgress') {
          return _error(409, 'invalid_state', 'This job is already finished.');
        }
      case 'complete':
        if (job.status == 'inProgress') {
          job
            ..status = 'done'
            ..completedAt = now
            ..crewNote = body['crewNote'] as String? ?? '';
        } else if (job.status != 'done') {
          return _error(409, 'invalid_state', 'Start the job before completing it.');
        }
      default:
        return _error(404, 'not_found', 'Not found.');
    }
    return _json(_view(job));
  });
}

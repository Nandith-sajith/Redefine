import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import 'store.dart';

// ---- helpers ---------------------------------------------------------------
Response _json(Object? data, {int status = 200}) => Response(
      status,
      body: jsonEncode(data),
      headers: {'content-type': 'application/json'},
    );

Future<Map<String, dynamic>> _body(Request req) async {
  final raw = await req.readAsString();
  if (raw.isEmpty) return {};
  try {
    return jsonDecode(raw) as Map<String, dynamic>;
  } catch (_) {
    return {};
  }
}

const _corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, POST, PUT, PATCH, DELETE, OPTIONS',
  'Access-Control-Allow-Headers': 'Origin, Content-Type, Accept, Authorization',
};

Middleware _cors() => (Handler inner) => (Request req) async {
      if (req.method == 'OPTIONS') {
        return Response.ok('', headers: _corsHeaders);
      }
      final res = await inner(req);
      return res.change(headers: _corsHeaders);
    };

// ---- app -------------------------------------------------------------------
Handler createApp() {
  final db = Store.instance..seed();
  final r = Router();

  r.get('/health', (Request _) => _json({'status': 'ok', 'service': 'redefine-api'}));

  // ---- Auth ---------------------------------------------------------------
  r.post('/auth/signup', (Request req) async {
    final res = db.signup(await _body(req));
    return _json(res, status: res.containsKey('error') ? 400 : 201);
  });

  r.post('/auth/login', (Request req) async {
    final b = await _body(req);
    final res = db.login(
        (b['email'] ?? '').toString(), (b['password'] ?? '').toString());
    return _json(res, status: res.containsKey('error') ? 401 : 200);
  });

  r.get('/auth/me', (Request req) {
    final u = db.userForToken(req.headers['authorization']);
    return u == null
        ? _json({'error': 'unauthorized'}, status: 401)
        : _json(u);
  });

  // ---- Customers ----------------------------------------------------------
  r.get('/customers', (Request req) {
    final status = req.url.queryParameters['status'];
    var list = db.customers;
    if (status != null && status != 'all') {
      list = list.where((c) => c['status'] == status).toList();
    }
    return _json({
      'total': db.customers.length,
      'activeSubscriptions':
          db.customers.where((c) => c['status'] == 'active').length,
      'customers': list,
    });
  });

  r.get('/customers/<id>', (Request _, String id) {
    final c = db.customers.where((e) => e['id'] == id).cast<Map?>().firstOrNull;
    if (c == null) return _json({'error': 'not found'}, status: 404);
    final props =
        db.properties.where((p) => p['customerId'] == id).toList();
    return _json({...c, 'properties': props});
  });

  // ---- Properties ---------------------------------------------------------
  r.get('/properties', (Request req) {
    final cid = req.url.queryParameters['customerId'];
    var list = db.properties;
    if (cid != null) list = list.where((p) => p['customerId'] == cid).toList();
    return _json(list);
  });

  // ---- Quotes -------------------------------------------------------------
  r.get('/quotes', (Request req) {
    final status = req.url.queryParameters['status'];
    var list = db.quotes;
    if (status != null) list = list.where((q) => q['status'] == status).toList();
    return _json(list);
  });

  r.get('/quotes/<id>', (Request _, String id) {
    final q = db.quotes.where((e) => e['id'] == id).cast<Map?>().firstOrNull;
    return q == null ? _json({'error': 'not found'}, status: 404) : _json(q);
  });

  r.post('/quotes', (Request req) async => _json(db.createQuote(await _body(req)), status: 201));

  r.post('/quotes/<id>/send', (Request req, String id) async {
    final b = await _body(req);
    final q = db.sendQuote(id, (b['biweeklyPrice'] as num?)?.toInt() ?? 52);
    return q == null ? _json({'error': 'not found'}, status: 404) : _json(q);
  });

  r.post('/quotes/<id>/accept', (Request req, String id) async {
    final b = await _body(req);
    final q = db.acceptQuote(id, b['plan']?.toString() ?? 'biweekly');
    return q == null ? _json({'error': 'not found'}, status: 404) : _json(q);
  });

  // ---- Crew ---------------------------------------------------------------
  r.get('/crew', (Request req) {
    final status = req.url.queryParameters['status'];
    var list = db.crew;
    if (status != null) list = list.where((c) => c['status'] == status).toList();
    return _json({
      'active': db.crew.where((c) => c['status'] == 'active').toList(),
      'pending': db.crew.where((c) => c['status'] == 'pending').toList(),
      'crew': list,
    });
  });

  r.post('/crew/<id>/approve', (Request _, String id) {
    final c = db.approveCrew(id, true);
    return c == null ? _json({'error': 'not found'}, status: 404) : _json(c);
  });
  r.post('/crew/<id>/reject', (Request _, String id) {
    final c = db.approveCrew(id, false);
    return c == null ? _json({'error': 'not found'}, status: 404) : _json(c);
  });

  // ---- Job cards / schedule ----------------------------------------------
  r.get('/job-cards', (Request req) {
    final status = req.url.queryParameters['status'];
    var list = db.jobCards;
    if (status != null) list = list.where((j) => j['status'] == status).toList();
    return _json(list);
  });

  r.post('/job-cards', (Request req) async => _json(db.postJobCard(await _body(req)), status: 201));

  // Cards posted and still claimable — the crew "Pending" tab.
  r.get('/pending-jobs', (Request _) {
    final list = db.jobCards
        .where((j) => j['status'] == 'awaiting' || j['status'] == 'urgent' || j['status'] == 'toPost')
        .where((j) => (j['slotsFilled'] as int) < (j['maxCrew'] as int))
        .toList();
    return _json(list);
  });

  r.post('/job-cards/<id>/claim', (Request req, String id) async {
    final b = await _body(req);
    final j = db.claimJob(id, b['crewId']?.toString() ?? 'crew-marcus',
        b['date']?.toString() ?? 'Wed May 7', b['window']?.toString() ?? 'Midday');
    return j == null ? _json({'error': 'not found'}, status: 404) : _json(j);
  });

  r.post('/job-cards/<id>/start', (Request _, String id) {
    final j = db.updateJobStatus(id, 'inProgress');
    return j == null ? _json({'error': 'not found'}, status: 404) : _json(j);
  });
  r.post('/job-cards/<id>/complete', (Request _, String id) {
    final j = db.updateJobStatus(id, 'done');
    return j == null ? _json({'error': 'not found'}, status: 404) : _json(j);
  });

  // ---- Crew home (grouped jobs) ------------------------------------------
  r.get('/crew/<id>/jobs', (Request _, String id) {
    return _json({
      'groups': [
        {
          'label': 'Today',
          'count': 2,
          'total': 96,
          'jobs': [
            {'id': 'cj-1', 'name': 'Maple Street home', 'pay': 48, 'address': '412 Maple St', 'time': '8–10am', 'phase': 'aeration'},
            {'id': 'cj-2', 'name': 'Birch Lane property', 'pay': 48, 'address': '88 Birch Ln', 'time': '11am–1pm', 'phase': 'fertilizing'},
          ],
        },
        {
          'label': 'Tomorrow',
          'count': 3,
          'total': 156,
          'jobs': [
            {'id': 'cj-3', 'name': 'Cedar Ave home', 'pay': 52, 'address': '145 Cedar Ave', 'time': '8–10am', 'phase': 'aeration'},
            {'id': 'cj-4', 'name': 'Pine Crescent', 'pay': 48, 'address': '23 Pine Cres', 'time': '11am–1pm', 'phase': 'seeding'},
            {'id': 'cj-5', 'name': 'Oak Street home', 'pay': 56, 'address': '71 Oak St', 'time': '2–4pm', 'phase': 'fertilizing'},
          ],
        },
        {
          'label': 'Rest of week',
          'count': 5,
          'total': 244,
          'summary': 'Fri – Sun · 5 more jobs scheduled',
          'jobs': [],
        },
      ],
    });
  });

  // ---- Crew pay -----------------------------------------------------------
  r.get('/crew/<id>/pay', (Request _, String id) {
    final pos = db.payouts.where((p) => p['crewId'] == id).toList();
    return _json({
      'earnedThisWeek': 144,
      'expected': 496,
      'progress': 0.29,
      'jobsDone': 3,
      'jobsTotal': 10,
      'payoutLabel': 'Payout Mon May 5',
      'earnedToday': 48,
      'jobsTodayDone': 1,
      'jobsTodayTotal': 2,
      'payouts': pos.isEmpty ? db.payouts : pos,
    });
  });

  // ---- Visits / photos ----------------------------------------------------
  r.get('/visits', (Request req) {
    final pid = req.url.queryParameters['propertyId'];
    var list = db.visits;
    if (pid != null) list = list.where((v) => v['propertyId'] == pid).toList();
    return _json(list);
  });
  r.get('/visits/<id>', (Request _, String id) {
    final v = db.visits.where((e) => e['id'] == id).cast<Map?>().firstOrNull;
    return v == null ? _json({'error': 'not found'}, status: 404) : _json(v);
  });

  // ---- Admin dashboard (home inbox) --------------------------------------
  r.get('/dashboard/admin', (Request _) {
    final quoteReqs = db.quotes.where((q) => q['status'] == 'pending').length;
    final crewApps = db.crew.where((c) => c['status'] == 'pending').length;
    final toPost = db.jobCards.where((j) => j['status'] == 'toPost').length;
    return _json({
      'greeting': 'Hi Lia!',
      'date': 'Wednesday, May 3',
      'summary': '6 jobs · \$312 booked',
      'needsAttention': [
        {'icon': 'quote', 'title': 'Quote requests · $quoteReqs', 'sub': 'Oldest pending 2 days'},
        {'icon': 'crew', 'title': 'Crew application · $crewApps', 'sub': 'Tasha Rivera, applied 2 days ago'},
        {'icon': 'card', 'title': 'Unposted job cards · $toPost', 'sub': 'Pine Cres today, Elm Way Friday'},
      ],
      'thisWeek': {
        'label': 'Wk of May 1',
        'filled': 5,
        'total': 8,
        'toPost': db.jobCards
            .where((j) => j['status'] == 'toPost')
            .map((j) => {'name': j['propertyName']})
            .toList(),
      },
      'todaysJobs': db.jobCards
          .where((j) => ['claimed', 'awaiting', 'inProgress', 'toPost', 'urgent'].contains(j['status']))
          .map((j) => {
                'name': j['propertyName'],
                'status': j['status'],
                'eta': j['eta'],
                'crewIds': j['crewIds'],
              })
          .toList(),
    });
  });

  return Pipeline().addMiddleware(logRequests()).addMiddleware(_cors()).addHandler(r.call);
}

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull => isEmpty ? null : first;
}

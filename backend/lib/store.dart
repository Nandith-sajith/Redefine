/// In-memory data store for the Redefine platform, seeded with the people and
/// jobs from the product designs. Single source of truth shared by the three
/// apps (admin / crew / customer) through the REST API.
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';

int _seq = 1000;
String _id(String prefix) => '$prefix-${_seq++}';

class Store {
  Store._();
  static final Store instance = Store._();

  // ---- Collections (JSON-ready maps) --------------------------------------
  final List<Map<String, dynamic>> customers = [];
  final List<Map<String, dynamic>> properties = [];
  final List<Map<String, dynamic>> quotes = [];
  final List<Map<String, dynamic>> crew = [];
  final List<Map<String, dynamic>> jobCards = [];
  final List<Map<String, dynamic>> visits = [];
  final List<Map<String, dynamic>> payouts = [];
  final List<Map<String, dynamic>> users = [];
  final Map<String, String> _tokens = {}; // token -> userId

  bool _seeded = false;

  void seed() {
    if (_seeded) return;
    _seeded = true;

    // ---- Users (demo accounts; password for all three is "redefine") ------
    users.addAll([
      _seedUser('user-lia', 'Lia Robinson', 'lia@redefine.co', 'admin', 'LR', null, 'redefine'),
      _seedUser('user-marcus', 'Marcus Reid', 'marcus@redefine.co', 'crew', 'MR', 'crew-marcus', 'redefine'),
      _seedUser('user-sarah', 'Sarah Mitchell', 'sarah.m@gmail.com', 'customer', 'SM', 'cust-sarah', 'redefine'),
    ]);

    // ---- Crew --------------------------------------------------------------
    crew.addAll([
      {
        'id': 'crew-marcus',
        'name': 'Marcus Reid',
        'initials': 'MR',
        'color': 'lime',
        'status': 'active',
        'jobsThisWeek': 6,
        'payThisWeek': 288,
        'email': 'marcus.r@gmail.com',
        'phone': '(807) 555-0111',
      },
      {
        'id': 'crew-jordan',
        'name': 'Jordan Park',
        'initials': 'JP',
        'color': 'teal',
        'status': 'active',
        'jobsThisWeek': 4,
        'payThisWeek': 192,
        'email': 'jordan.p@gmail.com',
        'phone': '(807) 555-0122',
      },
      {
        'id': 'crew-sam',
        'name': 'Sam Chen',
        'initials': 'SC',
        'color': 'paper',
        'status': 'active',
        'jobsThisWeek': 3,
        'payThisWeek': 144,
        'email': 'sam.c@gmail.com',
        'phone': '(807) 555-0133',
      },
      {
        'id': 'crew-pete',
        'name': 'Pete Larsson',
        'initials': 'PL',
        'color': 'paper',
        'status': 'active',
        'jobsThisWeek': 3,
        'payThisWeek': 144,
        'email': 'pete.l@gmail.com',
        'phone': '(807) 555-0144',
      },
      {
        'id': 'crew-tasha',
        'name': 'Tasha Rivera',
        'initials': 'TR',
        'color': 'teal',
        'status': 'pending',
        'jobsThisWeek': 0,
        'payThisWeek': 0,
        'email': 'tasha.r@gmail.com',
        'phone': '(807) 555-0398',
        'experience': '3 seasons landscaping',
        'appliedAgo': 'Applied 2 days ago',
      },
    ]);

    // ---- Customers ---------------------------------------------------------
    customers.addAll([
      _cust('cust-sarah', 'Sarah Mitchell', 'SM', 'lime', 'active',
          'sarah.m@gmail.com', '(807) 555-0142', '412 Maple St',
          'Next visit Wed May 7', 'since Mar 15'),
      _cust('cust-anna', 'Anna Tomlinson', 'AT', 'lime', 'active',
          'anna.t@gmail.com', '(807) 555-0150', '78 Cedar Ave',
          'Next visit Thu May 8', 'since Mar 20'),
      _cust('cust-paul', 'Paul Larson', 'PL', 'lime', 'active',
          'paul.l@gmail.com', '(807) 555-0151', '21 Birch Rd',
          'Next visit Thu May 8', 'since Apr 1'),
      _cust('cust-ben', 'Ben Jackson', 'BJ', 'teal', 'paused',
          'ben.j@gmail.com', '(807) 555-0152', '88 Birch Ln',
          'Paused · resumes May 20', 'since Feb 28'),
      _cust('cust-greg', 'Greg Henson', 'GH', 'lime', 'active',
          'greg.h@gmail.com', '(807) 555-0153', '145 Oak St',
          'Next visit Fri May 9', 'since Mar 30'),
      _cust('cust-lucas', 'Lucas Davies', 'LD', 'paper', 'oneTime',
          'lucas.d@gmail.com', '(807) 555-0154', '71 Pine Way',
          'One-time · last Apr 21', 'one-time'),
      _cust('cust-karen', 'Karen Morton', 'KM', 'lime', 'active',
          'karen.m@gmail.com', '(807) 555-0155', '312 Willow Dr',
          'Next visit Mon May 12', 'since Apr 5'),
      _cust('cust-david', 'David Roberts', 'DR', 'paper', 'oneTime',
          'david.r@gmail.com', '(807) 555-0156', '18 Elm St',
          'One-time · last Mar 15', 'one-time'),
    ]);

    // ---- Properties --------------------------------------------------------
    properties.addAll([
      {
        'id': 'prop-maple',
        'customerId': 'cust-sarah',
        'name': 'Maple Street home',
        'address': '412 Maple St, Thunder Bay, ON',
        'illustration': 'house',
        'serviceType': 'biweekly',
        'visitNumber': 4,
        'totalVisits': 16,
        'nextVisitLabel': 'Next Wed May 7',
      },
      {
        'id': 'prop-cabin',
        'customerId': 'cust-sarah',
        'name': 'Cabin',
        'address': '88 Lakeside Rd, Thunder Bay, ON',
        'illustration': 'cabin',
        'serviceType': 'oneTime',
        'visitNumber': 1,
        'totalVisits': 1,
        'nextVisitLabel': 'One-time · last visit Apr 15',
      },
    ]);

    // ---- Quotes ------------------------------------------------------------
    quotes.add({
      'id': 'quote-sarah',
      'customerId': 'cust-sarah',
      'customerName': 'Sarah Mitchell',
      'customerInitials': 'SM',
      'email': 'sarah.m@gmail.com',
      'phone': '(807) 555-0142',
      'propertyName': 'Maple Street home',
      'address': '412 Maple St',
      'propertyDesc': 'Two-story · medium yard',
      'status': 'pending',
      'submittedAt': 'Apr 30',
      'pendingDays': 2,
      'note':
          "Just bought the house, lawn's been neglected. Looking for someone reliable for the season.",
      'crewVisit': 'Visited Apr 28 by Marcus Reid',
      'biweeklyPrice': 52,
      'oneTimePrice': 85,
      'program': 'Billed bi-weekly · 16 visits · ~8 months',
    });

    // ---- Job cards (the schedule / pending board) --------------------------
    jobCards.addAll([
      _job('Pine Crescent', '23 Pine Cres', 'cust-henry', 'Henry Wallace',
          'aeration', 'May 7', 'May 1', 'urgent',
          maxCrew: 2, goTogether: true, pay: 48, slots: 1,
          time: 'This week · ends Fri', etaLabel: ''),
      _job('Elm Way', '142 Elm Way', 'cust-elm', 'Elm Way',
          'fertilizing', 'May 8', 'May 1', 'toPost',
          maxCrew: 1, goTogether: false, pay: 52, slots: 0,
          time: 'This week · ends Fri'),
      _job('Willow Drive', '312 Willow Dr', 'cust-karen', 'Karen Morton',
          'seeding', 'May 9', 'May 1', 'toPost',
          maxCrew: 2, goTogether: true, pay: 56, slots: 0,
          time: 'This week · ends Fri'),
      _job('Maple St', '412 Maple St', 'cust-sarah', 'Sarah Mitchell',
          'aeration', 'May 6', 'May 1', 'awaiting',
          maxCrew: 2, goTogether: true, pay: 48, slots: 0,
          time: 'Awaiting crew · 2 days left'),
      _job('Cedar Ave', '78 Cedar Ave', 'cust-anna', 'Anna Tomlinson',
          'aeration', 'May 7', 'May 1', 'claimed',
          maxCrew: 2, goTogether: false, pay: 52, slots: 1,
          time: 'Wed 11am', crewIds: ['crew-marcus'], etaLabel: '~11am'),
      _job('Birch Ln', '88 Birch Ln', 'cust-paul', 'Paul Larson',
          'aeration', 'May 5', 'May 1', 'done',
          maxCrew: 2, goTogether: true, pay: 48, slots: 2,
          time: 'Mon · MR · 47 min', crewIds: ['crew-marcus']),
    ]);

    // ---- Completed visits (customer timeline / photo detail) ---------------
    visits.addAll([
      {
        'id': 'visit-1',
        'propertyId': 'prop-maple',
        'date': 'Apr 22',
        'weekday': 'Tuesday',
        'ago': '11 days ago',
        'crew': 'Marcus & Tasha',
        'crewInitials': 'MT',
        'durationMin': 47,
        'visitNumber': 3,
        'totalVisits': 16,
        'phase': 'aeration',
        'note':
            'Front lawn looking great — caught a bit of crabgrass starting near the driveway, will keep an eye on it next visit.',
      },
      {
        'id': 'visit-2',
        'propertyId': 'prop-maple',
        'date': 'Apr 8',
        'weekday': 'Tuesday',
        'ago': '25 days ago',
        'crew': 'Marcus & Tasha',
        'crewInitials': 'MT',
        'durationMin': 52,
        'visitNumber': 2,
        'totalVisits': 16,
        'phase': 'fertilizing',
        'note': 'Even growth across the back. Edged along the new flower bed.',
      },
      {
        'id': 'visit-3',
        'propertyId': 'prop-maple',
        'date': 'Mar 25',
        'weekday': 'Tuesday',
        'ago': '39 days ago',
        'crew': 'Jordan & Pete',
        'crewInitials': 'JP',
        'durationMin': 58,
        'visitNumber': 1,
        'totalVisits': 16,
        'phase': 'raking',
        'note': 'First visit — full spring cleanup and rake.',
      },
    ]);

    // ---- Payouts (crew Pay screen) ----------------------------------------
    payouts.addAll([
      {'id': 'po-1', 'crewId': 'crew-marcus', 'range': 'Apr 21 – 27', 'paid': 'Paid Apr 28', 'amount': 312},
      {'id': 'po-2', 'crewId': 'crew-marcus', 'range': 'Apr 14 – 20', 'paid': 'Paid Apr 21', 'amount': 268},
      {'id': 'po-3', 'crewId': 'crew-marcus', 'range': 'Apr 7 – 13', 'paid': 'Paid Apr 14', 'amount': 295},
      {'id': 'po-4', 'crewId': 'crew-marcus', 'range': 'Mar 31 – Apr 6', 'paid': 'Paid Apr 7', 'amount': 210},
    ]);
  }

  Map<String, dynamic> _cust(String id, String name, String initials,
      String color, String status, String email, String phone,
      String address, String secondary, String since) {
    return {
      'id': id,
      'name': name,
      'initials': initials,
      'color': color,
      'status': status,
      'email': email,
      'phone': phone,
      'address': address,
      'secondary': secondary,
      'since': since,
    };
  }

  Map<String, dynamic> _job(String propertyName, String address,
      String customerId, String customerName, String phase, String date,
      String weekOf, String status,
      {required int maxCrew,
      required bool goTogether,
      required int pay,
      required int slots,
      required String time,
      List<String> crewIds = const [],
      String etaLabel = ''}) {
    return {
      'id': _id('job'),
      'propertyName': propertyName,
      'address': address,
      'customerId': customerId,
      'customerName': customerName,
      'phase': phase,
      'date': date,
      'weekOf': weekOf,
      'status': status,
      'maxCrew': maxCrew,
      'goTogether': goTogether,
      'payPerCrew': pay,
      'slotsFilled': slots,
      'crewIds': List<String>.from(crewIds),
      'time': time,
      'eta': etaLabel,
    };
  }

  // ---- Mutations ---------------------------------------------------------
  Map<String, dynamic> createQuote(Map<String, dynamic> body) {
    final q = {
      'id': _id('quote'),
      'customerId': body['customerId'] ?? 'cust-sarah',
      'customerName': body['customerName'] ?? 'New Customer',
      'customerInitials': body['customerInitials'] ?? 'NC',
      'email': body['email'] ?? '',
      'phone': body['phone'] ?? '',
      'propertyName': body['propertyName'] ?? 'New property',
      'address': body['address'] ?? '',
      'propertyDesc': body['propertyDesc'] ?? '',
      'status': 'pending',
      'submittedAt': 'Today',
      'pendingDays': 0,
      'note': body['note'] ?? '',
      'serviceType': body['serviceType'] ?? 'biweekly',
      'crewVisit': null,
      'biweeklyPrice': null,
      'oneTimePrice': 85,
      'program': 'Billed bi-weekly · 16 visits · ~8 months',
    };
    quotes.add(q);
    return q;
  }

  Map<String, dynamic>? sendQuote(String id, int biweeklyPrice) {
    final q = quotes.cast<Map<String, dynamic>?>().firstWhere(
        (e) => e!['id'] == id,
        orElse: () => null);
    if (q == null) return null;
    q['status'] = 'sent';
    q['biweeklyPrice'] = biweeklyPrice;
    q['crewVisit'] = 'Visited Apr 28 by Marcus Reid';
    return q;
  }

  Map<String, dynamic>? acceptQuote(String id, String plan) {
    final q = quotes.cast<Map<String, dynamic>?>().firstWhere(
        (e) => e!['id'] == id,
        orElse: () => null);
    if (q == null) return null;
    q['status'] = 'accepted';
    q['acceptedPlan'] = plan;
    return q;
  }

  Map<String, dynamic>? approveCrew(String id, bool approve) {
    final c = crew.cast<Map<String, dynamic>?>().firstWhere(
        (e) => e!['id'] == id,
        orElse: () => null);
    if (c == null) return null;
    c['status'] = approve ? 'active' : 'rejected';
    return c;
  }

  Map<String, dynamic>? claimJob(
      String id, String crewId, String date, String window) {
    final j = jobCards.cast<Map<String, dynamic>?>().firstWhere(
        (e) => e!['id'] == id,
        orElse: () => null);
    if (j == null) return null;
    final ids = List<String>.from(j['crewIds'] as List);
    if (!ids.contains(crewId)) ids.add(crewId);
    j['crewIds'] = ids;
    j['slotsFilled'] = ids.length;
    j['date'] = date;
    j['window'] = window;
    j['status'] = ids.length >= (j['maxCrew'] as int) ? 'claimed' : 'awaiting';
    return j;
  }

  Map<String, dynamic>? updateJobStatus(String id, String status) {
    final j = jobCards.cast<Map<String, dynamic>?>().firstWhere(
        (e) => e!['id'] == id,
        orElse: () => null);
    if (j == null) return null;
    j['status'] = status;
    return j;
  }

  Map<String, dynamic> postJobCard(Map<String, dynamic> body) {
    final j = _job(
      body['propertyName'] ?? 'New property',
      body['address'] ?? '',
      body['customerId'] ?? '',
      body['customerName'] ?? '',
      body['phase'] ?? 'aeration',
      body['date'] ?? 'This week',
      body['weekOf'] ?? 'May 1',
      'awaiting',
      maxCrew: body['maxCrew'] ?? 2,
      goTogether: body['goTogether'] ?? true,
      pay: body['payPerCrew'] ?? 48,
      slots: 0,
      time: 'Awaiting crew',
    );
    jobCards.add(j);
    return j;
  }

  // ---- Auth ---------------------------------------------------------------
  String _hash(String pw) =>
      sha256.convert(utf8.encode('redefine::$pw')).toString();

  String _initials(String name) {
    final parts =
        name.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts[0][0] + parts[1][0]).toUpperCase();
  }

  Map<String, dynamic> _seedUser(String id, String name, String email,
      String role, String initials, String? linkedId, String pw) {
    return {
      'id': id,
      'name': name,
      'email': email.toLowerCase(),
      'role': role,
      'initials': initials,
      'color': 'lime',
      'linkedId': linkedId,
      'passwordHash': _hash(pw),
    };
  }

  Map<String, dynamic> _publicUser(Map<String, dynamic> u) => {
        'id': u['id'],
        'name': u['name'],
        'email': u['email'],
        'role': u['role'],
        'initials': u['initials'],
        'color': u['color'],
        'linkedId': u['linkedId'],
      };

  String _issueToken(String userId) {
    final token =
        'tok_${_seq++}_${DateTime.now().microsecondsSinceEpoch.toRadixString(16)}';
    _tokens[token] = userId;
    return token;
  }

  Map<String, dynamic>? _findUserByEmail(String email) {
    final e = email.toLowerCase().trim();
    for (final u in users) {
      if (u['email'] == e) return u;
    }
    return null;
  }

  /// Returns `{token, user}` on success or `{error}` on failure.
  Map<String, dynamic> login(String email, String password) {
    final u = _findUserByEmail(email);
    if (u == null || u['passwordHash'] != _hash(password)) {
      return {'error': 'Invalid email or password'};
    }
    return {'token': _issueToken(u['id'] as String), 'user': _publicUser(u)};
  }

  Map<String, dynamic> signup(Map<String, dynamic> body) {
    final email = (body['email'] ?? '').toString().toLowerCase().trim();
    final password = (body['password'] ?? '').toString();
    final name = (body['name'] ?? '').toString().trim();
    if (email.isEmpty || name.isEmpty || password.length < 4) {
      return {'error': 'Name, email and a password of 4+ characters are required'};
    }
    if (_findUserByEmail(email) != null) {
      return {'error': 'An account with that email already exists'};
    }
    final u = {
      'id': _id('user'),
      'name': name,
      'email': email,
      'role': (body['role'] ?? 'customer').toString(),
      'initials': _initials(name),
      'color': 'lime',
      'linkedId': null,
      'passwordHash': _hash(password),
      'phone': body['phone'],
      'business': body['business'],
    };
    users.add(u);
    return {'token': _issueToken(u['id'] as String), 'user': _publicUser(u)};
  }

  Map<String, dynamic>? userForToken(String? authHeader) {
    if (authHeader == null) return null;
    final token = authHeader.replaceFirst('Bearer ', '').trim();
    final uid = _tokens[token];
    if (uid == null) return null;
    for (final u in users) {
      if (u['id'] == uid) return _publicUser(u);
    }
    return null;
  }
}

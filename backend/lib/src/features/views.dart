import '../data/store.dart';
import '../http.dart';
import '../model.dart';
import '../time.dart';

/// A JSON object of a response body.
typedef Json = Map<String, Object?>;

/// The User shape, the same for every role.
Json userView(DocReader db, Doc user) {
  final linkedId = user['linkedId'] as String?;
  final crew = user['role'] == Role.crew && linkedId != null
      ? db.get(Collections.crew, linkedId)
      : null;
  return {
    'id': user['id'],
    'name': user['name'],
    'email': user['email'],
    'role': user['role'],
    'initials': user['initials'],
    'color': user['color'],
    'phone': user['phone'] ?? '',
    'linkedId': linkedId,
    'crewStatus': crew?['status'],
  };
}

/// Turns stored documents into response bodies for one caller.
///
/// This is the only place that decides which fields a role receives; private
/// fields (password hashes, Stripe ids, payout ids) are never copied out.
/// Build a fresh instance after the last write of a request.
class Views {
  final DocReader db;

  /// The caller's role.
  final String role;

  /// The caller's crew id (role crew), else null.
  final String? crewId;

  Views(this.db, {required this.role, this.crewId});

  /// Views for the caller of a request.
  Views.of(this.db, AuthCtx caller)
    : role = caller.role,
      crewId = caller.crewId;

  bool get _isAdmin => role == Role.admin;
  bool get _isCrew => role == Role.crew;
  bool get _isCustomer => role == Role.customer;

  late final Map<String, Doc> _unfinishedByProperty = {
    for (final j in db.where(
      Collections.jobs,
      (j) => JobStatus.unfinished.contains(j['status']),
    ))
      j['propertyId'] as String: j,
  };

  /// Settings; [paymentsMode] is `stripe` or `manual`.
  Json settings(Doc s, {required String paymentsMode}) => {
    if (!_isCrew) 'shovelPrice': s['shovelPrice'],
    if (!_isCustomer) 'crewShovelBonus': s['crewShovelBonus'],
    if (_isAdmin) 'openJobExpiryHours': s['openJobExpiryHours'],
    'currency': currency,
    if (!_isCrew) 'paymentsMode': paymentsMode,
  };

  Json property(Doc p) {
    final activeJob = _unfinishedByProperty[p['id']];
    return {
      'id': p['id'],
      'name': p['name'],
      'address': p['address'],
      'illustration': p['illustration'],
      'note': p['note'],
      'status': p['status'],
      'price': p['price'],
      'quoteId': p['quoteId'],
      'createdAt': p['createdAt'],
      'activeJob': activeJob == null ? null : job(activeJob),
      if (_isAdmin) ...{
        'customerId': p['customerId'],
        'customerName': _customerOf(p)?['name'] ?? '',
        'crewPay': p['crewPay'],
      },
    };
  }

  Json quote(Doc q) {
    final customer = _customerOf(q);
    final property = _propertyOf(q);
    return {
      'id': q['id'],
      'propertyId': q['propertyId'],
      'customerId': q['customerId'],
      'status': q['status'],
      'note': q['note'],
      'price': q['price'],
      'crewPay': _isAdmin ? q['crewPay'] : null,
      'createdAt': q['createdAt'],
      'sentAt': q['sentAt'],
      'decidedAt': q['decidedAt'],
      'customerName': customer?['name'] ?? '',
      'customerInitials': customer?['initials'] ?? '',
      'customerColor': customer?['color'] ?? '',
      'email': customer?['email'] ?? '',
      'phone': customer?['phone'] ?? '',
      'propertyName': property?['name'] ?? '',
      'address': property?['address'] ?? '',
      'illustration': property?['illustration'] ?? illustrations.first,
    };
  }

  Json job(Doc j) {
    final property = _propertyOf(j);
    final jobCrewId = j['crewId'] as String?;
    final crew = jobCrewId == null ? null : db.get(Collections.crew, jobCrewId);
    // Crew learn who the customer is only once the job is theirs.
    final customer = !_isCrew || (jobCrewId != null && jobCrewId == crewId)
        ? _customerOf(j)
        : null;
    final payment = j['payment'] as Map<String, dynamic>;
    return {
      'id': j['id'],
      'propertyId': j['propertyId'],
      'customerId': j['customerId'],
      'propertyName': property?['name'] ?? '',
      'address': property?['address'] ?? '',
      'illustration': property?['illustration'] ?? illustrations.first,
      'customerName': customer?['name'] ?? '',
      'customerInitials': customer?['initials'] ?? '',
      'customerPhone': customer?['phone'] ?? '',
      'shovel': j['shovel'],
      if (!_isCrew) ...{
        'price': j['price'],
        'shovelPrice': j['shovelPrice'],
        'total': j['total'],
      },
      if (!_isCustomer) 'crewPay': j['crewPay'],
      'status': j['status'],
      if (!_isCustomer) 'crewId': jobCrewId,
      'crewName': crew?['name'] ?? '',
      'crewInitials': crew?['initials'] ?? '',
      'crewColor': crew?['color'] ?? '',
      'note': j['note'],
      'crewNote': j['crewNote'],
      'source': j['source'],
      'requestedAt': j['requestedAt'],
      'claimedAt': j['claimedAt'],
      'startedAt': j['startedAt'],
      'completedAt': j['completedAt'],
      'cancelledAt': j['cancelledAt'],
      'cancelledBy': j['cancelledBy'],
      if (!_isCrew)
        'payment': {
          'mode': payment['mode'],
          'status': payment['status'],
          'error': payment['error'],
          'holdExpiresAt': payment['holdExpiresAt'],
          'capturedAt': payment['capturedAt'],
        },
      if (!_isCustomer) 'paidOut': j['payoutId'] != null,
    };
  }

  /// The customer's own billing page. [mode] is `stripe` or `manual`.
  Json billing(
    Doc customer, {
    required String mode,
    required bool pendingSetup,
  }) {
    final charges = db.where(
      Collections.jobs,
      (j) =>
          j['customerId'] == customer['id'] &&
          PaymentStatus.charges.contains(_paymentStatus(j)),
    );
    sortByKey(charges, _chargeDate, descending: true);
    return {
      'mode': mode,
      'card': _card(customer),
      'pendingSetup': pendingSetup,
      'balanceDue': _sum(
        charges.where(
          (j) => PaymentStatus.outstanding.contains(_paymentStatus(j)),
        ),
        'total',
      ),
      'charges': [
        for (final j in charges)
          {
            'jobId': j['id'],
            'propertyName': _propertyOf(j)?['name'] ?? '',
            'date': _chargeDate(j),
            'total': j['total'],
            'shovel': j['shovel'],
            'status': _paymentStatus(j),
          },
      ],
    };
  }

  /// A crew member as the admin sees them. [tz] is the caller's UTC offset.
  Json crewMember(Doc c, {required DateTime now, required Duration tz}) {
    final done = _doneJobsOf(c['id'] as String);
    final week = _completedSince(done, localWeekStart(now, tz));
    final unpaid = done.where((j) => j['payoutId'] == null).toList();
    return {
      'id': c['id'],
      'userId': c['userId'],
      'name': c['name'],
      'initials': c['initials'],
      'color': c['color'],
      'email': c['email'],
      'phone': c['phone'] ?? '',
      'status': c['status'],
      'appliedAt': c['appliedAt'],
      'jobsThisWeek': week.length,
      'earnedThisWeek': _sum(week, 'crewPay'),
      'unpaidTotal': _sum(unpaid, 'crewPay'),
      'unpaidJobs': unpaid.length,
    };
  }

  /// A crew member's earnings. The unpaid jobs are in that crew member's
  /// own Job view whoever asks. [tz] is the caller's UTC offset.
  Json crewPay(Doc c, {required DateTime now, required Duration tz}) {
    final id = c['id'] as String;
    final done = _doneJobsOf(id);
    sortByTime(done, 'completedAt', descending: true);
    final today = _completedSince(done, localDayStart(now, tz));
    final week = _completedSince(done, localWeekStart(now, tz));
    final unpaid = done.where((j) => j['payoutId'] == null).toList();
    final payouts = db.where(Collections.payouts, (p) => p['crewId'] == id);
    sortByTime(payouts, 'paidAt', descending: true);
    final asCrew = _isCrew && crewId == id
        ? this
        : Views(db, role: Role.crew, crewId: id);
    return {
      'crewId': id,
      'name': c['name'],
      'earnedToday': _sum(today, 'crewPay'),
      'jobsToday': today.length,
      'earnedThisWeek': _sum(week, 'crewPay'),
      'jobsThisWeek': week.length,
      'earnedAllTime': _sum(done, 'crewPay'),
      'unpaidTotal': _sum(unpaid, 'crewPay'),
      'unpaidJobs': unpaid.map(asCrew.job).toList(),
      'payouts': payouts.map(payout).toList(),
    };
  }

  Json payout(Doc p) => {
    'id': p['id'],
    'crewId': p['crewId'],
    'amount': p['amount'],
    'jobCount': p['jobCount'],
    'paidAt': p['paidAt'],
    'note': p['note'],
  };

  /// A customer as one row of the admin's list.
  Json customer(Doc c) => _customer(c, _propertiesOf(c), _jobsOf(c));

  /// A customer with their properties, latest jobs and money totals.
  Json customerDetail(Doc c) {
    final properties = _propertiesOf(c);
    final jobs = _jobsOf(c);
    return {
      ..._customer(c, properties, jobs),
      'card': _card(c),
      'properties': properties.map(property).toList(),
      'jobs': jobs.take(50).map(job).toList(),
      'totals': {
        'billed': _sum(
          jobs.where((j) => PaymentStatus.billed.contains(_paymentStatus(j))),
          'total',
        ),
        'outstanding': _sum(
          jobs.where(
            (j) => PaymentStatus.outstanding.contains(_paymentStatus(j)),
          ),
          'total',
        ),
      },
    };
  }

  Json _customer(Doc c, List<Doc> properties, List<Doc> jobs) => {
    'id': c['id'],
    'name': c['name'],
    'initials': c['initials'],
    'color': c['color'],
    'email': c['email'],
    'phone': c['phone'] ?? '',
    'createdAt': c['createdAt'],
    'propertyCount': properties.length,
    'activeProperties': properties
        .where((p) => p['status'] == PropertyStatus.active)
        .length,
    'jobCount': jobs.length,
    'lastJobAt': jobs.isEmpty ? null : jobs.first['requestedAt'],
    'hasCard': c['card'] != null,
    'addresses': [for (final p in properties) p['address']],
  };

  Json? _card(Doc customer) {
    final card = customer['card'] as Map<String, dynamic>?;
    return card == null
        ? null
        : {
            'brand': card['brand'],
            'last4': card['last4'],
            'expMonth': card['expMonth'],
            'expYear': card['expYear'],
            'updatedAt': card['updatedAt'],
          };
  }

  Doc? _customerOf(Doc doc) =>
      db.get(Collections.customers, doc['customerId'] as String);

  Doc? _propertyOf(Doc doc) =>
      db.get(Collections.properties, doc['propertyId'] as String);

  /// The customer's properties, oldest first.
  List<Doc> _propertiesOf(Doc customer) {
    final found = db.where(
      Collections.properties,
      (p) => p['customerId'] == customer['id'],
    );
    sortByTime(found, 'createdAt');
    return found;
  }

  /// The customer's jobs, newest request first.
  List<Doc> _jobsOf(Doc customer) {
    final found = db.where(
      Collections.jobs,
      (j) => j['customerId'] == customer['id'],
    );
    sortByTime(found, 'requestedAt', descending: true);
    return found;
  }

  List<Doc> _doneJobsOf(String crewId) => db.where(
    Collections.jobs,
    (j) => j['crewId'] == crewId && j['status'] == JobStatus.done,
  );
}

String _paymentStatus(Doc job) =>
    (job['payment'] as Map<String, dynamic>)['status'] as String;

String _chargeDate(Doc job) =>
    (job['completedAt'] ?? job['requestedAt']) as String;

int _sum(Iterable<Doc> docs, String field) =>
    docs.fold(0, (total, d) => total + (d[field] as int));

List<Doc> _completedSince(List<Doc> jobs, DateTime start) => [
  for (final j in jobs)
    if (parseTime(j['completedAt'])?.isBefore(start) == false) j,
];

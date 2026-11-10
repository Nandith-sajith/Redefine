import 'package:shelf/shelf.dart';

import '../app.dart';
import '../data/store.dart';
import '../errors.dart';
import '../http.dart';
import '../model.dart';
import '../routes.dart';
import '../time.dart';
import 'views.dart';

/// Settings, the customer directory and the admin dashboard.
void mountAdmin(Routes r, App app) {
  final store = app.store;

  r.get('/settings', (Request req) {
    final ctx = authOf(req);
    return jsonOk(
      Views.of(
        store,
        ctx,
      ).settings(store.settings!, paymentsMode: app.paymentsMode),
    );
  });

  r.post('/settings', (Request req) async {
    final ctx = authOf(req, roles: {Role.admin});
    final body = await readJson(req);
    final shovelPrice = optInt(body, 'shovelPrice', min: 0, max: 1000);
    final crewShovelBonus = optInt(body, 'crewShovelBonus', min: 0, max: 1000);
    final expiryHours = optInt(body, 'openJobExpiryHours', min: 1, max: 120);
    final settings = store.tx((tx) {
      final updated = {
        ...tx.settings!,
        'shovelPrice': ?shovelPrice,
        'crewShovelBonus': ?crewShovelBonus,
        'openJobExpiryHours': ?expiryHours,
      };
      if ((updated['crewShovelBonus'] as int) >
          (updated['shovelPrice'] as int)) {
        throw ApiError.validation(
          'crewShovelBonus must be a whole number from 0 to '
          '${updated['shovelPrice']} (the shovel price).',
        );
      }
      return tx.put(Collections.settings, updated);
    });
    return jsonOk(
      Views.of(store, ctx).settings(settings, paymentsMode: app.paymentsMode),
    );
  });

  r.get('/customers', (Request req) {
    final ctx = authOf(req, roles: {Role.admin});
    final customers = store.all(Collections.customers);
    sortByKey(customers, (c) => (c['name'] as String).toLowerCase());
    return jsonOk(customers.map(Views.of(store, ctx).customer).toList());
  });

  r.get('/customers/<id>', (Request req, String id) {
    final ctx = authOf(req, roles: {Role.admin});
    final customer = store.require(Collections.customers, id, what: 'Customer');
    return jsonOk(Views.of(store, ctx).customerDetail(customer));
  });

  r.get('/dashboard/admin', (Request req) {
    final ctx = authOf(req, roles: {Role.admin});
    final now = app.now();
    final tz = tzOffset(req);
    final today = localDayStart(now, tz);
    final views = Views.of(store, ctx);

    final quotes = store.all(Collections.quotes);
    final pendingQuotes = [
      for (final q in quotes)
        if (q['status'] == QuoteStatus.pending) q,
    ];
    sortByTime(pendingQuotes, 'createdAt');

    final jobs = store.all(Collections.jobs);
    int withStatus(String status) =>
        jobs.where((j) => j['status'] == status).length;
    bool sinceToday(Doc job, String field) =>
        parseTime(job[field])?.isBefore(today) == false;
    final liveJobs = [
      for (final j in jobs)
        if (JobStatus.unfinished.contains(j['status'])) j,
    ];
    sortByTime(liveJobs, 'requestedAt');
    final doneToday = [
      for (final j in jobs)
        if (j['status'] == JobStatus.done && sinceToday(j, 'completedAt')) j,
    ];
    final paymentIssues = [
      for (final j in jobs)
        if (PaymentStatus.outstanding.contains(
          (j['payment'] as Map<String, dynamic>)['status'],
        ))
          j,
    ];
    sortByTime(paymentIssues, 'completedAt', descending: true);

    final pendingCrew = store.where(
      Collections.crew,
      (c) => c['status'] == CrewStatus.pending,
    );
    sortByTime(pendingCrew, 'appliedAt');

    return jsonOk({
      'serverTime': isoTime(now),
      'counts': {
        'pendingQuotes': pendingQuotes.length,
        'sentQuotes': quotes
            .where((q) => q['status'] == QuoteStatus.sent)
            .length,
        'pendingCrew': pendingCrew.length,
        'openJobs': withStatus(JobStatus.open),
        'claimedJobs': withStatus(JobStatus.claimed),
        'inProgressJobs': withStatus(JobStatus.inProgress),
        'doneToday': doneToday.length,
        'cancelledToday': jobs
            .where(
              (j) =>
                  j['status'] == JobStatus.cancelled &&
                  sinceToday(j, 'cancelledAt'),
            )
            .length,
        'revenueToday': doneToday.fold<int>(
          0,
          (sum, j) => sum + (j['total'] as int),
        ),
        'paymentIssues': paymentIssues.length,
      },
      'pendingQuotes': pendingQuotes.map(views.quote).toList(),
      'liveJobs': liveJobs.map(views.job).toList(),
      'pendingCrew': [
        for (final c in pendingCrew) views.crewMember(c, now: now, tz: tz),
      ],
      'paymentIssues': paymentIssues.map(views.job).toList(),
    });
  });
}

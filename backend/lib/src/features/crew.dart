import 'package:shelf/shelf.dart';

import '../app.dart';
import '../auth/tokens.dart';
import '../data/docs.dart';
import '../data/store.dart';
import '../errors.dart';
import '../http.dart';
import '../model.dart';
import '../routes.dart';
import 'jobs.dart' show reopenClaimedJobs;
import 'views.dart';

/// The crew list, approvals, earnings and payouts.
void mountCrew(Routes r, App app) {
  final store = app.store;

  Response setStatus(Request req, String id, String status) {
    final ctx = authOf(req, roles: {Role.admin});
    final tz = tzOffset(req);
    final member = store.tx((tx) {
      tx.require(Collections.crew, id, what: 'Crew member');
      if (status == CrewStatus.rejected) reopenClaimedJobs(tx, id);
      return tx.patch(Collections.crew, id, {'status': status});
    });
    return jsonOk(
      Views.of(store, ctx).crewMember(member, now: app.now(), tz: tz),
    );
  }

  r.get('/crew', (Request req) {
    final ctx = authOf(req, roles: {Role.admin});
    final now = app.now();
    final tz = tzOffset(req);
    final views = Views.of(store, ctx);
    List<Json> withStatus(String status, {bool byName = true}) {
      final members = store.where(
        Collections.crew,
        (c) => c['status'] == status,
      );
      if (byName) {
        sortByKey(members, (c) => (c['name'] as String).toLowerCase());
      } else {
        sortByTime(members, 'appliedAt');
      }
      return [for (final c in members) views.crewMember(c, now: now, tz: tz)];
    }

    return jsonOk({
      'active': withStatus(CrewStatus.active),
      'pending': withStatus(CrewStatus.pending, byName: false),
      'rejected': withStatus(CrewStatus.rejected),
    });
  });

  r.post(
    '/crew/<id>/approve',
    (Request req, String id) => setStatus(req, id, CrewStatus.active),
  );
  r.post(
    '/crew/<id>/reject',
    (Request req, String id) => setStatus(req, id, CrewStatus.rejected),
  );

  r.get('/crew/<id>/pay', (Request req, String id) {
    final ctx = authOf(req, roles: {Role.crew, Role.admin});
    final String crewId;
    if (ctx.isCrew) {
      ctx.requireActiveCrew();
      if (id != 'me' && id != ctx.crewId) {
        throw ApiError.notFound('Crew member');
      }
      crewId = ctx.crewId!;
    } else {
      crewId = id;
    }
    final member = store.require(Collections.crew, crewId, what: 'Crew member');
    return jsonOk(
      Views.of(store, ctx).crewPay(member, now: app.now(), tz: tzOffset(req)),
    );
  });

  r.post('/crew/<id>/payouts', (Request req, String id) async {
    final ctx = authOf(req, roles: {Role.admin});
    store.require(Collections.crew, id, what: 'Crew member');
    final tz = tzOffset(req);
    final note = optString(await readJson(req), 'note', max: 500);
    final now = app.now();
    final payout = store.tx((tx) {
      final unpaid = tx.where(
        Collections.jobs,
        (j) =>
            j['crewId'] == id &&
            j['status'] == JobStatus.done &&
            j['payoutId'] == null,
      );
      if (unpaid.isEmpty) throw ApiError.nothingToPay();
      final payout = tx.insert(
        Collections.payouts,
        payoutDoc(
          id: newId('payout'),
          crewId: id,
          amount: unpaid.fold(0, (sum, j) => sum + (j['crewPay'] as int)),
          jobCount: unpaid.length,
          paidAt: now,
          note: note,
        ),
      );
      for (final job in unpaid) {
        tx.patch(Collections.jobs, job['id'] as String, {
          'payoutId': payout['id'],
        });
      }
      return payout;
    });
    final views = Views.of(store, ctx);
    return jsonOk({
      'payout': views.payout(payout),
      'pay': views.crewPay(
        store.require(Collections.crew, id),
        now: now,
        tz: tz,
      ),
    });
  });
}

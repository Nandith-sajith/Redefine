import 'dart:async';

import 'package:shelf/shelf.dart';

import '../app.dart';
import '../auth/tokens.dart';
import '../data/docs.dart';
import '../data/persistence.dart' show StorageException;
import '../data/store.dart';
import '../errors.dart';
import '../http.dart';
import '../model.dart';
import '../payments/gateway.dart';
import '../routes.dart';
import '../time.dart';
import 'views.dart';

const _sweepInterval = Duration(minutes: 10);

/// This long after `holdExpiresAt` the card network has dropped the hold
/// for certain, so there is nothing left to release.
const _holdGoneAfter = Duration(days: 3);

/// Plough requests: create, list, the crew's accept/start/complete steps,
/// cancelling and the admin's payment actions.
void mountJobs(Routes r, App app) {
  final store = app.store;

  Response jobResponse(AuthCtx ctx, String id, {int status = 200}) => jsonOk(
    Views.of(store, ctx).job(store.require(Collections.jobs, id, what: 'Job')),
    status: status,
  );

  r.post('/jobs', (Request req) async {
    final ctx = authOf(req, roles: {Role.customer, Role.admin});
    final body = await readJson(req);
    final propertyId = reqString(body, 'propertyId', max: 200);
    final shovel = optBool(body, 'shovel');
    final note = optString(body, 'note', max: 500);
    final wanted = ctx.isAdmin
        ? optEnum(body, 'payment', const {'card', 'manual'})
        : null;

    final property = store.get(Collections.properties, propertyId);
    if (property == null ||
        (ctx.isCustomer && property['customerId'] != ctx.customerId)) {
      throw ApiError.notFound('Property');
    }
    _requireRequestable(store, property);
    final customer = store.require(
      Collections.customers,
      property['customerId'] as String,
      what: 'Customer',
    );
    final stripeCustomerId = customer['stripeCustomerId'] as String?;
    final card = customer['stripePaymentMethodId'] as String?;
    final gateway = app.payments;

    final bool byCard;
    if (gateway == null) {
      if (wanted == 'card') throw ApiError.paymentsManual();
      byCard = false;
    } else if (wanted == 'manual') {
      byCard = false;
    } else if (stripeCustomerId != null && card != null) {
      byCard = true;
    } else if (ctx.isCustomer || wanted == 'card') {
      throw ApiError.cardRequired();
    } else {
      byCard = false;
    }

    final requestedAt = app.now();
    final draft = jobDoc(
      id: newId('job'),
      property: property,
      settings: store.settings!,
      shovel: shovel,
      note: note,
      source: ctx.role,
      requestedAt: requestedAt,
      payment: manualPayment(),
    );
    final jobId = draft['id'] as String;

    Doc insert(Tx tx, Map<String, dynamic> payment) {
      final current = tx.require(
        Collections.properties,
        propertyId,
        what: 'Property',
      );
      _requireRequestable(tx, current);
      if (current['price'] != property['price'] ||
          current['crewPay'] != property['crewPay']) {
        throw ApiError.invalidState(
          'The price of this property has just changed. Check it and '
          'request again.',
        );
      }
      return tx.insert(Collections.jobs, {...draft, 'payment': payment});
    }

    if (!byCard) {
      store.tx((tx) => insert(tx, manualPayment()));
      return jobResponse(ctx, jobId, status: 201);
    }

    // One hold at a time per property: a second request must not place
    // another hold while the first is still on its way to Stripe.
    if (!app.busyProperties.add(propertyId)) {
      throw ApiError.invalidState(
        'A plough request for this property is already being processed.',
      );
    }
    try {
      Future<HoldResult> placeHold() => gateway!.authorize(
        jobId: jobId,
        stripeCustomerId: stripeCustomerId!,
        paymentMethodId: card!,
        amountDollars: draft['total'] as int,
      );
      var hold = await placeHold();
      // The answer got lost, so the card may be held without anyone knowing
      // the hold's id. The same request again gets the answer to the first.
      if (hold.inDoubt) hold = await placeHold();
      final intentId = hold.paymentIntentId;
      if (!hold.isOk || intentId == null) throw _holdError(app, hold, jobId);
      try {
        store.tx(
          (tx) => insert(
            tx,
            cardHoldPayment(
              paymentIntentId: intentId,
              paymentMethodId: card!,
              heldAt: requestedAt,
            ),
          ),
        );
        // Saved here rather than by `autoFlush`, to learn whether the job
        // survived: a takeover reload drops it and with it the hold's id.
        await store.flush();
      } on Object {
        // No job came of it, so the money must not stay held.
        if (store.get(Collections.jobs, jobId) == null) {
          await _cancelQuietly(app, intentId, jobId);
        }
        rethrow;
      }
    } finally {
      app.busyProperties.remove(propertyId);
    }
    return jobResponse(ctx, jobId, status: 201);
  });

  r.get('/jobs', (Request req) {
    final ctx = authOf(req);
    final List<Doc> found;
    var limit = 100;
    if (ctx.isCrew) {
      ctx.requireActiveCrew();
      final scope = queryEnum(req, 'scope', const {'open', 'mine'}) ?? 'mine';
      if (scope == 'open') {
        found = store.where(
          Collections.jobs,
          (j) => j['status'] == JobStatus.open,
        );
        sortByTime(found, 'requestedAt');
        limit = found.length;
      } else {
        found = store.where(Collections.jobs, (j) => j['crewId'] == ctx.crewId);
        sortByKey(found, _lastActivity, descending: true);
      }
    } else {
      final statuses = queryEnumSet(req, 'status', JobStatus.all);
      final propertyId = queryString(req, 'propertyId');
      String? customerId = ctx.customerId;
      String? crewId;
      Set<String>? payments;
      String? from;
      String? to;
      if (ctx.isAdmin) {
        limit = 300;
        customerId = queryString(req, 'customerId');
        crewId = queryString(req, 'crewId');
        payments = queryEnumSet(req, 'payment', PaymentStatus.all);
        final fromTime = queryTime(req, 'from');
        final toTime = queryTime(req, 'to');
        from = fromTime == null ? null : isoTime(fromTime);
        to = toTime == null ? null : isoTime(toTime);
      }
      found = store.where(Collections.jobs, (j) {
        final requestedAt = j['requestedAt'] as String;
        return (customerId == null || j['customerId'] == customerId) &&
            (propertyId == null || j['propertyId'] == propertyId) &&
            (crewId == null || j['crewId'] == crewId) &&
            (statuses == null || statuses.contains(j['status'])) &&
            (payments == null || payments.contains(_payment(j)['status'])) &&
            (from == null || requestedAt.compareTo(from) >= 0) &&
            (to == null || requestedAt.compareTo(to) <= 0);
      });
      sortByTime(found, 'requestedAt', descending: true);
    }
    return jsonOk(found.take(limit).map(Views.of(store, ctx).job).toList());
  });

  r.get('/jobs/<id>', (Request req, String id) {
    final ctx = authOf(req);
    if (ctx.isCrew) ctx.requireActiveCrew();
    _visible(store, ctx, id);
    return jobResponse(ctx, id);
  });

  r.post('/jobs/<id>/claim', (Request req, String id) {
    final ctx = authOf(req, roles: {Role.crew})..requireActiveCrew();
    // Check and write in one synchronous transaction: of two crew members
    // racing for the job exactly one finds it still open.
    store.tx((tx) {
      final job = tx.require(Collections.jobs, id, what: 'Job');
      final status = job['status'];
      if (status == JobStatus.cancelled) {
        throw ApiError.invalidState('This job was cancelled.');
      }
      if (job['crewId'] == ctx.crewId) return;
      if (status != JobStatus.open) throw ApiError.alreadyClaimed();
      tx.patch(Collections.jobs, id, {
        'status': JobStatus.claimed,
        'crewId': ctx.crewId,
        'claimedAt': isoTime(app.now()),
      });
    });
    return jobResponse(ctx, id);
  });

  r.post('/jobs/<id>/unclaim', (Request req, String id) {
    final ctx = authOf(req, roles: {Role.crew, Role.admin});
    if (ctx.isCrew) ctx.requireActiveCrew();
    store.tx((tx) {
      final job = _visible(tx, ctx, id);
      if (job['status'] != JobStatus.claimed) {
        throw ApiError.invalidState(
          'Only an accepted job that has not been started can be released.',
        );
      }
      tx.patch(Collections.jobs, id, _reopened);
    });
    return jobResponse(ctx, id);
  });

  r.post('/jobs/<id>/start', (Request req, String id) {
    final ctx = authOf(req, roles: {Role.crew})..requireActiveCrew();
    store.tx((tx) {
      final job = _visible(tx, ctx, id);
      final status = job['status'];
      if (status == JobStatus.inProgress) return;
      if (status != JobStatus.claimed) {
        throw ApiError.invalidState(
          status == JobStatus.open
              ? 'Accept the job before starting it.'
              : 'This job is already finished.',
        );
      }
      tx.patch(Collections.jobs, id, {
        'status': JobStatus.inProgress,
        'startedAt': isoTime(app.now()),
      });
    });
    return jobResponse(ctx, id);
  });

  r.post('/jobs/<id>/complete', (Request req, String id) async {
    final ctx = authOf(req, roles: {Role.crew, Role.admin});
    if (ctx.isCrew) ctx.requireActiveCrew();
    _visible(store, ctx, id);
    final crewNote = optString(await readJson(req), 'crewNote', max: 500);
    store.tx((tx) {
      final job = _visible(tx, ctx, id);
      final status = job['status'];
      if (status == JobStatus.done) return;
      final ready =
          status == JobStatus.inProgress ||
          (ctx.isAdmin && status == JobStatus.claimed);
      if (!ready) {
        throw ApiError.invalidState(switch (status) {
          JobStatus.cancelled => 'This job was cancelled.',
          JobStatus.open => 'Nobody has accepted this job yet.',
          _ => 'Start the job before completing it.',
        });
      }
      tx.update(Collections.jobs, id, (draft) {
        draft['status'] = JobStatus.done;
        draft['completedAt'] = isoTime(app.now());
        draft['crewNote'] = crewNote;
        final payment = _payment(draft);
        if (payment['mode'] == PaymentMode.manual) {
          payment['status'] = PaymentStatus.due;
        }
      });
    });
    // The job is done whatever happens to the charge from here on.
    await _finishPayment(app, id);
    return jobResponse(ctx, id);
  });

  r.post('/jobs/<id>/cancel', (Request req, String id) async {
    final ctx = authOf(req, roles: {Role.customer, Role.admin});
    store.tx((tx) {
      final job = _visible(tx, ctx, id);
      switch (job['status']) {
        case JobStatus.cancelled:
          return;
        case JobStatus.done:
          throw ApiError.invalidState('A completed job cannot be cancelled.');
        case JobStatus.inProgress when ctx.isCustomer:
          throw ApiError.jobStarted();
      }
      tx.patch(Collections.jobs, id, {
        'status': JobStatus.cancelled,
        'cancelledAt': isoTime(app.now()),
        'cancelledBy': ctx.role,
      });
    });
    await _finishPayment(app, id);
    return jobResponse(ctx, id);
  });

  r.post('/jobs/<id>/mark-paid', (Request req, String id) async {
    final ctx = authOf(req, roles: {Role.admin});
    final leftoverHold = store.tx((tx) {
      final payment = _payment(tx.require(Collections.jobs, id, what: 'Job'));
      if (payment['status'] == PaymentStatus.paid) return null;
      if (!PaymentStatus.outstanding.contains(payment['status'])) {
        throw ApiError.invalidState(
          'Only a due or failed payment can be marked as paid.',
        );
      }
      if (app.busyJobs.contains(id)) {
        throw ApiError.invalidState(
          'A card payment for this job is being processed. Try again shortly.',
        );
      }
      tx.update(Collections.jobs, id, (draft) {
        _payment(draft)
          ..['status'] = PaymentStatus.paid
          ..['error'] = null
          ..['capturedAt'] = isoTime(app.now());
      });
      return payment['paymentIntentId'] as String?;
    });
    // Paid some other way: the card must not stay held for the same job.
    if (leftoverHold != null && app.payments != null) {
      await store.flush();
      await _cancelQuietly(app, leftoverHold, id);
    }
    return jobResponse(ctx, id);
  });

  r.post('/jobs/<id>/retry-payment', (Request req, String id) async {
    final ctx = authOf(req, roles: {Role.admin});
    final job = store.require(Collections.jobs, id, what: 'Job');
    final payment = _payment(job);
    if (job['status'] != JobStatus.done ||
        payment['mode'] != PaymentMode.stripe ||
        payment['status'] != PaymentStatus.failed) {
      throw ApiError.invalidState(
        'Only a failed card payment of a completed job can be retried.',
      );
    }
    if (app.payments == null) {
      throw ApiError.invalidState(
        'Card payments are not enabled on this server.',
      );
    }
    if (!app.busyJobs.add(id)) {
      throw ApiError.invalidState(
        'A card payment for this job is already being processed.',
      );
    }
    try {
      await _settle(app, id);
    } finally {
      app.busyJobs.remove(id);
    }
    return jobResponse(ctx, id);
  });
}

/// Puts every job that [crewId] has accepted but not started back on the
/// open list. Returns how many were reopened.
int reopenClaimedJobs(Tx tx, String crewId) {
  final claimed = tx.where(
    Collections.jobs,
    (j) => j['crewId'] == crewId && j['status'] == JobStatus.claimed,
  );
  for (final job in claimed) {
    tx.patch(Collections.jobs, job['id'] as String, _reopened);
  }
  return claimed.length;
}

/// Cancels open jobs nobody accepted within `settings.openJobExpiryHours`
/// (`cancelledBy: system`), releases their holds, and finishes card work a
/// crash or a failed save left behind.
///
/// Runs at most every ten minutes unless [force]d. Never throws: a failure
/// is logged and retried by the next sweep. The caller flushes the store
/// afterwards.
Future<void> sweepStaleJobs(App app, {bool force = false}) async {
  if (!_expireStaleJobs(app, force: force)) return;
  await _finishCardWork(app, _claimOutstandingHolds(app));
}

/// The sweep as requests trigger it. Stale jobs are cancelled on the spot,
/// without a pause in which the caller's rights could change, and saved
/// with the request by `autoFlush`. The card work then runs on its own, so
/// no request waits for the payment service.
void sweepInBackground(App app) {
  if (!_expireStaleJobs(app, force: false)) return;
  final jobIds = _claimOutstandingHolds(app);
  if (jobIds.isEmpty) return;
  unawaited(() async {
    await _finishCardWork(app, jobIds);
    try {
      await app.store.flush();
    } on StorageException {
      // Logged by the store; what could not be saved goes out with the
      // next flush or is redone by the next sweep.
    } on Object catch (e, stack) {
      // Nobody awaits this future: an error must not escape it.
      app.log('sweep: failed, will retry: $e\n$stack');
    }
  }());
}

/// The synchronous part of the sweep. Returns false when no sweep is due.
bool _expireStaleJobs(App app, {required bool force}) {
  final now = app.now();
  final last = app.lastSweepAt;
  if (!force && last != null && now.difference(last) < _sweepInterval) {
    return false;
  }
  final settings = app.store.settings;
  if (settings == null) return false;
  app.lastSweepAt = now;
  try {
    final cutoff = isoTime(
      now.subtract(Duration(hours: settings['openJobExpiryHours'] as int)),
    );
    final expired = app.store.tx((tx) {
      final stale = tx.where(
        Collections.jobs,
        (j) =>
            j['status'] == JobStatus.open &&
            (j['requestedAt'] as String).compareTo(cutoff) < 0,
      );
      for (final job in stale) {
        tx.patch(Collections.jobs, job['id'] as String, {
          'status': JobStatus.cancelled,
          'cancelledAt': isoTime(now),
          'cancelledBy': 'system',
        });
      }
      return stale.length;
    });
    if (expired > 0) {
      app.log('sweep: cancelled $expired open job(s) nobody accepted in time');
    }
  } on Object catch (e, stack) {
    app.log('sweep: failed, will retry: $e\n$stack');
  }
  return true;
}

/// Takes charge (through [App.busyJobs]) of every finished job whose hold
/// nobody else is settling; returns their ids for [_finishCardWork].
List<String> _claimOutstandingHolds(App app) => [
  for (final job in app.store.where(Collections.jobs, _holdOutstanding))
    if (app.busyJobs.add(job['id'] as String)) job['id'] as String,
];

/// Captures or releases the holds of [jobIds] and gives the jobs back.
Future<void> _finishCardWork(App app, List<String> jobIds) async {
  if (jobIds.isEmpty) return;
  try {
    await app.store.flush();
    for (final id in jobIds) {
      await _settleOrRelease(app, id);
    }
  } on Object catch (e, stack) {
    app.log('sweep: failed, will retry: $e\n$stack');
  } finally {
    app.busyJobs.removeAll(jobIds);
  }
}

/// What an unclaimed job looks like again.
const _reopened = {'status': JobStatus.open, 'crewId': null, 'claimedAt': null};

Map<String, dynamic> _payment(Doc job) =>
    job['payment'] as Map<String, dynamic>;

/// The job [id] if the caller may see it, else 404: admins any job,
/// customers their own, crew the open ones and the ones they accepted.
Doc _visible(DocReader db, AuthCtx ctx, String id) {
  final job = db.get(Collections.jobs, id);
  final allowed =
      job != null &&
      switch (ctx.role) {
        Role.admin => true,
        Role.customer => job['customerId'] == ctx.customerId,
        _ => job['status'] == JobStatus.open || job['crewId'] == ctx.crewId,
      };
  return allowed ? job : throw ApiError.notFound('Job');
}

/// Throws unless a plough can be requested for [property] right now.
void _requireRequestable(DocReader db, Doc property) {
  if (property['status'] != PropertyStatus.active) {
    throw ApiError.invalidState(
      'This property needs an accepted quote before a plough can be requested.',
    );
  }
  final unfinished = db.firstWhere(
    Collections.jobs,
    (j) =>
        j['propertyId'] == property['id'] &&
        JobStatus.unfinished.contains(j['status']),
  );
  if (unfinished != null) throw ApiError.jobActive(unfinished['id'] as String);
}

/// The latest thing that happened to [job], as an ISO timestamp.
String _lastActivity(Doc job) => [
  for (final field in const [
    'requestedAt',
    'claimedAt',
    'startedAt',
    'completedAt',
    'cancelledAt',
  ])
    job[field] as String? ?? '',
].reduce((a, b) => a.compareTo(b) >= 0 ? a : b);

ApiError _holdError(App app, HoldResult hold, String jobId) {
  switch (hold.outcome) {
    case PaymentOutcome.declined:
      return ApiError.cardDeclined(hold.message);
    case PaymentOutcome.authRequired:
      return ApiError.cardAuthRequired();
    case PaymentOutcome.ok || PaymentOutcome.unavailable:
      app.log('payments: placing a hold failed: ${hold.message}');
      if (hold.inDoubt) {
        // Without its id the hold cannot be released; it lapses unused.
        app.log(
          'payments: no answer either time; a hold with metadata jobId '
          '$jobId may exist',
        );
      }
      return ApiError.paymentUnavailable();
  }
}

/// A finished job whose card hold has been neither captured nor released.
bool _holdOutstanding(Doc job) {
  final payment = _payment(job);
  return (job['status'] == JobStatus.done ||
          job['status'] == JobStatus.cancelled) &&
      payment['mode'] == PaymentMode.stripe &&
      payment['status'] == PaymentStatus.authorized;
}

/// Captures the hold of a job that was just completed, or releases the hold
/// of one that was just cancelled.
///
/// Call it right after the transaction that finished the job, without an
/// `await` in between. The job's new status is saved first (and a failed
/// save surfaces as 503 before any money moves); the card result is
/// recorded afterwards and never undoes the status.
Future<void> _finishPayment(App app, String jobId) async {
  final job = app.store.get(Collections.jobs, jobId);
  if (job == null || !_holdOutstanding(job) || !app.busyJobs.add(jobId)) {
    return;
  }
  try {
    await app.store.flush();
    await _settleOrRelease(app, jobId);
  } finally {
    app.busyJobs.remove(jobId);
  }
}

Future<void> _settleOrRelease(App app, String jobId) =>
    app.store.require(Collections.jobs, jobId)['status'] == JobStatus.done
    ? _settle(app, jobId)
    : _release(app, jobId);

/// Collects the money for done job [jobId] and records `captured` or
/// `failed`. The caller must hold the job in [App.busyJobs].
Future<void> _settle(App app, String jobId) async {
  final store = app.store;
  final job = store.require(Collections.jobs, jobId);
  final payment = _payment(job);
  final gateway = app.payments;
  CaptureResult? result;
  var chargedCard = payment['paymentMethodId'] as String?;
  // Every call to the payment service gets an attempt number of its own,
  // which names its idempotency key.
  final firstAttempt = payment['attempts'] as int? ?? 0;
  var attempt = firstAttempt;

  if (gateway != null) {
    final intentId = payment['paymentIntentId'] as String?;
    if (intentId != null) {
      result = await gateway.capture(
        jobId: jobId,
        paymentIntentId: intentId,
        attempt: attempt++,
      );
    }
    // The held card was refused. If the customer has saved a different card
    // since, charge that one. Not after an outage: the first charge may
    // have gone through.
    final refused =
        result == null ||
        result.outcome == PaymentOutcome.declined ||
        result.outcome == PaymentOutcome.authRequired;
    final customer = store.get(
      Collections.customers,
      job['customerId'] as String,
    );
    final stripeCustomerId = customer?['stripeCustomerId'] as String?;
    final currentCard = customer?['stripePaymentMethodId'] as String?;
    if (refused &&
        stripeCustomerId != null &&
        currentCard != null &&
        currentCard != chargedCard) {
      result = await gateway.chargeNow(
        jobId: jobId,
        stripeCustomerId: stripeCustomerId,
        paymentMethodId: currentCard,
        amountDollars: job['total'] as int,
        attempt: attempt++,
      );
      chargedCard = currentCard;
    }
  }

  final outcome = result;
  // The numbers are used up only by a definite answer. While the outcome is
  // in doubt the next try repeats this one call for call, so the payment
  // service answers what it answered the first time instead of charging
  // again under a new key.
  final attempts = outcome != null && outcome.inDoubt ? firstAttempt : attempt;
  final String? error;
  if (gateway == null) {
    error =
        'Card payments are not enabled on this server. Collect the payment '
        'and mark the job as paid.';
  } else if (outcome == null) {
    error = 'There is no card on file to charge.';
  } else {
    error = switch (outcome.outcome) {
      PaymentOutcome.ok => null,
      PaymentOutcome.declined => outcome.message ?? 'The card was declined.',
      PaymentOutcome.authRequired =>
        'The card needs extra authentication. Ask the customer to save '
            'their card again.',
      PaymentOutcome.unavailable =>
        'The payment service was unavailable. Retry the payment.',
    };
    if (outcome.outcome == PaymentOutcome.unavailable) {
      app.log('payments: charging job $jobId failed: ${outcome.message}');
    }
  }
  store.tx(
    (tx) => tx.update(Collections.jobs, jobId, (draft) {
      final p = _payment(draft)..['attempts'] = attempts;
      if (error == null) {
        p
          ..['status'] = PaymentStatus.captured
          ..['error'] = null
          ..['capturedAt'] = isoTime(app.now())
          ..['paymentIntentId'] = outcome?.paymentIntentId
          ..['paymentMethodId'] = chargedCard;
      } else {
        p
          ..['status'] = PaymentStatus.failed
          ..['error'] = error;
      }
    }),
  );
}

/// Releases the hold of cancelled job [jobId] and records `released`; when
/// Stripe cannot be reached the hold stays `authorized` for the next sweep.
/// The caller must hold the job in [App.busyJobs].
Future<void> _release(App app, String jobId) async {
  final payment = _payment(app.store.require(Collections.jobs, jobId));
  final intentId = payment['paymentIntentId'] as String?;
  final gateway = app.payments;
  final expiresAt = parseTime(payment['holdExpiresAt']);
  final gone =
      expiresAt != null && app.now().isAfter(expiresAt.add(_holdGoneAfter));
  String? error;
  if (gateway != null && intentId != null && !gone) {
    try {
      await gateway.cancel(intentId);
    } on PaymentException catch (e) {
      app.log(
        'payments: releasing the hold of job $jobId failed: ${e.message}',
      );
      error =
          'The card hold could not be released yet. It will be retried '
          'automatically.';
    }
  }
  app.store.tx(
    (tx) => tx.update(Collections.jobs, jobId, (draft) {
      final p = _payment(draft);
      if (error == null) p['status'] = PaymentStatus.released;
      p['error'] = error;
    }),
  );
}

/// Releases a hold that no job needs; a failure is only logged, because the
/// card network drops an unused hold by itself within days.
Future<void> _cancelQuietly(App app, String intentId, String jobId) async {
  try {
    await app.payments?.cancel(intentId);
  } on PaymentException catch (e) {
    app.log('payments: releasing a hold of job $jobId failed: ${e.message}');
  }
}

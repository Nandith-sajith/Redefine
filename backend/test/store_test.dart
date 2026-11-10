import 'dart:async';

import 'package:redefine_api/src/auth/sessions.dart';
import 'package:redefine_api/src/auth/tokens.dart';
import 'package:redefine_api/src/data/persistence.dart';
import 'package:redefine_api/src/data/store.dart';
import 'package:redefine_api/src/errors.dart';
import 'package:test/test.dart';

const _jobs = Collections.jobs;

Doc _job(String id, {String status = 'open', String? crewId, int total = 45}) =>
    {
      'id': id,
      'propertyId': 'prop_maple',
      'status': status,
      'crewId': crewId,
      'total': total,
      'payment': {'mode': 'manual', 'status': 'none', 'error': null},
    };

TypeMatcher<ApiError> _apiError(String code) =>
    isA<ApiError>().having((e) => e.code, 'code', code);

void main() {
  late MemoryPersistence persistence;
  late Store store;
  late List<String> logs;

  Future<Store> open({int flushRetries = 3}) => Store.open(
    persistence,
    flushRetries: flushRetries,
    retryDelay: Duration.zero,
    log: logs.add,
  );

  setUp(() async {
    persistence = MemoryPersistence();
    logs = [];
    store = await open();
  });

  group('reads', () {
    setUp(() {
      store.tx((tx) {
        tx.put(_jobs, _job('job_1'));
        tx.put(_jobs, _job('job_2', status: 'done', total: 65));
        tx.put(_jobs, _job('job_3', status: 'done'));
      });
    });

    test('get / require', () {
      expect(store.get(_jobs, 'job_1')!['status'], 'open');
      expect(store.get(_jobs, 'nope'), isNull);
      expect(store.require(_jobs, 'job_2')['total'], 65);
      expect(
        () => store.require(_jobs, 'nope', what: 'Job'),
        throwsA(
          _apiError('not_found')
              .having((e) => e.status, 'status', 404)
              .having((e) => e.message, 'message', 'Job not found.'),
        ),
      );
    });

    test('all / where / firstWhere / any / count', () {
      expect(store.all(_jobs).map((j) => j['id']), {'job_1', 'job_2', 'job_3'});
      expect(
        store.where(_jobs, (j) => j['status'] == 'done').map((j) => j['id']),
        unorderedEquals(['job_2', 'job_3']),
      );
      expect(store.firstWhere(_jobs, (j) => j['total'] == 65)!['id'], 'job_2');
      expect(store.firstWhere(_jobs, (j) => j['total'] == 1), isNull);
      expect(store.any(_jobs, (j) => j['status'] == 'open'), isTrue);
      expect(store.any(_jobs, (j) => j['status'] == 'cancelled'), isFalse);
      expect(store.count(_jobs), 3);
      expect(store.count(_jobs, (j) => j['status'] == 'done'), 2);
    });

    test('lists are fresh copies, documents are deeply unmodifiable', () {
      store.all(_jobs).clear();
      expect(store.count(_jobs), 3);

      final job = store.get(_jobs, 'job_1')!;
      expect(() => job['status'] = 'done', throwsUnsupportedError);
      expect(
        () => (job['payment'] as Map)['status'] = 'paid',
        throwsUnsupportedError,
      );
      expect(job['payment'], isA<Map<String, dynamic>>());
    });

    test('an unknown collection is a programming error', () {
      expect(() => store.get('jobz', 'job_1'), throwsArgumentError);
      expect(() => store.all('jobz'), throwsArgumentError);
      expect(
        () => store.tx((tx) => tx.put('jobz', {'id': 'x'})),
        throwsArgumentError,
      );
    });

    test('userByEmail ignores case and surrounding space', () {
      store.tx((tx) {
        tx.put(Collections.users, {
          'id': 'user_lia',
          'email': 'lia@redefine.co',
        });
      });
      expect(store.userByEmail('  Lia@Redefine.CO ')!['id'], 'user_lia');
      expect(store.userByEmail('nobody@redefine.co'), isNull);
    });

    test('settings is settings/main', () {
      expect(store.settings, isNull);
      store.tx((tx) {
        tx.put(Collections.settings, {'id': 'main', 'shovelPrice': 20});
      });
      expect(store.settings!['shovelPrice'], 20);
    });
  });

  group('tx', () {
    test('returns the body result and applies every write together', () {
      final result = store.tx((tx) {
        tx.put(_jobs, _job('job_1'));
        tx.put(Collections.payouts, {'id': 'payout_1', 'amount': 25});
        return 'done';
      });
      expect(result, 'done');
      expect(store.get(_jobs, 'job_1'), isNotNull);
      expect(store.get(Collections.payouts, 'payout_1')!['amount'], 25);
    });

    test(
      'reads inside see its own writes; outside sees nothing until the end',
      () {
        store.tx((tx) => tx.put(_jobs, _job('job_1')));
        store.tx((tx) {
          tx.put(_jobs, _job('job_2'));
          tx.patch(_jobs, 'job_1', {'status': 'claimed'});
          tx.delete(_jobs, 'job_2');
          tx.put(_jobs, _job('job_3', status: 'done'));

          expect(tx.get(_jobs, 'job_1')!['status'], 'claimed');
          expect(tx.get(_jobs, 'job_2'), isNull);
          expect(tx.all(_jobs).map((j) => j['id']), {'job_1', 'job_3'});
          expect(
            tx.where(_jobs, (j) => j['status'] == 'claimed'),
            hasLength(1),
          );
          expect(tx.count(_jobs), 2);

          expect(store.get(_jobs, 'job_1')!['status'], 'open');
          expect(store.count(_jobs), 1);
        });
        expect(store.get(_jobs, 'job_1')!['status'], 'claimed');
        expect(store.all(_jobs).map((j) => j['id']), {'job_1', 'job_3'});
      },
    );

    test('a throwing body changes nothing and is not dirty', () async {
      store.tx((tx) => tx.put(_jobs, _job('job_1')));
      await store.flush();

      expect(
        () => store.tx((tx) {
          tx.patch(_jobs, 'job_1', {'status': 'claimed', 'crewId': 'crew_a'});
          tx.put(_jobs, _job('job_2'));
          tx.delete(_jobs, 'job_1');
          throw ApiError.alreadyClaimed();
        }),
        throwsA(_apiError('already_claimed')),
      );

      expect(store.get(_jobs, 'job_1')!['status'], 'open');
      expect(store.get(_jobs, 'job_2'), isNull);
      expect(store.isDirty, isFalse);
    });

    test('check-then-write is atomic: only the first claim wins', () async {
      store.tx((tx) => tx.put(_jobs, _job('job_1')));

      Future<String> claim(String crewId) async {
        await Future<void>.delayed(Duration.zero);
        return store.tx((tx) {
          final job = tx.require(_jobs, 'job_1');
          if (job['status'] != 'open') throw ApiError.alreadyClaimed();
          tx.patch(_jobs, 'job_1', {'status': 'claimed', 'crewId': crewId});
          return crewId;
        });
      }

      final results = await Future.wait([
        for (final crew in ['crew_marcus', 'crew_jordan'])
          claim(crew).then<Object>((v) => v, onError: (Object e) => e),
      ]);

      expect(results.whereType<String>(), ['crew_marcus']);
      expect(results.whereType<ApiError>().single.code, 'already_claimed');
      expect(store.get(_jobs, 'job_1')!['crewId'], 'crew_marcus');
    });

    test('put stores a frozen copy and returns it', () {
      final draft = _job('job_1');
      final stored = store.tx((tx) => tx.put(_jobs, draft));

      draft['status'] = 'tampered';
      (draft['payment'] as Map)['status'] = 'tampered';
      expect(stored['status'], 'open');
      expect(store.get(_jobs, 'job_1'), same(stored));
      expect((stored['payment'] as Map)['status'], 'none');
      expect(() => stored['status'] = 'x', throwsUnsupportedError);
    });

    test('update hands out a mutable deep copy', () {
      store.tx((tx) => tx.put(_jobs, _job('job_1')));
      final before = store.get(_jobs, 'job_1')!;

      final after = store.tx(
        (tx) => tx.update(_jobs, 'job_1', (job) {
          job['status'] = 'done';
          (job['payment'] as Map)['status'] = 'due';
        }),
      );

      expect(after['status'], 'done');
      expect((after['payment'] as Map)['status'], 'due');
      expect(before['status'], 'open');
      expect((before['payment'] as Map)['status'], 'none');
      expect(store.get(_jobs, 'job_1'), same(after));
    });

    test('update and patch on a missing document are 404', () {
      expect(
        () => store.tx((tx) => tx.update(_jobs, 'nope', (_) {}, what: 'Job')),
        throwsA(_apiError('not_found')),
      );
      expect(
        () => store.tx((tx) => tx.patch(_jobs, 'nope', {'status': 'done'})),
        throwsA(_apiError('not_found')),
      );
    });

    test('update refuses to change the id', () {
      store.tx((tx) => tx.put(_jobs, _job('job_1')));
      expect(
        () => store.tx((tx) => tx.update(_jobs, 'job_1', (j) => j['id'] = 'x')),
        throwsStateError,
      );
      expect(store.get(_jobs, 'job_1'), isNotNull);
      expect(store.get(_jobs, 'x'), isNull);
    });

    test('insert refuses to overwrite', () {
      store.tx((tx) => tx.insert(_jobs, _job('job_1')));
      expect(
        () => store.tx((tx) => tx.insert(_jobs, _job('job_1', total: 99))),
        throwsStateError,
      );
      expect(store.get(_jobs, 'job_1')!['total'], 45);
    });

    test('delete reports whether the document existed', () {
      store.tx((tx) => tx.put(_jobs, _job('job_1')));
      expect(store.tx((tx) => tx.delete(_jobs, 'job_1')), isTrue);
      expect(store.tx((tx) => tx.delete(_jobs, 'job_1')), isFalse);
      expect(store.get(_jobs, 'job_1'), isNull);
    });

    test('put validates the id and the values', () {
      void put(Doc doc) => store.tx((tx) => tx.put(_jobs, doc));
      expect(() => put({'status': 'open'}), throwsArgumentError);
      expect(() => put({'id': ''}), throwsArgumentError);
      expect(() => put({'id': 'a/b'}), throwsArgumentError);
      expect(() => put({'id': 'sarah.m@gmail.com'}), throwsArgumentError);
      expect(() => put({'id': 'x' * 201}), throwsArgumentError);
      expect(() => put({'id': 7}), throwsArgumentError);
      expect(() => put({'id': 'a', 'at': DateTime(2026)}), throwsArgumentError);
      expect(() => put({'id': 'a', 'n': double.nan}), throwsArgumentError);
      expect(
        () => put({
          'id': 'a',
          'grid': [
            [1],
          ],
        }),
        throwsArgumentError,
      );
      expect(
        () => put({
          'id': 'a',
          'm': {1: 'x'},
        }),
        throwsArgumentError,
      );
      expect(store.count(_jobs), 0);
      expect(store.isDirty, isFalse);
    });

    test('an async body is rejected and rolled back', () {
      expect(
        () => store.tx((tx) async => tx.put(_jobs, _job('job_1'))),
        throwsStateError,
      );
      expect(store.get(_jobs, 'job_1'), isNull);
      expect(store.isDirty, isFalse);
    });

    test('cannot be nested or used after it ended', () {
      expect(() => store.tx((_) => store.tx((_) => 1)), throwsStateError);

      late Tx leaked;
      store.tx((tx) => leaked = tx);
      expect(() => leaked.put(_jobs, _job('job_1')), throwsStateError);
      expect(() => leaked.get(_jobs, 'job_1'), throwsStateError);
      expect(() => leaked.all(_jobs), throwsStateError);
      // A failed nested attempt must not leave the store locked.
      expect(store.tx((tx) => tx.put(_jobs, _job('job_2'))), isNotNull);
    });
  });

  group('flush', () {
    test('writes every dirty document in one atomic commit', () async {
      store.tx((tx) {
        tx.put(_jobs, _job('job_1'));
        tx.put(_jobs, _job('job_2'));
      });
      store.tx((tx) => tx.patch(_jobs, 'job_1', {'status': 'claimed'}));
      expect(store.isDirty, isTrue);
      expect(store.dirtyCount, 2);
      expect(persistence.commits, isEmpty);

      await store.flush();

      expect(store.isDirty, isFalse);
      expect(persistence.commits, hasLength(1));
      expect(persistence.commits.single.map((w) => '$w'), {
        'put jobs/job_1',
        'put jobs/job_2',
      });
      expect(persistence.doc(_jobs, 'job_1')!['status'], 'claimed');
      expect(persistence.doc(_jobs, 'job_2'), _job('job_2'));
    });

    test('persists deletes', () async {
      store.tx((tx) => tx.put(_jobs, _job('job_1')));
      await store.flush();
      store.tx((tx) => tx.delete(_jobs, 'job_1'));
      await store.flush();

      expect(persistence.commits.last.single.isDelete, isTrue);
      expect(persistence.doc(_jobs, 'job_1'), isNull);
    });

    test('with nothing dirty does not touch persistence', () async {
      await store.flush();
      expect(persistence.commitAttempts, 0);
    });

    test('retries transient failures and then succeeds', () async {
      store.tx((tx) => tx.put(_jobs, _job('job_1')));
      persistence.failNextCommits(3);

      await store.flush();

      expect(persistence.commitAttempts, 4);
      expect(store.isDirty, isFalse);
      expect(persistence.doc(_jobs, 'job_1'), isNotNull);
    });

    test(
      'gives up after the retries, keeps the docs dirty, retries later',
      () async {
        store.tx((tx) => tx.put(_jobs, _job('job_1')));
        persistence.failNextCommits(4);

        await expectLater(store.flush(), throwsA(isA<StorageException>()));

        expect(persistence.commitAttempts, 4);
        expect(store.isDirty, isTrue);
        expect(persistence.doc(_jobs, 'job_1'), isNull);
        expect(
          store.get(_jobs, 'job_1'),
          isNotNull,
          reason: 'memory stays authoritative',
        );
        expect(logs.single, contains('flush of 1 docs failed'));

        store.tx((tx) => tx.put(_jobs, _job('job_2')));
        await store.flush();

        expect(store.isDirty, isFalse);
        expect(persistence.doc(_jobs, 'job_1'), isNotNull);
        expect(persistence.doc(_jobs, 'job_2'), isNotNull);
        expect(persistence.commits, hasLength(1));
      },
    );

    test('does not retry a permanent failure', () async {
      store.tx((tx) => tx.put(_jobs, _job('job_1')));
      persistence.failNextCommits(1, transient: false);

      await expectLater(store.flush(), throwsA(isA<StorageException>()));
      expect(persistence.commitAttempts, 1);
      expect(store.isDirty, isTrue);

      await store.flush();
      expect(persistence.doc(_jobs, 'job_1'), isNotNull);
    });

    test('writes the database refuses are given up, not sent again', () async {
      store.tx((tx) => tx.put(_jobs, _job('job_saved')));
      await store.flush();
      persistence.rejectWrite = (w) => w.id == 'job_poison';
      store.tx((tx) {
        tx.put(_jobs, _job('job_poison'));
        tx.patch(_jobs, 'job_saved', {'status': 'claimed'});
      });
      final epoch = store.epoch;

      await expectLater(store.flush(), throwsA(isA<StorageException>()));
      expect(persistence.commitAttempts, 2, reason: 'not retried');
      // Memory is back to what the database holds, all of the batch undone.
      expect(store.epoch, epoch + 1);
      expect(store.isDirty, isFalse);
      expect(store.get(_jobs, 'job_poison'), isNull);
      expect(store.get(_jobs, 'job_saved')!['status'], 'open');
      expect(logs.join('\n'), contains('put jobs/job_poison'));

      await store.flush();
      expect(persistence.commitAttempts, 2, reason: 'nothing left to send');
    });

    test(
      'a document the database refuses does not block later writes',
      () async {
        persistence.rejectWrite = (w) => w.id == 'job_poison';
        store.tx((tx) => tx.put(_jobs, _job('job_poison')));
        final poisoned = store.flush();
        // Queued behind the doomed flush: lost with it, and told so.
        store.tx((tx) => tx.put(_jobs, _job('job_bystander')));
        final bystander = store.flush();

        await expectLater(poisoned, throwsA(isA<StorageException>()));
        await expectLater(bystander, throwsA(isA<StorageException>()));
        expect(store.get(_jobs, 'job_poison'), isNull);
        expect(store.get(_jobs, 'job_bystander'), isNull);
        expect(store.isDirty, isFalse);

        // Every later write goes through; before, each one failed again.
        for (final id in ['job_1', 'job_2']) {
          store.tx((tx) => tx.put(_jobs, _job(id)));
          await store.flush();
        }
        expect(persistence.docs(_jobs).keys, {'job_1', 'job_2'});
      },
    );

    test(
      'when the reload after a refusal fails, the next flush tries again',
      () async {
        persistence
          ..rejectWrite = ((w) => w.id == 'job_poison')
          ..failNextLoads(1);
        store.tx((tx) => tx.put(_jobs, _job('job_poison')));
        final epoch = store.epoch;

        await expectLater(store.flush(), throwsA(isA<StorageException>()));
        expect(store.epoch, epoch);
        expect(store.isDirty, isTrue);
        expect(store.get(_jobs, 'job_poison'), isNotNull);

        await expectLater(store.flush(), throwsA(isA<StorageException>()));
        expect(store.epoch, epoch + 1);
        expect(store.isDirty, isFalse);
        expect(store.get(_jobs, 'job_poison'), isNull);
      },
    );

    test('honours flushRetries', () async {
      store = await open(flushRetries: 0);
      store.tx((tx) => tx.put(_jobs, _job('job_1')));
      persistence.failNextCommits(1);

      await expectLater(store.flush(), throwsA(isA<StorageException>()));
      expect(persistence.commitAttempts, 1);
    });

    test(
      'a failed flush does not lose a later version of the document',
      () async {
        store.tx((tx) => tx.put(_jobs, _job('job_1')));
        persistence.failNextCommits(4);
        final failing = store.flush();
        // Changed while the failing flush is in flight.
        store.tx((tx) => tx.patch(_jobs, 'job_1', {'status': 'cancelled'}));
        await expectLater(failing, throwsA(isA<StorageException>()));

        await store.flush();
        expect(persistence.doc(_jobs, 'job_1')!['status'], 'cancelled');
        expect(store.isDirty, isFalse);
      },
    );

    test('concurrent flushes run one at a time, in order', () async {
      final gate = _GatedPersistence();
      store = await Store.open(gate, retryDelay: Duration.zero, log: logs.add);

      store.tx((tx) => tx.put(_jobs, _job('job_1')));
      final first = store.flush();
      await pumpEventQueue();
      expect(gate.inFlight, 1);

      store.tx((tx) => tx.put(_jobs, _job('job_2')));
      final second = store.flush();
      await pumpEventQueue();
      expect(gate.inFlight, 1, reason: 'the second commit must wait');
      expect(gate.started, hasLength(1));

      gate.release();
      await first;
      await pumpEventQueue();
      expect(gate.started, hasLength(2));
      gate.release();
      await second;

      expect(gate.started.map((ws) => ws.map((w) => w.id).toList()), [
        ['job_1'],
        ['job_2'],
      ]);
      expect(gate.maxInFlight, 1);
      expect(store.isDirty, isFalse);
    });

    test('a flush queued behind a failed one still saves everything', () async {
      store.tx((tx) => tx.put(_jobs, _job('job_1')));
      persistence.failNextCommits(4);
      final first = store.flush();
      store.tx((tx) => tx.put(_jobs, _job('job_2')));
      final second = store.flush();

      await expectLater(first, throwsA(isA<StorageException>()));
      await second;
      expect(persistence.docs(_jobs).keys, {'job_1', 'job_2'});
    });
  });

  group('takeover (lease lost)', () {
    test(
      'reloads from persistence, drops unflushed writes, fails the flush',
      () async {
        store.tx((tx) => tx.put(_jobs, _job('job_1')));
        await store.flush();

        // Another instance changes the database, then we try to write.
        final other = await open();
        other.tx((tx) {
          tx.patch(_jobs, 'job_1', {'status': 'claimed', 'crewId': 'crew_x'});
          tx.put(_jobs, _job('job_theirs'));
        });
        await other.flush();

        store.tx((tx) => tx.put(_jobs, _job('job_ours')));
        final epoch = store.epoch;
        persistence.loseLeaseOnNextCommit();
        await expectLater(
          store.flush(),
          throwsA(
            isA<StorageException>().having(
              (e) => e,
              'type',
              isNot(isA<LeaseLostException>()),
            ),
          ),
        );

        expect(store.epoch, epoch + 1);
        expect(store.isDirty, isFalse);
        expect(store.get(_jobs, 'job_ours'), isNull);
        expect(store.get(_jobs, 'job_theirs'), isNotNull);
        expect(store.get(_jobs, 'job_1')!['crewId'], 'crew_x');
        expect(persistence.doc(_jobs, 'job_ours'), isNull);
        expect(logs, isNotEmpty);

        // The store works normally again afterwards.
        store.tx((tx) => tx.put(_jobs, _job('job_after')));
        await store.flush();
        expect(persistence.doc(_jobs, 'job_after'), isNotNull);
      },
    );

    test('flushes queued before the reload fail too', () async {
      store.tx((tx) => tx.put(_jobs, _job('job_1')));
      persistence.loseLeaseOnNextCommit();
      final first = store.flush();
      store.tx((tx) => tx.put(_jobs, _job('job_2')));
      final second = store.flush();

      await expectLater(first, throwsA(isA<StorageException>()));
      await expectLater(second, throwsA(isA<StorageException>()));
      expect(store.get(_jobs, 'job_2'), isNull);
      expect(persistence.docs(_jobs), isEmpty);
    });

    test(
      'when the reload fails the writes stay dirty and are retried',
      () async {
        store.tx((tx) => tx.put(_jobs, _job('job_1')));
        persistence
          ..loseLeaseOnNextCommit()
          ..failNextLoads(1);
        final epoch = store.epoch;

        await expectLater(store.flush(), throwsA(isA<StorageException>()));
        expect(store.epoch, epoch);
        expect(store.isDirty, isTrue);
        expect(store.get(_jobs, 'job_1'), isNotNull);

        await store.flush();
        expect(persistence.doc(_jobs, 'job_1'), isNotNull);
      },
    );

    test('reload replaces the working copy and bumps the epoch', () async {
      store.tx((tx) => tx.put(_jobs, _job('job_unsaved')));
      final epoch = store.epoch;
      await store.reload();
      expect(store.epoch, epoch + 1);
      expect(store.get(_jobs, 'job_unsaved'), isNull);
      expect(store.isDirty, isFalse);
    });
  });

  group('reopen over the same persistence', () {
    test('a second store sees everything that was flushed', () async {
      final now = DateTime.utc(2026, 1, 5, 12);
      late String token;
      store.tx((tx) {
        tx.put(Collections.users, {
          'id': 'user_sarah',
          'email': 'sarah.m@gmail.com',
          'role': 'customer',
          'linkedId': 'cust_sarah',
        });
        tx.put(Collections.customers, {'id': 'cust_sarah', 'name': 'Sarah'});
        tx.put(Collections.properties, {
          'id': 'prop_maple',
          'customerId': 'cust_sarah',
          'price': 45,
          'crewPay': 25,
        });
        tx.put(_jobs, _job('job_1', status: 'done', crewId: 'crew_marcus'));
        tx.put(Collections.settings, {'id': 'main', 'shovelPrice': 20});
        token = createSession(
          tx,
          'user_sarah',
          now: now,
          ttl: const Duration(days: 30),
        );
      });
      await store.flush();

      final reopened = await open();

      for (final collection in Collections.all) {
        expect(
          reopened.all(collection),
          unorderedEquals(store.all(collection)),
          reason: collection,
        );
      }
      expect(reopened.get(_jobs, 'job_1')!['payment'], {
        'mode': 'manual',
        'status': 'none',
        'error': null,
      });
      expect(reopened.settings!['shovelPrice'], 20);

      // Sessions survive a restart: the same bearer token still resolves.
      expect(reopened.session(tokenHash(token))!['userId'], 'user_sarah');
      final session = resolveSession(
        reopened,
        token,
        now.add(const Duration(days: 1)),
      );
      expect(session!.user['id'], 'user_sarah');
      expect(session.sessionId, tokenHash(token));
      expect(
        resolveSession(reopened, token, now.add(const Duration(days: 31))),
        isNull,
      );
      expect(resolveSession(reopened, 'rdf_unknown', now), isNull);
    });

    test('unflushed writes are not there after a restart', () async {
      store.tx((tx) => tx.put(_jobs, _job('job_1')));
      await store.flush();
      store.tx((tx) => tx.put(_jobs, _job('job_2')));

      final reopened = await open();
      expect(reopened.all(_jobs).map((j) => j['id']), ['job_1']);
    });

    test('stores do not share document instances', () async {
      store.tx((tx) => tx.put(_jobs, _job('job_1')));
      await store.flush();
      final reopened = await open();

      store.tx((tx) => tx.patch(_jobs, 'job_1', {'status': 'cancelled'}));
      expect(reopened.get(_jobs, 'job_1')!['status'], 'open');
      expect(reopened.isDirty, isFalse);
    });

    test('loaded documents are unmodifiable too', () async {
      store.tx((tx) => tx.put(_jobs, _job('job_1')));
      await store.flush();
      final job = (await open()).get(_jobs, 'job_1')!;
      expect(() => job['status'] = 'x', throwsUnsupportedError);
      expect(
        () => (job['payment'] as Map)['status'] = 'x',
        throwsUnsupportedError,
      );
    });

    test('open fails fast when the load fails', () async {
      persistence.failNextLoads(1);
      await expectLater(open(), throwsA(isA<StorageException>()));
    });

    test('close flushes what is outstanding', () async {
      store.tx((tx) => tx.put(_jobs, _job('job_1')));
      await store.close();
      expect(persistence.doc(_jobs, 'job_1'), isNotNull);
    });
  });

  group('sessions', () {
    final now = DateTime.utc(2026, 1, 5, 12);

    test('createSession stores only the token hash, with an expiry', () {
      final token = store.tx(
        (tx) => createSession(
          tx,
          'user_lia',
          now: now,
          ttl: const Duration(days: 30),
        ),
      );

      final session = store.session(tokenHash(token))!;
      expect(session, {
        'id': tokenHash(token),
        'userId': 'user_lia',
        'createdAt': '2026-01-05T12:00:00.000Z',
        'expiresAt': '2026-02-04T12:00:00.000Z',
      });
      expect(
        store.all(Collections.sessions).toString(),
        isNot(contains(token)),
      );
      expect(store.session(token), isNull);
    });

    test('resolveSession needs an existing user', () {
      final token = store.tx(
        (tx) => createSession(
          tx,
          'user_gone',
          now: now,
          ttl: const Duration(days: 1),
        ),
      );
      expect(resolveSession(store, token, now), isNull);
    });

    test('revokeSession ends the session', () {
      late String token;
      store.tx((tx) {
        tx.put(Collections.users, {'id': 'user_lia', 'role': 'admin'});
        token = createSession(
          tx,
          'user_lia',
          now: now,
          ttl: const Duration(days: 1),
        );
      });
      expect(resolveSession(store, token, now), isNotNull);

      expect(store.tx((tx) => revokeSession(tx, tokenHash(token))), isTrue);
      expect(resolveSession(store, token, now), isNull);
      expect(store.tx((tx) => revokeSession(tx, tokenHash(token))), isFalse);
    });

    test(
      'pruneExpiredSessions removes expired and unreadable sessions',
      () async {
        late String live;
        store.tx((tx) {
          createSession(tx, 'user_a', now: now, ttl: const Duration(hours: 1));
          live = createSession(
            tx,
            'user_b',
            now: now,
            ttl: const Duration(days: 30),
          );
          tx.put(Collections.sessions, {'id': 'broken', 'userId': 'user_c'});
        });
        await store.flush();

        final removed = store.pruneExpiredSessions(
          now.add(const Duration(days: 1)),
        );

        expect(removed, 2);
        expect(store.all(Collections.sessions).single['id'], tokenHash(live));
        await store.flush();
        expect(persistence.docs(Collections.sessions).keys, [tokenHash(live)]);
      },
    );
  });

  group('MemoryPersistence', () {
    test('commit is all-or-nothing', () async {
      await expectLater(
        persistence.commit([
          const DocWrite.put(_jobs, 'job_1', {'id': 'job_1'}),
          const DocWrite.put('no_such_collection', 'x', {'id': 'x'}),
        ]),
        throwsArgumentError,
      );
      expect(persistence.doc(_jobs, 'job_1'), isNull);
      expect(persistence.commits, isEmpty);
    });

    test('hands out copies, never its own maps', () async {
      await persistence.commit([DocWrite.put(_jobs, 'job_1', _job('job_1'))]);
      persistence.doc(_jobs, 'job_1')!['status'] = 'tampered';
      (await persistence.load())[_jobs]!['job_1']!['status'] = 'tampered';
      expect(persistence.doc(_jobs, 'job_1')!['status'], 'open');
      expect(persistence.kind, 'memory');
    });
  });

  group('freezeDoc / copyDoc', () {
    test('copyDoc is deep and mutable', () {
      final frozen = freezeDoc(_job('job_1'));
      final copy = copyDoc(frozen);
      (copy['payment'] as Map)['status'] = 'paid';
      copy['status'] = 'done';
      expect((frozen['payment'] as Map)['status'], 'none');
      expect(copy, isNot(frozen));
    });

    test('freezeDoc keeps values and JSON types', () {
      final frozen = freezeDoc({
        'id': 'a',
        'n': 1,
        'd': 1.5,
        'b': true,
        'z': null,
        'l': [
          1,
          {'k': 'v'},
        ],
        'm': <String, dynamic>{},
      });
      expect(frozen, {
        'id': 'a',
        'n': 1,
        'd': 1.5,
        'b': true,
        'z': null,
        'l': [
          1,
          {'k': 'v'},
        ],
        'm': <String, dynamic>{},
      });
      expect(() => (frozen['l'] as List).add(2), throwsUnsupportedError);
      expect(
        () => ((frozen['l'] as List)[1] as Map)['k'] = 'x',
        throwsUnsupportedError,
      );
    });

    test('isWellFormed accepts pairs and rejects lone surrogates', () {
      const high = '\u{d83d}';
      const low = '\u{de00}';
      for (final text in ['', 'Zo\u00eb', '\u2603 snow', 'a$high${low}b']) {
        expect(isWellFormed(text), isTrue, reason: text);
      }
      for (final text in [high, low, 'a$high', '${high}b', '$low$high']) {
        expect(isWellFormed(text), isFalse, reason: '${text.codeUnits}');
      }
    });

    test('text that is not valid Unicode never enters the store', () {
      const lone = '\u{d83d}';
      for (final doc in [
        {'id': 'a', 'name': lone},
        {
          'id': 'a',
          'list': [
            {'note': 'x$lone'},
          ],
        },
        {'id': 'a', lone: 1},
      ]) {
        expect(() => freezeDoc(doc), throwsArgumentError);
        expect(() => store.tx((tx) => tx.put(_jobs, doc)), throwsArgumentError);
      }
      expect(store.isDirty, isFalse);
      expect(store.count(_jobs), 0);
    });
  });
}

/// Holds every commit until [release] is called, to observe flush ordering.
class _GatedPersistence implements Persistence {
  final List<List<DocWrite>> started = [];
  final List<Completer<void>> _gates = [];
  int inFlight = 0;
  int maxInFlight = 0;

  void release() => _gates.removeAt(0).complete();

  @override
  String get kind => 'memory';

  @override
  Future<Map<String, Map<String, Doc>>> load() async => {};

  @override
  Future<void> commit(List<DocWrite> writes) async {
    started.add(writes);
    inFlight++;
    if (inFlight > maxInFlight) maxInFlight = inFlight;
    final gate = Completer<void>();
    _gates.add(gate);
    await gate.future;
    inFlight--;
  }

  @override
  Future<void> close() async {}
}

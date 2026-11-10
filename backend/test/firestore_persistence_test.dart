import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:redefine_api/src/data/firestore_codec.dart';
import 'package:redefine_api/src/data/firestore_persistence.dart';
import 'package:redefine_api/src/data/persistence.dart';
import 'package:redefine_api/src/data/store.dart';
import 'package:test/test.dart';

const _root = 'projects/demo-project/databases/(default)/documents';

/// A minimal Firestore REST double: paginated lists, atomic commits with
/// `currentDocument.updateTime` preconditions, and scripted failures.
class _FakeFirestore {
  final Map<String, Map<String, dynamic>> fieldsByName = {};
  final Map<String, String> updateTimes = {};
  final List<http.Request> requests = [];
  final List<http.Response Function()> scripted = [];
  bool offline = false;

  /// When set, every list request fails with this HTTP status.
  int? listStatus;
  int _clock = 0;

  late final http.Client client = MockClient((request) async {
    requests.add(request);
    if (offline) throw http.ClientException('connection refused');
    if (scripted.isNotEmpty) return scripted.removeAt(0)();
    if (request.method == 'POST' && request.url.path.endsWith(':commit')) {
      return _commit(jsonDecode(request.body) as Map<String, dynamic>);
    }
    if (request.method == 'GET') {
      final status = listStatus;
      return status == null
          ? _list(request.url)
          : http.Response('upstream connect error', status);
    }
    return _error(404, 'NOT_FOUND', 'no such method');
  });

  List<http.Request> get commits =>
      requests.where((r) => r.url.path.endsWith(':commit')).toList();

  List<dynamic> writesOf(http.Request commit) =>
      (jsonDecode(commit.body) as Map<String, dynamic>)['writes'] as List;

  void seed(String collection, String id, Map<String, dynamic> doc) {
    final name = '$_root/$collection/$id';
    fieldsByName[name] = encodeFields(doc);
    updateTimes[name] = _tick();
  }

  /// Another server instance rewrites the lease.
  void takeOver() => updateTimes['$_root/meta/lease'] = _tick();

  void failNext(int status, String code, [String message = 'scripted']) =>
      scripted.add(() => _error(status, code, message));

  String _tick() => 't${++_clock}';

  http.Response _error(int status, String code, String message) =>
      http.Response(
        jsonEncode({
          'error': {'code': status, 'message': message, 'status': code},
        }),
        status,
      );

  http.Response _commit(Map<String, dynamic> body) {
    final writes = (body['writes'] as List).cast<Map<String, dynamic>>();
    for (final w in writes) {
      final expected = (w['currentDocument'] as Map?)?['updateTime'];
      if (expected == null) continue;
      final name = (w['update'] as Map)['name'] as String;
      if (updateTimes[name] != expected) {
        return _error(400, 'FAILED_PRECONDITION', 'the stored version changed');
      }
    }
    final results = <Map<String, dynamic>>[];
    for (final w in writes) {
      if (w['delete'] case final String name) {
        fieldsByName.remove(name);
        updateTimes.remove(name);
        results.add({});
      } else {
        final update = w['update'] as Map<String, dynamic>;
        final name = update['name'] as String;
        fieldsByName[name] = update['fields'] as Map<String, dynamic>;
        results.add({'updateTime': updateTimes[name] = _tick()});
      }
    }
    return http.Response(
      jsonEncode({'writeResults': results, 'commitTime': 't$_clock'}),
      200,
    );
  }

  http.Response _list(Uri url) {
    final prefix = '${url.path.substring('/v1/'.length)}/';
    final names = fieldsByName.keys.where((n) => n.startsWith(prefix)).toList()
      ..sort();
    final pageSize = int.parse(url.queryParameters['pageSize']!);
    final start = int.parse(url.queryParameters['pageToken'] ?? '0');
    final end = start + pageSize < names.length
        ? start + pageSize
        : names.length;
    return http.Response(
      jsonEncode({
        if (names.isNotEmpty)
          'documents': [
            for (final name in names.sublist(start, end))
              {
                'name': name,
                'fields': fieldsByName[name],
                'createTime': 't0',
                'updateTime': updateTimes[name],
              },
          ],
        if (end < names.length) 'nextPageToken': '$end',
      }),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
  }
}

void main() {
  late _FakeFirestore firestore;

  FirestorePersistence open({int pageSize = 300, int maxWrites = 400}) =>
      FirestorePersistence(
        client: firestore.client,
        project: 'demo-project',
        owner: 'inst_test',
        pageSize: pageSize,
        maxWritesPerCommit: maxWrites,
      );

  setUp(() => firestore = _FakeFirestore());

  group('load', () {
    test('takes the lease first, then lists every collection', () async {
      firestore.seed('users', 'user_lia', {'id': 'user_lia', 'name': 'Lia'});
      final data = await open().load();

      final first = firestore.requests.first;
      expect(first.method, 'POST');
      expect(
        first.url.toString(),
        'https://firestore.googleapis.com/v1/$_root:commit',
      );
      final lease = firestore.writesOf(first).single as Map<String, dynamic>;
      expect(lease.containsKey('currentDocument'), isFalse);
      expect((lease['update'] as Map)['name'], '$_root/meta/lease');
      expect(decodeFields((lease['update'] as Map)['fields']), {
        'owner': 'inst_test',
        'seq': 1,
      });

      final listed = [
        for (final r in firestore.requests.skip(1)) r.url.pathSegments.last,
      ];
      expect(listed, Collections.all);
      expect(
        firestore.requests.skip(1).every((r) => r.method == 'GET'),
        isTrue,
      );
      expect(
        firestore.requests[1].url.toString(),
        'https://firestore.googleapis.com/v1/$_root/users?pageSize=300',
      );

      expect(data.keys, Collections.all);
      expect(data['users'], {
        'user_lia': {'id': 'user_lia', 'name': 'Lia'},
      });
      expect(data['jobs'], isEmpty);
    });

    test('follows nextPageToken until the collection is complete', () async {
      for (var i = 0; i < 7; i++) {
        firestore.seed('jobs', 'job_$i', {'id': 'job_$i', 'total': 40 + i});
      }
      final data = await open(pageSize: 3).load();

      expect(data['jobs']!.keys, {for (var i = 0; i < 7; i++) 'job_$i'});
      expect(data['jobs']!['job_6'], {'id': 'job_6', 'total': 46});
      final pages = firestore.requests
          .where((r) => r.method == 'GET' && r.url.path.endsWith('/jobs'))
          .map((r) => r.url.queryParameters)
          .toList();
      expect(pages, [
        {'pageSize': '3'},
        {'pageSize': '3', 'pageToken': '3'},
        {'pageSize': '3', 'pageToken': '6'},
      ]);
    });

    test('takes the document id from its name', () async {
      firestore.seed('settings', 'main', {'shovelPrice': 20});
      final data = await open().load();
      expect(data['settings']!['main'], {'shovelPrice': 20, 'id': 'main'});
    });

    test('addresses a named database', () async {
      final persistence = FirestorePersistence(
        client: firestore.client,
        project: 'demo-project',
        database: 'redefine',
      );
      await persistence.load();
      expect(
        firestore.requests.first.url.path,
        '/v1/projects/demo-project/databases/redefine/documents:commit',
      );
      expect(
        firestore.requests[1].url.path,
        '/v1/projects/demo-project/databases/redefine/documents/users',
      );
    });

    test('fails with a non-transient error when access is denied', () async {
      firestore.failNext(403, 'PERMISSION_DENIED', 'Missing permissions.');
      await expectLater(
        open().load(),
        throwsA(
          isA<StorageException>()
              .having((e) => e.transient, 'transient', isFalse)
              .having(
                (e) => e.message,
                'message',
                contains('PERMISSION_DENIED'),
              )
              .having((e) => e, 'type', isNot(isA<LeaseLostException>())),
        ),
      );
    });

    test('a failed listing leaves the lease unusable', () async {
      final persistence = open();
      firestore.listStatus = 503;
      await expectLater(
        persistence.load(),
        throwsA(
          isA<StorageException>().having(
            (e) => e.transient,
            'transient',
            isTrue,
          ),
        ),
      );
      // The lease write itself went through, but without a complete snapshot
      // this instance must not write.
      expect(firestore.commits, hasLength(1));
      final sent = firestore.requests.length;
      await expectLater(
        persistence.commit([
          const DocWrite.put('jobs', 'job_1', {'id': 'job_1'}),
        ]),
        throwsA(isA<LeaseLostException>()),
      );
      expect(firestore.requests, hasLength(sent));

      firestore.listStatus = null;
      await persistence.load();
      await persistence.commit([
        const DocWrite.put('jobs', 'job_1', {'id': 'job_1'}),
      ]);
      expect(firestore.fieldsByName.containsKey('$_root/jobs/job_1'), isTrue);
    });
  });

  group('commit', () {
    test('sends puts and deletes atomically behind the lease', () async {
      final persistence = open();
      await persistence.load();
      final leaseTime = firestore.updateTimes['$_root/meta/lease'];
      firestore.seed('sessions', 'abc', {'id': 'abc'});

      await persistence.commit([
        const DocWrite.put('jobs', 'job_1', {
          'id': 'job_1',
          'total': 65,
          'shovel': true,
          'crewId': null,
          'payment': {'mode': 'manual', 'status': 'none'},
        }),
        const DocWrite.delete('sessions', 'abc'),
      ]);

      final commit = firestore.commits.last;
      expect(commit.headers['content-type'], startsWith('application/json'));
      expect(firestore.writesOf(commit), [
        {
          'update': {
            'name': '$_root/meta/lease',
            'fields': {
              'owner': {'stringValue': 'inst_test'},
              'seq': {'integerValue': '2'},
            },
          },
          'currentDocument': {'updateTime': leaseTime},
        },
        {
          'update': {
            'name': '$_root/jobs/job_1',
            'fields': {
              'id': {'stringValue': 'job_1'},
              'total': {'integerValue': '65'},
              'shovel': {'booleanValue': true},
              'crewId': {'nullValue': null},
              'payment': {
                'mapValue': {
                  'fields': {
                    'mode': {'stringValue': 'manual'},
                    'status': {'stringValue': 'none'},
                  },
                },
              },
            },
          },
        },
        {'delete': '$_root/sessions/abc'},
      ]);
      expect(
        firestore.fieldsByName.containsKey('$_root/sessions/abc'),
        isFalse,
      );
    });

    test('chains each commit on the lease time of the previous one', () async {
      final persistence = open();
      await persistence.load();
      await persistence.commit([
        const DocWrite.put('jobs', 'a', {'id': 'a'}),
      ]);
      final afterFirst = firestore.updateTimes['$_root/meta/lease'];
      await persistence.commit([
        const DocWrite.put('jobs', 'b', {'id': 'b'}),
      ]);

      final lease =
          firestore.writesOf(firestore.commits.last).first
              as Map<String, dynamic>;
      expect(lease['currentDocument'], {'updateTime': afterFirst});
      expect(firestore.updateTimes['$_root/meta/lease'], isNot(afterFirst));
    });

    test('what it commits is what a later load returns', () async {
      final doc = {
        'id': 'job_1',
        'note': '',
        'tags': <dynamic>[],
        'payment': {'error': null, 'holdExpiresAt': '2026-01-10T06:00:00.000Z'},
        'total': 65,
      };
      final writer = open();
      await writer.load();
      await writer.commit([DocWrite.put('jobs', 'job_1', doc)]);

      final data = await open().load();
      expect(data['jobs'], {'job_1': doc});
    });

    test('splits large commits, each chunk behind the lease', () async {
      final persistence = open(maxWrites: 3);
      await persistence.load();
      await persistence.commit([
        for (var i = 0; i < 5; i++) DocWrite.put('jobs', 'j$i', {'id': 'j$i'}),
      ]);

      final chunks = firestore.commits.skip(1).map(firestore.writesOf).toList();
      expect(chunks.map((c) => c.length), [3, 3, 2]);
      for (final chunk in chunks) {
        expect((chunk.first as Map)['currentDocument'], isNotNull);
      }
      expect(
        firestore.fieldsByName.keys.where((n) => n.contains('/jobs/')),
        hasLength(5),
      );
    });

    test('an empty commit sends nothing', () async {
      final persistence = open();
      await persistence.load();
      final sent = firestore.requests.length;
      await persistence.commit([]);
      expect(firestore.requests, hasLength(sent));
    });

    test('refuses to write before the first load', () async {
      await expectLater(
        open().commit([
          const DocWrite.put('jobs', 'a', {'id': 'a'}),
        ]),
        throwsA(isA<LeaseLostException>()),
      );
      expect(firestore.requests, isEmpty);
    });

    test('reports 429, 5xx and aborted commits as transient', () async {
      final persistence = open();
      await persistence.load();
      const write = [
        DocWrite.put('jobs', 'a', {'id': 'a'}),
      ];
      for (final (status, code) in [
        (429, 'RESOURCE_EXHAUSTED'),
        (503, 'UNAVAILABLE'),
        (500, 'INTERNAL'),
        (409, 'ABORTED'),
      ]) {
        firestore.failNext(status, code);
        await expectLater(
          persistence.commit(write),
          throwsA(
            isA<StorageException>()
                .having((e) => e.transient, 'transient', isTrue)
                .having((e) => e, 'type', isNot(isA<LeaseLostException>())),
          ),
          reason: code,
        );
      }
      // The lease survived the failures: the same commit now goes through.
      await persistence.commit(write);
      expect(firestore.fieldsByName.containsKey('$_root/jobs/a'), isTrue);
    });

    test('reports a rejected request as permanent', () async {
      final persistence = open();
      await persistence.load();
      firestore.failNext(400, 'INVALID_ARGUMENT', 'bad field');
      await expectLater(
        persistence.commit([
          const DocWrite.put('jobs', 'a', {'id': 'a'}),
        ]),
        throwsA(
          isA<StorageException>()
              .having((e) => e.transient, 'transient', isFalse)
              .having((e) => e.refused, 'refused', isTrue)
              .having((e) => e.message, 'message', contains('bad field')),
        ),
      );
    });

    test('a denied or failing commit is not a refusal of the writes', () async {
      final persistence = open();
      await persistence.load();
      for (final (status, code) in [
        (403, 'PERMISSION_DENIED'),
        (401, 'UNAUTHENTICATED'),
        (503, 'UNAVAILABLE'),
      ]) {
        firestore.failNext(status, code);
        await expectLater(
          persistence.commit([
            const DocWrite.put('jobs', 'a', {'id': 'a'}),
          ]),
          throwsA(
            isA<StorageException>().having(
              (e) => e.refused,
              'refused',
              isFalse,
            ),
          ),
          reason: code,
        );
      }
    });

    test('reports network failures as transient', () async {
      final persistence = open();
      await persistence.load();
      firestore.offline = true;
      await expectLater(
        persistence.commit([
          const DocWrite.put('jobs', 'a', {'id': 'a'}),
        ]),
        throwsA(
          isA<StorageException>().having(
            (e) => e.transient,
            'transient',
            isTrue,
          ),
        ),
      );
    });

    test('reports a hung request as transient after the timeout', () async {
      final persistence = FirestorePersistence(
        client: MockClient((request) async {
          if (request.method == 'GET') return http.Response('{}', 200);
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          if ((body['writes'] as List).length > 1) {
            await Completer<void>().future;
          }
          return http.Response(
            jsonEncode({
              'writeResults': [
                {'updateTime': 't1'},
              ],
            }),
            200,
          );
        }),
        project: 'demo-project',
        timeout: const Duration(milliseconds: 30),
      );
      await persistence.load();
      await expectLater(
        persistence.commit([
          const DocWrite.put('jobs', 'a', {'id': 'a'}),
        ]),
        throwsA(
          isA<StorageException>().having(
            (e) => e.transient,
            'transient',
            isTrue,
          ),
        ),
      );
    });
  });

  group('lease', () {
    const write = [
      DocWrite.put('jobs', 'a', {'id': 'a'}),
    ];

    test('a takeover by another instance fails the commit', () async {
      final persistence = open();
      await persistence.load();
      firestore.takeOver();

      await expectLater(
        persistence.commit(write),
        throwsA(isA<LeaseLostException>()),
      );
      expect(firestore.fieldsByName.containsKey('$_root/jobs/a'), isFalse);
    });

    test(
      'after losing the lease nothing is sent until the next load',
      () async {
        final persistence = open();
        await persistence.load();
        firestore.takeOver();
        await expectLater(
          persistence.commit(write),
          throwsA(isA<LeaseLostException>()),
        );

        final sent = firestore.requests.length;
        await expectLater(
          persistence.commit(write),
          throwsA(isA<LeaseLostException>()),
        );
        expect(firestore.requests, hasLength(sent));
      },
    );

    test(
      'load retakes the lease unconditionally and commits work again',
      () async {
        final persistence = open();
        await persistence.load();
        firestore.takeOver();
        await expectLater(
          persistence.commit(write),
          throwsA(isA<LeaseLostException>()),
        );

        await persistence.load();
        final retake =
            firestore.writesOf(firestore.commits.last).single
                as Map<String, dynamic>;
        expect(retake.containsKey('currentDocument'), isFalse);

        await persistence.commit(write);
        expect(firestore.fieldsByName.containsKey('$_root/jobs/a'), isTrue);
      },
    );

    test(
      'two instances: the newer one wins, the older one is fenced',
      () async {
        final older = open();
        await older.load();
        final newer = FirestorePersistence(
          client: firestore.client,
          project: 'demo-project',
          owner: 'inst_newer',
        );
        await newer.load();

        await expectLater(
          older.commit(write),
          throwsA(isA<LeaseLostException>()),
        );
        await newer.commit([
          const DocWrite.put('jobs', 'b', {'id': 'b'}),
        ]);
        expect(firestore.fieldsByName.keys.where((n) => n.contains('/jobs/')), [
          '$_root/jobs/b',
        ]);
      },
    );

    test('a deleted lease document also counts as lost', () async {
      final persistence = open();
      await persistence.load();
      firestore.failNext(404, 'NOT_FOUND', 'No document to update');
      await expectLater(
        persistence.commit(write),
        throwsA(isA<LeaseLostException>()),
      );
    });
  });

  test('a store gives up the batch Firestore refuses and carries on', () async {
    final logs = <String>[];
    final store = await Store.open(
      open(),
      retryDelay: Duration.zero,
      log: logs.add,
    );
    store.tx((tx) => tx.put('jobs', {'id': 'refused'}));
    firestore.failNext(400, 'INVALID_ARGUMENT', 'Invalid UTF-8 in a value');

    await expectLater(store.flush(), throwsA(isA<StorageException>()));
    expect(store.get('jobs', 'refused'), isNull);
    expect(store.isDirty, isFalse);
    expect(logs.join(' '), contains('put jobs/refused'));

    // The lease was taken again with the reload: later writes are saved.
    store.tx((tx) => tx.put('jobs', {'id': 'fine'}));
    await store.flush();
    expect(firestore.fieldsByName.keys.where((n) => n.contains('/jobs/')), [
      '$_root/jobs/fine',
    ]);
  });

  test('kind is firestore and close closes the client', () async {
    var closed = false;
    final persistence = FirestorePersistence(
      client: _ClosingClient(() => closed = true),
      project: 'demo-project',
    );
    expect(persistence.kind, 'firestore');
    await persistence.close();
    expect(closed, isTrue);
  });
}

class _ClosingClient extends http.BaseClient {
  final void Function() onClose;
  _ClosingClient(this.onClose);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      throw UnimplementedError();

  @override
  void close() => onClose();
}

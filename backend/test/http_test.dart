import 'dart:convert';

import 'package:redefine_api/src/auth/sessions.dart';
import 'package:redefine_api/src/data/persistence.dart';
import 'package:redefine_api/src/data/store.dart';
import 'package:redefine_api/src/errors.dart';
import 'package:redefine_api/src/http.dart';
import 'package:redefine_api/src/payments/gateway.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:test/test.dart';

Request _request(
  String method,
  String path, {
  Object? body,
  String? token,
  Map<String, String> headers = const {},
}) => Request(
  method,
  Uri.parse('http://localhost$path'),
  headers: {...headers, if (token != null) 'authorization': 'Bearer $token'},
  body: body is String || body is List<int> || body == null
      ? body
      : jsonEncode(body),
);

Future<Map<String, dynamic>> _body(Response response) async =>
    jsonDecode(await response.readAsString()) as Map<String, dynamic>;

Matcher _validation(String messagePart) => isA<ApiError>()
    .having((e) => e.status, 'status', 400)
    .having((e) => e.code, 'code', 'validation')
    .having((e) => e.message, 'message', contains(messagePart));

Matcher _badRequest() => isA<ApiError>()
    .having((e) => e.status, 'status', 400)
    .having((e) => e.code, 'code', 'bad_request');

void main() {
  group('jsonOk / jsonError', () {
    test('jsonOk encodes the body as UTF-8 JSON', () async {
      final response = jsonOk({'name': 'Été ❄'});
      expect(response.statusCode, 200);
      expect(
        response.headers['content-type'],
        'application/json; charset=utf-8',
      );
      expect(await _body(response), {'name': 'Été ❄'});
      expect(jsonCreated([1]).statusCode, 201);
      expect(await jsonOk([]).readAsString(), '[]');
    });

    test('jsonError carries status, code, message and extras', () async {
      final response = jsonError(ApiError.jobActive('job_9'));
      expect(response.statusCode, 409);
      expect(await _body(response), {
        'error': 'This property already has a plough request in progress.',
        'code': 'job_active',
        'jobId': 'job_9',
      });
    });
  });

  group('ApiError factories', () {
    test('match the contract table', () {
      final table = {
        ApiError.badRequest('x'): (400, 'bad_request'),
        ApiError.validation('x'): (400, 'validation'),
        ApiError.unauthorized(): (401, 'unauthorized'),
        ApiError.invalidCredentials(): (401, 'invalid_credentials'),
        ApiError.cardRequired(): (402, 'card_required'),
        ApiError.cardDeclined(): (402, 'card_declined'),
        ApiError.cardAuthRequired(): (402, 'card_auth_required'),
        ApiError.forbidden(): (403, 'forbidden'),
        ApiError.crewPending(): (403, 'crew_pending'),
        ApiError.crewRejected(): (403, 'crew_rejected'),
        ApiError.inviteRequired(): (403, 'invite_required'),
        ApiError.notFound(): (404, 'not_found'),
        ApiError.emailTaken(): (409, 'email_taken'),
        ApiError.jobActive('j'): (409, 'job_active'),
        ApiError.alreadyClaimed(): (409, 'already_claimed'),
        ApiError.jobStarted(): (409, 'job_started'),
        ApiError.quoteNotOpen(): (409, 'quote_not_open'),
        ApiError.invalidState('x'): (409, 'invalid_state'),
        ApiError.paymentsManual(): (409, 'payments_manual'),
        ApiError.nothingToPay(): (409, 'nothing_to_pay'),
        ApiError.rateLimited(): (429, 'rate_limited'),
        ApiError.paymentUnavailable(): (502, 'payment_unavailable'),
        ApiError.storageUnavailable(): (503, 'storage_unavailable'),
        ApiError.internal(): (500, 'internal'),
      };
      table.forEach((error, expected) {
        expect((error.status, error.code), expected);
        expect(error.message, isNotEmpty);
        expect(error.toJson()['error'], error.message);
        expect(error.toJson()['code'], error.code);
      });
    });

    test('card and payment errors accept a specific message', () {
      expect(
        ApiError.cardDeclined('Insufficient funds.').message,
        'Insufficient funds.',
      );
      expect(ApiError.cardDeclined('').message, 'The card was declined.');
      expect(ApiError.notFound('Job').message, 'Job not found.');
    });
  });

  group('readJson', () {
    test('parses a JSON object', () async {
      expect(await readJson(_request('POST', '/x', body: {'a': 1, 'b': 'é'})), {
        'a': 1,
        'b': 'é',
      });
    });

    test('treats an empty or blank body as {}', () async {
      expect(await readJson(_request('POST', '/x')), <String, dynamic>{});
      expect(
        await readJson(_request('POST', '/x', body: '  \n')),
        <String, dynamic>{},
      );
    });

    test('rejects invalid JSON, non-objects and invalid UTF-8', () async {
      for (final body in <Object>[
        '{"a":',
        'not json',
        '[1,2]',
        '"text"',
        '42',
        'null',
        [0xff, 0xfe, 0xfd],
      ]) {
        await expectLater(
          readJson(_request('POST', '/x', body: body)),
          throwsA(_badRequest()),
          reason: '$body',
        );
      }
    });

    test('rejects bodies over 64 KB, declared or streamed', () async {
      final big = jsonEncode({'note': 'x' * maxBodyBytes});
      await expectLater(
        readJson(_request('POST', '/x', body: big)),
        throwsA(_badRequest()),
      );
      final streamed = Request(
        'POST',
        Uri.parse('http://localhost/x'),
        body: Stream.fromIterable([
          for (var i = 0; i < 70; i++) List.filled(1024, 0x20),
        ]),
      );
      expect(streamed.contentLength, isNull);
      await expectLater(readJson(streamed), throwsA(_badRequest()));

      final justUnder = jsonEncode({'note': 'x' * (maxBodyBytes - 20)});
      expect(utf8.encode(justUnder).length, lessThanOrEqualTo(maxBodyBytes));
      expect(
        (await readJson(_request('POST', '/x', body: justUnder)))['note'],
        hasLength(maxBodyBytes - 20),
      );
    });
  });

  group('body validators', () {
    test('reqString trims and enforces the length range', () {
      expect(reqString({'name': '  Maple  '}, 'name', max: 60), 'Maple');
      expect(
        () => reqString({}, 'name', max: 60),
        throwsA(_validation('name')),
      );
      expect(
        () => reqString({'name': null}, 'name', max: 60),
        throwsA(_validation('name is required')),
      );
      expect(
        () => reqString({'name': '   '}, 'name', max: 60),
        throwsA(_validation('name is required')),
      );
      expect(
        () => reqString({'name': 7}, 'name', max: 60),
        throwsA(_validation('name must be text')),
      );
      expect(
        () => reqString({'name': 'x' * 61}, 'name', max: 60),
        throwsA(_validation('name must be at most 60')),
      );
      expect(reqString({'name': 'x' * 60}, 'name', max: 60), hasLength(60));
      expect(
        () => reqString({'password': 'short'}, 'password', min: 8, max: 200),
        throwsA(_validation('password must be at least 8')),
      );
    });

    test('reqString can keep surrounding whitespace', () {
      expect(
        reqString(
          {'password': ' pass word '},
          'password',
          min: 8,
          max: 200,
          trim: false,
        ),
        ' pass word ',
      );
    });

    test('optString defaults to empty and still validates', () {
      expect(optString({}, 'note', max: 500), '');
      expect(optString({'note': null}, 'note', max: 500), '');
      expect(optString({'note': '  '}, 'note', max: 500), '');
      expect(
        optString({'note': ' gate code 12 '}, 'note', max: 500),
        'gate code 12',
      );
      expect(
        () => optString({'note': 'x' * 501}, 'note', max: 500),
        throwsA(_validation('note must be at most 500')),
      );
      expect(
        () => optString({'note': 5}, 'note', max: 500),
        throwsA(_validation('note must be text')),
      );
    });

    test('reqEmail normalises and validates', () {
      expect(
        reqEmail({'email': '  Sarah.M@Gmail.com '}, 'email'),
        'sarah.m@gmail.com',
      );
      for (final bad in [
        '',
        'sarah',
        'sarah@',
        '@gmail.com',
        'a b@c.co',
        'a@b',
        'a@@b.co',
      ]) {
        expect(
          () => reqEmail({'email': bad}, 'email'),
          throwsA(_validation('email')),
          reason: bad,
        );
      }
    });

    test('reqInt accepts whole numbers in range only', () {
      expect(reqInt({'price': 45}, 'price', min: 1, max: 10000), 45);
      expect(reqInt({'price': 45.0}, 'price', min: 1, max: 10000), 45);
      expect(reqInt({'price': 1}, 'price', min: 1, max: 10000), 1);
      expect(reqInt({'price': 10000}, 'price', min: 1, max: 10000), 10000);
      for (final bad in <Object?>[
        0,
        10001,
        45.5,
        '45',
        true,
        double.infinity,
        [45],
      ]) {
        expect(
          () => reqInt({'price': bad}, 'price', min: 1, max: 10000),
          throwsA(_validation('price must be a whole number from 1 to 10000')),
          reason: '$bad',
        );
      }
      expect(
        () => reqInt({}, 'price', min: 1, max: 10000),
        throwsA(_validation('price is required')),
      );
    });

    test('optInt is null when absent', () {
      expect(optInt({}, 'shovelPrice', min: 0, max: 1000), isNull);
      expect(
        optInt({'shovelPrice': null}, 'shovelPrice', min: 0, max: 1000),
        isNull,
      );
      expect(optInt({'shovelPrice': 0}, 'shovelPrice', min: 0, max: 1000), 0);
      expect(
        () => optInt({'shovelPrice': -1}, 'shovelPrice', min: 0, max: 1000),
        throwsA(_validation('shovelPrice')),
      );
    });

    test('optBool accepts only booleans', () {
      expect(optBool({}, 'shovel'), isFalse);
      expect(optBool({}, 'shovel', fallback: true), isTrue);
      expect(optBool({'shovel': true}, 'shovel'), isTrue);
      expect(optBool({'shovel': false}, 'shovel', fallback: true), isFalse);
      expect(
        () => optBool({'shovel': 'true'}, 'shovel'),
        throwsA(_validation('shovel must be true or false')),
      );
      expect(
        () => optBool({'shovel': 1}, 'shovel'),
        throwsA(_validation('shovel')),
      );
    });

    test('reqEnum / optEnum', () {
      expect(reqEnum({'role': 'crew'}, 'role', Role.all), 'crew');
      expect(optEnum({}, 'role', Role.all), isNull);
      expect(optEnum({'role': 'admin'}, 'role', Role.all), 'admin');
      expect(
        () => reqEnum({'role': 'owner'}, 'role', Role.all),
        throwsA(_validation('role must be one of: admin, crew, customer')),
      );
      expect(
        () => reqEnum({}, 'role', Role.all),
        throwsA(_validation('role is required')),
      );
      expect(
        () => optEnum({'role': 3}, 'role', Role.all),
        throwsA(_validation('role')),
      );
    });
  });

  group('query validators', () {
    const statuses = {'open', 'claimed', 'inProgress', 'done', 'cancelled'};

    test('queryString is null when absent or empty', () {
      expect(queryString(_request('GET', '/jobs'), 'customerId'), isNull);
      expect(
        queryString(_request('GET', '/jobs?customerId='), 'customerId'),
        isNull,
      );
      expect(
        queryString(_request('GET', '/jobs?customerId=cust_1'), 'customerId'),
        'cust_1',
      );
    });

    test('queryEnum', () {
      expect(
        queryEnum(_request('GET', '/jobs?scope=open'), 'scope', {
          'open',
          'mine',
        }),
        'open',
      );
      expect(
        queryEnum(_request('GET', '/jobs'), 'scope', {'open', 'mine'}),
        isNull,
      );
      expect(
        () => queryEnum(_request('GET', '/jobs?scope=all'), 'scope', {
          'open',
          'mine',
        }),
        throwsA(_validation('scope must be one of: open, mine')),
      );
    });

    test('queryEnumSet splits on commas', () {
      expect(
        queryEnumSet(_request('GET', '/jobs'), 'status', statuses),
        isNull,
      );
      expect(
        queryEnumSet(
          _request('GET', '/jobs?status=open,claimed'),
          'status',
          statuses,
        ),
        {'open', 'claimed'},
      );
      expect(
        queryEnumSet(
          _request('GET', '/jobs?status=done,%20open,'),
          'status',
          statuses,
        ),
        {'done', 'open'},
      );
      expect(
        () => queryEnumSet(
          _request('GET', '/jobs?status=open,closed'),
          'status',
          statuses,
        ),
        throwsA(_validation('status')),
      );
      expect(
        () =>
            queryEnumSet(_request('GET', '/jobs?status=,'), 'status', statuses),
        throwsA(_validation('status')),
      );
    });

    test('queryTime parses ISO timestamps to UTC', () {
      expect(queryTime(_request('GET', '/jobs'), 'from'), isNull);
      expect(
        queryTime(
          _request('GET', '/jobs?from=2026-01-05T12:00:00.000Z'),
          'from',
        ),
        DateTime.utc(2026, 1, 5, 12),
      );
      expect(
        queryTime(
          _request('GET', '/jobs?from=2026-01-05T07:00:00-05:00'),
          'from',
        ),
        DateTime.utc(2026, 1, 5, 12),
      );
      expect(
        () => queryTime(_request('GET', '/jobs?from=yesterday'), 'from'),
        throwsA(_validation('from must be an ISO-8601 timestamp')),
      );
    });

    test('tzOffset reads minutes east of UTC', () {
      expect(tzOffset(_request('GET', '/crew')), Duration.zero);
      expect(
        tzOffset(_request('GET', '/crew?tz=-300')),
        const Duration(minutes: -300),
      );
      expect(
        tzOffset(_request('GET', '/crew?tz=330')),
        const Duration(minutes: 330),
      );
      for (final bad in ['abc', '1.5', '841', '-841']) {
        expect(
          () => tzOffset(_request('GET', '/crew?tz=$bad')),
          throwsA(_validation('tz')),
          reason: bad,
        );
      }
    });
  });

  group('pipeline', () {
    final now = DateTime.utc(2026, 1, 5, 12);
    late MemoryPersistence persistence;
    late Store store;
    late Handler app;
    late List<Object> reported;
    late Map<String, String> tokens;

    setUp(() async {
      persistence = MemoryPersistence();
      store = await Store.open(
        persistence,
        flushRetries: 0,
        retryDelay: Duration.zero,
        log: (_) {},
      );
      reported = [];
      tokens = {};
      store.tx((tx) {
        void user(String key, String role, {String? linkedId}) {
          tx.put(Collections.users, {
            'id': 'user_$key',
            'name': key,
            'email': '$key@example.com',
            'role': role,
            'linkedId': linkedId,
            'passwordHash': 'pbkdf2-sha256\$1\$c2FsdA==\$aGFzaA==',
          });
          tokens[key] = createSession(
            tx,
            'user_$key',
            now: now,
            ttl: const Duration(days: 30),
          );
        }

        user('lia', 'admin');
        user('sarah', 'customer', linkedId: 'cust_sarah');
        user('marcus', 'crew', linkedId: 'crew_marcus');
        user('tasha', 'crew', linkedId: 'crew_tasha');
        user('rex', 'crew', linkedId: 'crew_rex');
        tx.put(Collections.crew, {'id': 'crew_marcus', 'status': 'active'});
        tx.put(Collections.crew, {'id': 'crew_tasha', 'status': 'pending'});
        tx.put(Collections.crew, {'id': 'crew_rex', 'status': 'rejected'});
        tokens['expired'] = createSession(
          tx,
          'user_sarah',
          now: now.subtract(const Duration(days: 31)),
          ttl: const Duration(days: 30),
        );
        tokens['orphan'] = createSession(
          tx,
          'user_deleted',
          now: now,
          ttl: const Duration(days: 30),
        );
      });
      await store.flush();

      Response whoAmI(Request request) {
        final ctx = authOf(request);
        return jsonOk({
          'userId': ctx.userId,
          'role': ctx.role,
          'customerId': ctx.customerId,
          'crewId': ctx.crewId,
          'crewStatus': ctx.crewStatus,
          'sessionId': ctx.sessionId,
          'flags': [ctx.isAdmin, ctx.isCrew, ctx.isCustomer],
        });
      }

      final router = Router()
        ..get('/health', (Request _) => jsonOk({'status': 'ok'}))
        ..post('/auth/login', (Request _) => jsonOk({'token': 't'}))
        ..post('/auth/signup', (Request _) => jsonCreated({'token': 't'}))
        ..get(
          '/billing/return',
          (Request _) => Response.ok('<p>Card saved.</p>'),
        )
        ..get('/auth/me', whoAmI)
        ..get('/admin-only', (Request r) {
          authOf(r, roles: {Role.admin});
          return jsonOk({'ok': true});
        })
        ..get('/crew-jobs', (Request r) {
          authOf(r, roles: {Role.crew}).requireActiveCrew();
          return jsonOk({'ok': true});
        })
        ..get('/active-crew', (Request r) {
          authOf(r).requireActiveCrew();
          return jsonOk({'ok': true});
        })
        ..post('/echo', (Request r) async => jsonOk(await readJson(r)))
        ..post('/notes/<id>', (Request r, String id) {
          store.tx(
            (tx) => tx.put(Collections.payouts, {'id': id, 'amount': 1}),
          );
          return jsonCreated({'id': id});
        })
        ..post('/write-then-fail', (Request r) {
          store.tx(
            (tx) => tx.put(Collections.payouts, {'id': 'kept', 'amount': 1}),
          );
          throw ApiError.cardDeclined('Declined after the write.');
        })
        ..get('/sweep', (Request r) {
          store.tx(
            (tx) => tx.put(Collections.payouts, {'id': 'swept', 'amount': 1}),
          );
          return jsonOk({'ok': true});
        })
        ..post('/reload', (Request r) async {
          store.tx(
            (tx) => tx.put(Collections.payouts, {'id': 'lost', 'amount': 1}),
          );
          await store.reload();
          return jsonOk({'ok': true});
        })
        ..post('/boom', (Request _) => throw StateError('secret detail'))
        ..post('/storage', (Request _) => throw const StorageException('disk'))
        ..post(
          '/stripe',
          (Request _) => throw const PaymentException('sk_ detail'),
        )
        ..post('/conflict', (Request _) => throw ApiError.jobActive('job_7'));

      app = const Pipeline()
          .addMiddleware(cors())
          .addMiddleware(errors(onError: (e, _) => reported.add(e)))
          .addMiddleware(auth(store, clock: () => now))
          .addMiddleware(autoFlush(store))
          .addHandler(router.call);
    });

    void expectCors(Response response) {
      expect(response.headers['access-control-allow-origin'], '*');
      expect(
        response.headers['access-control-allow-headers'],
        contains('Authorization'),
      );
      expect(
        response.headers['access-control-allow-methods'],
        contains('POST'),
      );
    }

    Future<void> expectError(Response response, int status, String code) async {
      expect(response.statusCode, status);
      expect(response.headers['content-type'], startsWith('application/json'));
      final body = await _body(response);
      expect(body['code'], code);
      expect(body['error'], isA<String>().having((s) => s, 'text', isNotEmpty));
      expectCors(response);
    }

    group('cors', () {
      test('answers OPTIONS without a token', () async {
        for (final path in ['/auth/me', '/jobs/123/claim', '/nowhere']) {
          final response = await app(_request('OPTIONS', path));
          expect(response.statusCode, 200);
          expectCors(response);
          expect(await _body(response), isEmpty);
        }
      });

      test('adds the headers to successes and failures alike', () async {
        expectCors(await app(_request('GET', '/health')));
        expectCors(await app(_request('GET', '/auth/me')));
        expectCors(await app(_request('POST', '/boom', token: tokens['lia'])));
      });
    });

    group('auth', () {
      test('public routes need no token and ignore a bad one', () async {
        expect((await app(_request('GET', '/health'))).statusCode, 200);
        expect((await app(_request('POST', '/auth/login'))).statusCode, 200);
        expect((await app(_request('POST', '/auth/signup'))).statusCode, 201);
        expect(
          (await app(
            _request('GET', '/billing/return?cancelled=1'),
          )).statusCode,
          200,
        );
        expect(
          (await app(
            _request('POST', '/auth/login', token: 'rdf_stale'),
          )).statusCode,
          200,
        );
      });

      test('the allowlist is method-specific', () async {
        await expectError(
          await app(_request('POST', '/health')),
          401,
          'unauthorized',
        );
        await expectError(
          await app(_request('GET', '/auth/login')),
          401,
          'unauthorized',
        );
      });

      test(
        'a missing, malformed, unknown, expired or orphaned token is 401',
        () async {
          await expectError(
            await app(_request('GET', '/auth/me')),
            401,
            'unauthorized',
          );
          for (final header in [
            'Bearer',
            'Bearer ',
            'Basic abc',
            'rdf_no_scheme',
            'Bearer rdf_unknown',
            'Bearer ${tokens['expired']}',
            'Bearer ${tokens['orphan']}',
          ]) {
            await expectError(
              await app(
                _request('GET', '/auth/me', headers: {'authorization': header}),
              ),
              401,
              'unauthorized',
            );
          }
          expect(reported, isEmpty);
        },
      );

      test('resolves the caller for each role', () async {
        Future<Map<String, dynamic>> me(String who) async =>
            _body(await app(_request('GET', '/auth/me', token: tokens[who])));

        final admin = await me('lia');
        expect(admin['userId'], 'user_lia');
        expect(admin['role'], 'admin');
        expect(admin['customerId'], isNull);
        expect(admin['crewId'], isNull);
        expect(admin['crewStatus'], isNull);
        expect(admin['flags'], [true, false, false]);
        expect(admin['sessionId'], isNot(tokens['lia']));
        expect(
          store.session(admin['sessionId'] as String)!['userId'],
          'user_lia',
        );

        final customer = await me('sarah');
        expect(customer['customerId'], 'cust_sarah');
        expect(customer['crewId'], isNull);
        expect(customer['flags'], [false, false, true]);

        final crew = await me('marcus');
        expect(crew['crewId'], 'crew_marcus');
        expect(crew['customerId'], isNull);
        expect(crew['crewStatus'], 'active');
        expect(crew['flags'], [false, true, false]);
        expect((await me('tasha'))['crewStatus'], 'pending');
      });

      test('accepts the scheme in any case', () async {
        final response = await app(
          _request(
            'GET',
            '/auth/me',
            headers: {'authorization': 'bearer ${tokens['lia']}'},
          ),
        );
        expect(response.statusCode, 200);
      });

      test('a session stops working once it is revoked', () async {
        final me = _request('GET', '/auth/me', token: tokens['sarah']);
        final sessionId = (await _body(await app(me)))['sessionId'] as String;
        store.tx((tx) => revokeSession(tx, sessionId));
        await expectError(
          await app(_request('GET', '/auth/me', token: tokens['sarah'])),
          401,
          'unauthorized',
        );
      });

      test('authOf enforces roles with 403', () async {
        expect(
          (await app(
            _request('GET', '/admin-only', token: tokens['lia']),
          )).statusCode,
          200,
        );
        await expectError(
          await app(_request('GET', '/admin-only', token: tokens['sarah'])),
          403,
          'forbidden',
        );
        await expectError(
          await app(_request('GET', '/admin-only', token: tokens['marcus'])),
          403,
          'forbidden',
        );
      });

      test('requireActiveCrew distinguishes pending and rejected', () async {
        expect(
          (await app(
            _request('GET', '/crew-jobs', token: tokens['marcus']),
          )).statusCode,
          200,
        );
        await expectError(
          await app(_request('GET', '/crew-jobs', token: tokens['tasha'])),
          403,
          'crew_pending',
        );
        await expectError(
          await app(_request('GET', '/crew-jobs', token: tokens['rex'])),
          403,
          'crew_rejected',
        );
        await expectError(
          await app(_request('GET', '/crew-jobs', token: tokens['sarah'])),
          403,
          'forbidden',
        );
        await expectError(
          await app(_request('GET', '/active-crew', token: tokens['lia'])),
          403,
          'forbidden',
        );
      });

      test('authOf outside the middleware is 401', () {
        expect(
          () => authOf(_request('GET', '/auth/me')),
          throwsA(
            isA<ApiError>().having((e) => e.code, 'code', 'unauthorized'),
          ),
        );
      });

      test('isPublicRoute matches the contract allowlist exactly', () {
        expect(isPublicRoute(_request('GET', '/health')), isTrue);
        expect(isPublicRoute(_request('POST', '/auth/login')), isTrue);
        expect(isPublicRoute(_request('POST', '/auth/signup')), isTrue);
        expect(
          isPublicRoute(_request('GET', '/billing/return?session_id=cs_1')),
          isTrue,
        );
        expect(isPublicRoute(_request('OPTIONS', '/anything/at/all')), isTrue);
        expect(isPublicRoute(_request('HEAD', '/health')), isTrue);
        expect(isPublicRoute(_request('HEAD', '/auth/me')), isFalse);
        expect(isPublicRoute(_request('POST', '/auth/logout')), isFalse);
        expect(isPublicRoute(_request('GET', '/billing')), isFalse);
        expect(isPublicRoute(_request('GET', '/settings')), isFalse);
      });
    });

    group('errors', () {
      test(
        'ApiError becomes its status and JSON body, extras included',
        () async {
          final response = await app(
            _request('POST', '/conflict', token: tokens['lia']),
          );
          expect(response.statusCode, 409);
          expect(await _body(response), {
            'error': 'This property already has a plough request in progress.',
            'code': 'job_active',
            'jobId': 'job_7',
          });
          expect(reported, isEmpty);
        },
      );

      test('an unknown route is a JSON 404', () async {
        await expectError(
          await app(_request('GET', '/nowhere', token: tokens['lia'])),
          404,
          'not_found',
        );
        await expectError(
          await app(_request('DELETE', '/auth/me', token: tokens['lia'])),
          404,
          'not_found',
        );
      });

      test('bad JSON is a 400 from inside a handler', () async {
        await expectError(
          await app(
            _request('POST', '/echo', token: tokens['lia'], body: '{oops'),
          ),
          400,
          'bad_request',
        );
        final ok = await app(
          _request('POST', '/echo', token: tokens['lia'], body: {'a': 1}),
        );
        expect(await _body(ok), {'a': 1});
      });

      test('an unexpected exception is a 500 that leaks nothing', () async {
        final response = await app(
          _request('POST', '/boom', token: tokens['lia']),
        );
        expect(response.statusCode, 500);
        final text = await response.readAsString();
        expect(jsonDecode(text), {
          'error': 'Something went wrong on our side.',
          'code': 'internal',
        });
        expect(text, isNot(contains('secret detail')));
        expect(reported.single, isA<StateError>());
      });

      test('StorageException is 503 storage_unavailable', () async {
        final response = await app(
          _request('POST', '/storage', token: tokens['lia']),
        );
        await expectError(response, 503, 'storage_unavailable');
        expect(reported.single, isA<StorageException>());
      });

      test(
        'PaymentException is 502 payment_unavailable without the detail',
        () async {
          final response = await app(
            _request('POST', '/stripe', token: tokens['lia']),
          );
          expect(response.statusCode, 502);
          final text = await response.readAsString();
          expect((jsonDecode(text) as Map)['code'], 'payment_unavailable');
          expect(text, isNot(contains('sk_')));
          expect(reported.single, isA<PaymentException>());
        },
      );
    });

    group('autoFlush', () {
      test(
        'a write request is persisted before its response is returned',
        () async {
          final before = persistence.commits.length;
          final response = await app(
            _request('POST', '/notes/n1', token: tokens['lia']),
          );

          expect(response.statusCode, 201);
          expect(persistence.commits, hasLength(before + 1));
          expect(persistence.doc(Collections.payouts, 'n1'), {
            'id': 'n1',
            'amount': 1,
          });
          expect(store.isDirty, isFalse);
        },
      );

      test(
        'a failed flush turns the response into 503; the next flush saves it',
        () async {
          persistence.failNextCommits(1);
          final failed = await app(
            _request('POST', '/notes/n1', token: tokens['lia']),
          );

          await expectError(failed, 503, 'storage_unavailable');
          expect(persistence.doc(Collections.payouts, 'n1'), isNull);
          expect(store.get(Collections.payouts, 'n1'), isNotNull);
          expect(store.isDirty, isTrue);

          final next = await app(
            _request('POST', '/notes/n2', token: tokens['lia']),
          );
          expect(next.statusCode, 201);
          expect(persistence.docs(Collections.payouts).keys, {'n1', 'n2'});
          expect(store.isDirty, isFalse);
        },
      );

      test('a read does not touch persistence when nothing changed', () async {
        final before = persistence.commitAttempts;
        await app(_request('GET', '/auth/me', token: tokens['lia']));
        await app(_request('GET', '/health'));
        expect(persistence.commitAttempts, before);
      });

      test(
        'writes made during a read are flushed, failures stay queued',
        () async {
          persistence.failNextCommits(1);
          final response = await app(
            _request('GET', '/sweep', token: tokens['lia']),
          );

          expect(
            response.statusCode,
            200,
            reason: 'a read never fails on storage',
          );
          expect(store.isDirty, isTrue);

          await app(_request('GET', '/auth/me', token: tokens['lia']));
          expect(persistence.doc(Collections.payouts, 'swept'), isNotNull);
          expect(store.isDirty, isFalse);
        },
      );

      test(
        'what a handler committed before throwing is still persisted',
        () async {
          final response = await app(
            _request('POST', '/write-then-fail', token: tokens['lia']),
          );

          await expectError(response, 402, 'card_declined');
          expect(persistence.doc(Collections.payouts, 'kept'), isNotNull);
        },
      );

      test('a write request that spans a reload is 503', () async {
        final response = await app(
          _request('POST', '/reload', token: tokens['lia']),
        );

        await expectError(response, 503, 'storage_unavailable');
        expect(store.get(Collections.payouts, 'lost'), isNull);
        expect(persistence.doc(Collections.payouts, 'lost'), isNull);
      });

      test(
        'a takeover during the flush is 503 and the store is reloaded',
        () async {
          final epoch = store.epoch;
          persistence.loseLeaseOnNextCommit();
          final response = await app(
            _request('POST', '/notes/n1', token: tokens['lia']),
          );

          await expectError(response, 503, 'storage_unavailable');
          expect(store.epoch, epoch + 1);
          expect(store.get(Collections.payouts, 'n1'), isNull);
          // Sessions were persisted earlier, so the caller is still signed in.
          expect(
            (await app(
              _request('GET', '/auth/me', token: tokens['lia']),
            )).statusCode,
            200,
          );
        },
      );
    });
  });
}

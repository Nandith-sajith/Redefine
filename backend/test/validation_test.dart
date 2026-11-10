import 'dart:convert';

import 'package:redefine_api/src/data/persistence.dart';
import 'package:test/test.dart';

import 'support/harness.dart';

void main() {
  late TestApp t;

  setUp(() async => t = await TestApp.start());

  void expectCors(Reply reply) {
    expect(reply.headers['access-control-allow-origin'], '*');
    expect(
      reply.headers['access-control-allow-headers'],
      contains('Authorization'),
    );
    expect(reply.headers['access-control-allow-methods'], contains('POST'));
  }

  void expectValidation(Reply reply, String field) {
    expectError(reply, 400, 'validation');
    expect(reply.map['error'], contains(field), reason: reply.text);
  }

  group('request bodies', () {
    test(
      'malformed, non-object and oversized bodies are 400 bad_request',
      () async {
        for (final body in [
          '{"name": ',
          'name=Maple',
          '["prop_maple"]',
          '"prop_maple"',
          '42',
          jsonEncode({'propertyId': 'prop_maple', 'note': 'x' * 70000}),
        ]) {
          for (final (path, token) in [
            ('/jobs', t.sarah),
            ('/auth/login', null),
            ('/settings', t.lia),
          ]) {
            final reply = await t.post(path, token: token, body: body);
            expectError(reply, 400, 'bad_request');
            expectCors(reply);
          }
        }
        expect(t.store.count(Collections.jobs), 5);
      },
    );

    test('text that is not valid Unicode is a validation error', () async {
      // Half of an emoji, spelled the way JSON allows.
      const lone = r'\ud83d';
      final signup = await t.post(
        '/auth/signup',
        body:
            '{"name":"Robin $lone","email":"robin@example.com",'
            '"password":"long-enough"}',
      );
      expectValidation(signup, 'name');
      expectValidation(
        await t.post(
          '/auth/signup',
          body:
              '{"name":"Robin","email":"robin@example.com",'
              '"password":"long-enough","phone":"$lone"}',
        ),
        'phone',
      );
      expectValidation(
        await t.post(
          '/properties',
          token: t.sarah,
          body: '{"name":"Home","address":"1 Road","note":"a${lone}b"}',
        ),
        'note',
      );
      expectValidation(
        await t.post(
          '/jobs',
          token: t.lia,
          body: '{"propertyId":"prop_maple","note":"\\ude00"}',
        ),
        'note',
      );
      expect(t.store.count(Collections.users), 7);
      expect(t.store.count(Collections.properties), 4);
      expect(t.store.isDirty, isFalse);

      // A whole pair is an ordinary character.
      final ok = await t.post(
        '/auth/signup',
        body:
            '{"name":"Robin \\ud83d\\ude00","email":"robin@example.com",'
            '"password":"long-enough"}',
      );
      expect(ok.status, 201, reason: ok.text);
      expect((ok.map['user'] as Map)['name'], 'Robin \u{1F600}');
    });

    test('routes without required fields accept an empty body', () async {
      expect(
        (await t.post('/jobs/job_cedar_2/claim', token: t.marcus)).status,
        200,
      );
      expect(
        (await t.post(
          '/jobs/job_cedar_2/start',
          token: t.marcus,
          body: '',
        )).status,
        200,
      );
      final done = await t.post(
        '/jobs/job_cedar_2/complete',
        token: t.marcus,
        body: '{}',
      );
      expect(done.map['crewNote'], '');
      expect(
        (await t.post('/crew/crew_marcus/payouts', token: t.lia)).status,
        200,
      );
    });
  });

  group('signup and login', () {
    final valid = {
      'name': 'Robin Vale',
      'email': 'robin@example.com',
      'password': 'long-enough',
    };

    test('signup names the invalid field', () async {
      final cases = <(Map<String, Object?>, String)>[
        ({...valid, 'name': null}, 'name'),
        ({...valid, 'name': '   '}, 'name'),
        ({...valid, 'name': 'x' * 81}, 'name'),
        ({...valid, 'name': 12}, 'name'),
        ({...valid, 'email': null}, 'email'),
        ({...valid, 'email': 'robin.example.com'}, 'email'),
        ({...valid, 'email': 'robin@example'}, 'email'),
        ({...valid, 'password': null}, 'password'),
        ({...valid, 'password': 'short'}, 'password'),
        ({...valid, 'password': 'x' * 201}, 'password'),
        ({...valid, 'role': 'owner'}, 'role'),
        ({...valid, 'phone': 5551234}, 'phone'),
        ({...valid, 'phone': '5' * 41}, 'phone'),
      ];
      for (final (body, field) in cases) {
        expectValidation(await t.post('/auth/signup', body: body), field);
      }
      expect(t.store.count(Collections.users), 7);
      expect((await t.post('/auth/signup', body: valid)).status, 201);
    });

    test('an email can be used once, whatever its case', () async {
      expect((await t.post('/auth/signup', body: valid)).status, 201);
      expectError(
        await t.post(
          '/auth/signup',
          body: {...valid, 'email': 'ROBIN@Example.com'},
        ),
        409,
        'email_taken',
      );
      expectError(
        await t.post(
          '/auth/signup',
          body: {...valid, 'email': 'lia@redefine.co', 'role': 'crew'},
        ),
        409,
        'email_taken',
      );
      // Two signups racing for one address: exactly one account.
      final race = await Future.wait([
        for (var i = 0; i < 2; i++)
          t.post('/auth/signup', body: {...valid, 'email': 'twin@example.com'}),
      ]);
      expect(race.map((r) => r.status).toList()..sort(), [201, 409]);
      expect(t.store.userByEmail('twin@example.com'), isNotNull);
      expect(t.store.count(Collections.users), 9);
    });

    test('login rejects wrong credentials without saying which part', () async {
      final wrongPassword = await t.post(
        '/auth/login',
        body: {'email': 'lia@redefine.co', 'password': 'not-the-password'},
      );
      final unknownEmail = await t.post(
        '/auth/login',
        body: {'email': 'nobody@redefine.co', 'password': 'redefine'},
      );
      expectError(wrongPassword, 401, 'invalid_credentials');
      expectError(unknownEmail, 401, 'invalid_credentials');
      expect(wrongPassword.text, unknownEmail.text);
      expectCors(wrongPassword);

      expectValidation(
        await t.post('/auth/login', body: {'password': 'redefine'}),
        'email',
      );
      expectValidation(
        await t.post('/auth/login', body: {'email': 'lia@redefine.co'}),
        'password',
      );
      final ok = await t.post(
        '/auth/login',
        body: {'email': ' Lia@Redefine.co ', 'password': 'redefine'},
      );
      expect(ok.status, 200, reason: ok.text);
      expect((ok.map['user'] as Map)['id'], 'user_lia');
      expect(ok.map['token'], startsWith('rdf_'));
    });

    test('five failed logins a minute lock the email with 429', () async {
      Future<Reply> attempt(
        String password, {
        String email = 'sarah.m@gmail.com',
      }) => t.post('/auth/login', body: {'email': email, 'password': password});

      for (var i = 0; i < 5; i++) {
        expectError(await attempt('wrong-$i'), 401, 'invalid_credentials');
        t.advance(const Duration(seconds: 5));
      }
      expectError(await attempt('wrong-again'), 429, 'rate_limited');
      // Even the right password has to wait, but other accounts do not.
      expectError(await attempt('redefine'), 429, 'rate_limited');
      expect(
        (await attempt('redefine', email: 'anna.t@gmail.com')).status,
        200,
      );

      t.advance(const Duration(seconds: 40));
      expect((await attempt('redefine')).status, 200);
      // A success wipes the slate.
      for (var i = 0; i < 4; i++) {
        expectError(await attempt('wrong-$i'), 401, 'invalid_credentials');
      }
      expect((await attempt('redefine')).status, 200);
      for (var i = 0; i < 5; i++) {
        expectError(await attempt('wrong-$i'), 401, 'invalid_credentials');
      }
      expectError(await attempt('redefine'), 429, 'rate_limited');
    });

    test('failed logins from elsewhere do not lock the owner out', () async {
      t = await TestApp.start(behindProxy: true);
      Future<Reply> attempt(String password, String forwardedFor) => t.post(
        '/auth/login',
        body: {'email': 'lia@redefine.co', 'password': password},
        headers: TestApp.from(forwardedFor),
      );

      for (var i = 0; i < 5; i++) {
        expectError(
          await attempt('guess-$i', '203.0.113.7'),
          401,
          'invalid_credentials',
        );
      }
      expectError(
        await attempt('redefine', '203.0.113.7'),
        429,
        'rate_limited',
      );
      // The owner signs in from their own address all the while.
      expect((await attempt('redefine', '198.51.100.4')).status, 200);
      // Only the last address is the proxy's word; the ones before it are
      // whatever the client claimed.
      expectError(
        await attempt('redefine', '198.51.100.4, 203.0.113.7'),
        429,
        'rate_limited',
      );
      expect(
        (await attempt('redefine', '203.0.113.7, 198.51.100.4')).status,
        200,
      );
    });

    test('one client gets thirty logins and signups a minute', () async {
      for (var i = 0; i < 30; i++) {
        expectError(
          await t.post(
            '/auth/login',
            body: {'email': 'nobody$i@example.com', 'password': 'guess'},
          ),
          401,
          'invalid_credentials',
        );
      }
      expectError(
        await t.post(
          '/auth/login',
          body: {'email': 'lia@redefine.co', 'password': 'redefine'},
        ),
        429,
        'rate_limited',
      );
      expectError(
        await t.post('/auth/signup', body: valid),
        429,
        'rate_limited',
      );
      expect(t.store.count(Collections.users), 7);

      t.advance(const Duration(seconds: 61));
      await t.login('lia@redefine.co');
      expect((await t.post('/auth/signup', body: valid)).status, 201);
    });

    test('one client can create ten accounts in ten minutes', () async {
      Future<Reply> signup(int i) => t.post(
        '/auth/signup',
        body: {...valid, 'email': 'robin$i@example.com', 'role': 'crew'},
      );

      for (var i = 0; i < 10; i++) {
        expect((await signup(i)).status, 201);
      }
      final refused = await signup(10);
      expectError(refused, 429, 'rate_limited');
      expect(refused.map['error'], contains('ten minutes'));
      // A taken email is not told apart while the limit holds.
      expectError(await signup(0), 429, 'rate_limited');
      expect(t.store.count(Collections.users), 17);
      expect(t.store.count(Collections.crew), 13);

      t.advance(const Duration(minutes: 10));
      expect((await signup(10)).status, 201);
    });

    test(
      'password hashing is capped however many clients ask at once',
      () async {
        t = await TestApp.start(behindProxy: true);
        final replies = await Future.wait([
          for (var i = 0; i < 40; i++)
            t.post(
              '/auth/login',
              body: {'email': 'nobody$i@example.com', 'password': 'guess-$i'},
              headers: TestApp.from('198.51.100.$i'),
            ),
        ]);
        // Two at work and ten in line are answered; the rest are turned away
        // at once instead of piling up.
        final served = replies.where((r) => r.status == 401);
        final refused = replies.where((r) => r.status != 401);
        expect(served, hasLength(12));
        expect(refused, hasLength(28));
        for (final reply in refused) {
          expectError(reply, 429, 'rate_limited');
        }
        // The line has drained: the next caller is served.
        final next = await t.post(
          '/auth/login',
          body: {'email': 'lia@redefine.co', 'password': 'redefine'},
          headers: TestApp.from('198.51.100.200'),
        );
        expect(next.status, 200, reason: next.text);
      },
    );
  });

  group('fields', () {
    test('properties', () async {
      Future<Reply> add(Map<String, Object?> body, {String? token}) =>
          t.post('/properties', token: token ?? t.sarah, body: body);

      expectValidation(await add({'address': '1 Road'}), 'name');
      expectValidation(await add({'name': 'Home'}), 'address');
      expectValidation(
        await add({'name': 'x' * 61, 'address': '1 Road'}),
        'name',
      );
      expectValidation(
        await add({'name': 'Home', 'address': 'x' * 161}),
        'address',
      );
      expectValidation(
        await add({'name': 'Home', 'address': '1 Road', 'note': 'x' * 501}),
        'note',
      );
      expectValidation(
        await add({
          'name': 'Home',
          'address': '1 Road',
          'illustration': 'castle',
        }),
        'illustration',
      );
      expectValidation(
        await add({'name': 'Home', 'address': '1 Road'}, token: t.lia),
        'customerId',
      );
      expectValidation(
        await t.get('/properties?status=sold', token: t.lia),
        'status',
      );
      expect(t.store.count(Collections.properties), 4);

      final ok = await add({'name': ' Home ', 'address': ' 1 Road '});
      expect(ok.status, 201, reason: ok.text);
      expect((ok.map['property'] as Map)['name'], 'Home');
      expect((ok.map['property'] as Map)['illustration'], 'house');
      expect((ok.map['property'] as Map)['note'], '');
    });

    test('quote and re-price amounts', () async {
      for (final path in [
        '/quotes/quote_cabin/send',
        '/properties/prop_maple/price',
      ]) {
        Future<Reply> send(Map<String, Object?> body) =>
            t.post(path, token: t.lia, body: body);
        expectValidation(await send({'crewPay': 20}), 'price');
        expectValidation(await send({'price': 40}), 'crewPay');
        expectValidation(await send({'price': 0, 'crewPay': 0}), 'price');
        expectValidation(await send({'price': 10001, 'crewPay': 5}), 'price');
        expectValidation(await send({'price': 49.5, 'crewPay': 5}), 'price');
        expectValidation(await send({'price': '45', 'crewPay': 5}), 'price');
        expectValidation(await send({'price': 40, 'crewPay': 41}), 'crewPay');
        expectValidation(await send({'price': 40, 'crewPay': -1}), 'crewPay');
      }
      expect(
        t.store.get(Collections.quotes, 'quote_cabin')!['status'],
        'pending',
      );
      expect(t.store.get(Collections.properties, 'prop_maple')!['price'], 45);
      expectValidation(
        await t.get('/quotes?status=open', token: t.lia),
        'status',
      );
    });

    test('jobs', () async {
      expectValidation(
        await t.post('/jobs', token: t.sarah, body: {}),
        'propertyId',
      );
      expectValidation(
        await t.post(
          '/jobs',
          token: t.sarah,
          body: {'propertyId': 'prop_maple', 'shovel': 'yes'},
        ),
        'shovel',
      );
      expectValidation(
        await t.post(
          '/jobs',
          token: t.sarah,
          body: {'propertyId': 'prop_maple', 'note': 'x' * 501},
        ),
        'note',
      );
      expectValidation(
        await t.post(
          '/jobs',
          token: t.lia,
          body: {'propertyId': 'prop_maple', 'payment': 'cash'},
        ),
        'payment',
      );
      await t.post('/jobs/job_cedar_2/claim', token: t.marcus);
      await t.post('/jobs/job_cedar_2/start', token: t.marcus);
      expectValidation(
        await t.post(
          '/jobs/job_cedar_2/complete',
          token: t.marcus,
          body: {'crewNote': 'x' * 501},
        ),
        'crewNote',
      );
      expect(t.jobDoc('job_cedar_2')['status'], 'inProgress');
      expectValidation(
        await t.post(
          '/crew/crew_marcus/payouts',
          token: t.lia,
          body: {'note': 7},
        ),
        'note',
      );
    });

    test('settings', () async {
      Future<Reply> set(Map<String, Object?> body) =>
          t.post('/settings', token: t.lia, body: body);
      expectValidation(await set({'shovelPrice': -1}), 'shovelPrice');
      expectValidation(await set({'shovelPrice': 1001}), 'shovelPrice');
      expectValidation(await set({'shovelPrice': 'free'}), 'shovelPrice');
      expectValidation(
        await set({'openJobExpiryHours': 0}),
        'openJobExpiryHours',
      );
      expectValidation(
        await set({'openJobExpiryHours': 121}),
        'openJobExpiryHours',
      );
      // The bonus may not exceed the price, whichever of the two changes.
      expectValidation(await set({'crewShovelBonus': 21}), 'crewShovelBonus');
      expectValidation(await set({'shovelPrice': 9}), 'crewShovelBonus');
      expectValidation(
        await set({'shovelPrice': 30, 'crewShovelBonus': 31}),
        'crewShovelBonus',
      );
      expect(t.store.settings!['shovelPrice'], 20);
      expect((await set({})).status, 200);
      expect(
        (await set({'shovelPrice': 30, 'crewShovelBonus': 30})).status,
        200,
      );
    });

    test('the tz parameter', () async {
      for (final path in [
        '/dashboard/admin?tz=east',
        '/crew?tz=900',
        '/crew/crew_marcus/pay?tz=-841',
        '/crew/crew_marcus/pay?tz=1.5',
      ]) {
        expectValidation(await t.get(path, token: t.lia), 'tz');
      }
      expect((await t.get('/crew?tz=-300', token: t.lia)).status, 200);
      expect((await t.get('/crew?tz=', token: t.lia)).status, 200);
    });
  });

  group('errors', () {
    test('an unknown route is a JSON 404 with CORS headers', () async {
      for (final (method, path) in [
        ('GET', '/nowhere'),
        ('GET', '/jobs/job_cedar_2/claim'),
        ('DELETE', '/jobs/job_cedar_2'),
        ('PUT', '/settings'),
        ('GET', '/'),
      ]) {
        final reply = await t.call(method, path, token: t.lia);
        expectError(reply, 404, 'not_found');
        expect(reply.headers['content-type'], startsWith('application/json'));
        expectCors(reply);
      }
      // The same without a token: a missing route is not an auth problem.
      for (final (method, path) in [
        ('GET', '/nowhere'),
        ('POST', '/health'),
        ('GET', '/auth/login'),
        ('POST', '/jobs/job_cedar_2'),
      ]) {
        final anonymous = await t.call(method, path);
        expectError(anonymous, 404, 'not_found');
        expectCors(anonymous);
      }
      final head = await t.call('HEAD', '/health');
      expect(head.status, 200);
      expectError(await t.call('HEAD', '/auth/me'), 401, 'unauthorized');
    });

    test('every kind of error carries CORS headers and a JSON body', () async {
      final replies = [
        await t.get('/auth/me'),
        await t.get('/customers', token: t.sarah),
        await t.get('/jobs/job_nope', token: t.lia),
        await t.post('/jobs', token: t.sarah, body: '{'),
        await t.post('/jobs/job_cedar_1/claim', token: t.marcus),
        await t.post('/billing/setup-session', token: t.lia),
      ];
      expect(replies.map((r) => r.status), [401, 403, 404, 400, 409, 403]);
      for (final reply in replies) {
        expectCors(reply);
        expect(reply.headers['content-type'], startsWith('application/json'));
        expect(reply.map.keys, containsAll(['error', 'code']));
      }
    });

    test('preflight requests are answered without a token', () async {
      for (final path in ['/jobs', '/auth/login', '/crew/me/pay', '/nowhere']) {
        final reply = await t.call(
          'OPTIONS',
          path,
          headers: {
            'origin': 'http://localhost:5000',
            'access-control-request-method': 'POST',
            'access-control-request-headers': 'authorization,content-type',
          },
        );
        expect(reply.status, 200);
        expectCors(reply);
      }
    });

    test('success responses are JSON with CORS headers, never empty', () async {
      for (final reply in [
        await t.get('/health'),
        await t.get('/jobs', token: t.paul),
        await t.post('/auth/logout', token: t.anna),
      ]) {
        expect(reply.status, 200);
        expectCors(reply);
        expect(reply.headers['content-type'], startsWith('application/json'));
        expect(reply.text, isNotEmpty);
        expect(() => reply.json, returnsNormally);
      }
    });

    test('an unexpected failure is a 500 that leaks nothing', () async {
      // Corrupt the database behind the server's back.
      t.store.tx(
        (tx) => tx.delete(Collections.settings, Collections.settingsId),
      );
      final reply = await t.get('/settings', token: t.lia);
      expectError(reply, 500, 'internal');
      expect(reply.map, {
        'error': 'Something went wrong on our side.',
        'code': 'internal',
      });
      expectCors(reply);
      expect(t.logs.join('\n'), contains('ERROR'));
    });
  });
}

import 'dart:async';
import 'dart:io';

import 'package:redefine_api/src/auth/limits.dart';
import 'package:redefine_api/src/errors.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

final _rateLimited = throwsA(
  isA<ApiError>()
      .having((e) => e.status, 'status', 429)
      .having((e) => e.code, 'code', 'rate_limited'),
);

class _Connection implements HttpConnectionInfo {
  @override
  final InternetAddress remoteAddress;
  _Connection(String address) : remoteAddress = InternetAddress(address);

  @override
  int get remotePort => 50000;

  @override
  int get localPort => 8080;
}

Request _request({String? forwardedFor, String? socket}) => Request(
  'POST',
  Uri.parse('http://localhost/auth/login'),
  headers: {'x-forwarded-for': ?forwardedFor},
  context: {
    if (socket != null) 'shelf.io.connection_info': _Connection(socket),
  },
);

void main() {
  group('RateLimiter', () {
    final start = DateTime.utc(2026, 1, 7, 15);
    late RateLimiter limiter;

    setUp(
      () => limiter = RateLimiter(max: 3, window: const Duration(minutes: 1)),
    );

    test('allows max hits per key per window', () {
      for (var i = 0; i < 3; i++) {
        limiter.hit('a', start.add(Duration(seconds: i * 10)));
      }
      expect(
        () => limiter.hit('a', start.add(const Duration(seconds: 30))),
        _rateLimited,
      );
      // Other keys are not affected.
      limiter.hit('b', start.add(const Duration(seconds: 30)));

      // The oldest hit leaves the window a minute after it was made.
      expect(
        () => limiter.hit('a', start.add(const Duration(seconds: 59))),
        _rateLimited,
      );
      limiter.hit('a', start.add(const Duration(seconds: 60)));
      expect(
        () => limiter.hit('a', start.add(const Duration(seconds: 61))),
        _rateLimited,
      );
    });

    test('a refused hit is not counted', () {
      for (var i = 0; i < 3; i++) {
        limiter.hit('a', start);
      }
      for (var i = 0; i < 10; i++) {
        expect(
          () => limiter.hit('a', start.add(const Duration(seconds: 30))),
          _rateLimited,
        );
      }
      limiter.hit('a', start.add(const Duration(seconds: 60)));
    });

    test('check does not count, record does not check', () {
      for (var i = 0; i < 5; i++) {
        limiter.check('a', start);
      }
      for (var i = 0; i < 3; i++) {
        limiter.record('a', start);
      }
      expect(() => limiter.check('a', start), _rateLimited);
      limiter.record('a', start);
    });

    test('clear forgets a key', () {
      for (var i = 0; i < 3; i++) {
        limiter.hit('a', start);
      }
      limiter.clear('a');
      limiter.hit('a', start);
    });

    test('forgetting stale keys leaves the live ones exact', () {
      for (var i = 0; i < 25000; i++) {
        limiter.hit('key-$i', start.add(Duration(milliseconds: i * 10)));
      }
      // Still exact for a key that is in its window.
      final now = start.add(const Duration(milliseconds: 250000));
      limiter
        ..hit('key-24999', now)
        ..hit('key-24999', now);
      expect(() => limiter.hit('key-24999', now), _rateLimited);
    });
  });

  group('WorkGate', () {
    test(
      'runs maxRunning jobs at once and the rest in order of arrival',
      () async {
        final gate = WorkGate(maxRunning: 2, maxWaiting: 3);
        final started = <int>[];
        final finish = [for (var i = 0; i < 5; i++) Completer<int>()];
        var running = 0;
        var mostRunning = 0;
        final results = [
          for (var i = 0; i < 5; i++)
            gate.run(() async {
              started.add(i);
              running++;
              if (running > mostRunning) mostRunning = running;
              final value = await finish[i].future;
              running--;
              return value;
            }),
        ];
        await pumpEventQueue();
        expect(started, [0, 1]);

        finish[1].complete(11);
        await pumpEventQueue();
        expect(started, [0, 1, 2]);
        finish[0].complete(10);
        finish[2].complete(12);
        await pumpEventQueue();
        expect(started, [0, 1, 2, 3, 4]);
        finish[3].complete(13);
        finish[4].complete(14);

        expect(await Future.wait(results), [10, 11, 12, 13, 14]);
        expect(mostRunning, 2);
      },
    );

    test('turns callers away at once when the line is full', () async {
      final gate = WorkGate(maxRunning: 1, maxWaiting: 2);
      final release = Completer<void>();
      final admitted = [
        for (var i = 0; i < 3; i++) gate.run(() => release.future),
      ];
      var ran = false;
      await expectLater(gate.run(() async => ran = true), _rateLimited);
      expect(ran, isFalse);

      release.complete();
      await Future.wait(admitted);
      // With the line drained there is room again.
      expect(await gate.run(() async => 'served'), 'served');
    });

    test('a failing job frees its slot', () async {
      final gate = WorkGate(maxRunning: 1, maxWaiting: 1);
      final failing = gate.run<void>(() async => throw StateError('boom'));
      final waiting = gate.run(() async => 'next');
      await expectLater(failing, throwsStateError);
      expect(await waiting, 'next');
      expect(await gate.run(() async => 'after'), 'after');
    });
  });

  group('clientKey', () {
    test('behind the proxy only the last forwarded address counts', () {
      expect(
        clientKey(_request(forwardedFor: '203.0.113.7'), behindProxy: true),
        '203.0.113.7',
      );
      expect(
        clientKey(
          _request(forwardedFor: '10.0.0.1, 198.51.100.4 ,203.0.113.7 '),
          behindProxy: true,
        ),
        '203.0.113.7',
      );
    });

    test('without a proxy the header is ignored and the socket counts', () {
      expect(
        clientKey(
          _request(forwardedFor: '203.0.113.7', socket: '192.0.2.10'),
          behindProxy: false,
        ),
        '192.0.2.10',
      );
      expect(
        clientKey(_request(socket: '192.0.2.10'), behindProxy: true),
        '192.0.2.10',
        reason: 'no header: fall back to the socket',
      );
    });

    test('IPv6 clients are keyed by their /64 network', () {
      final a = clientKey(
        _request(forwardedFor: '2001:db8:12:34:aaaa:bbbb:cccc:dddd'),
        behindProxy: true,
      );
      final b = clientKey(
        _request(forwardedFor: '2001:db8:12:34::1'),
        behindProxy: true,
      );
      final other = clientKey(
        _request(forwardedFor: '2001:db8:12:35::1'),
        behindProxy: true,
      );
      expect(a, '20010db800120034/64');
      expect(b, a);
      expect(other, isNot(a));
      expect(
        clientKey(_request(socket: '::1'), behindProxy: false),
        endsWith('/64'),
      );
      expect(
        clientKey(_request(socket: '::ffff:192.0.2.10'), behindProxy: false),
        '192.0.2.10',
      );
    });

    test('is "unknown" when there is nothing to go by', () {
      expect(clientKey(_request(), behindProxy: false), 'unknown');
      expect(clientKey(_request(), behindProxy: true), 'unknown');
      expect(
        clientKey(_request(forwardedFor: 'not an address'), behindProxy: true),
        'unknown',
      );
      expect(
        clientKey(_request(forwardedFor: '203.0.113.7,'), behindProxy: true),
        'unknown',
      );
    });
  });
}

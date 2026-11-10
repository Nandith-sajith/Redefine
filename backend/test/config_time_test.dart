import 'package:redefine_api/src/config.dart';
import 'package:redefine_api/src/time.dart';
import 'package:test/test.dart';

void main() {
  group('Config.fromEnv', () {
    test('defaults to a local memory server in manual mode', () {
      final config = Config.fromEnv({});
      expect(config.port, 8080);
      expect(config.persistence, 'memory');
      expect(config.gcpProject, isNull);
      expect(config.firestoreDatabase, '(default)');
      expect(config.stripeSecretKey, isNull);
      expect(config.stripeConfigured, isFalse);
      expect(config.publicBaseUrl, 'http://localhost:8080');
      expect(config.adminInviteCode, isNull);
      expect(config.seedDemo, isTrue);
      expect(config.demoPassword, 'redefine');
      expect(config.pbkdf2Iterations, 100000);
      expect(config.sessionTtl, const Duration(days: 30));
      expect(config.onCloudRun, isFalse);
    });

    test('reads a Cloud Run + Firestore + Stripe environment', () {
      final config = Config.fromEnv({
        'PORT': '9090',
        'PERSISTENCE': 'firestore',
        'GCP_PROJECT': 'redefine-8a0b828f',
        'FIRESTORE_DATABASE': 'redefine',
        'STRIPE_SECRET_KEY': '  sk_test_abc\r\n',
        'PUBLIC_BASE_URL': 'https://api.example.com/',
        'ADMIN_INVITE_CODE': 'let-me-in-through-the-snow\n',
        'DEMO_PASSWORD': 'snowfall',
        'PBKDF2_ITERATIONS': '150000',
        'SESSION_TTL_DAYS': '7',
        'K_SERVICE': 'redefine-api',
      });
      expect(config.port, 9090);
      expect(config.persistence, 'firestore');
      expect(config.gcpProject, 'redefine-8a0b828f');
      expect(config.firestoreDatabase, 'redefine');
      expect(config.stripeSecretKey, 'sk_test_abc');
      expect(config.stripeConfigured, isTrue);
      expect(config.publicBaseUrl, 'https://api.example.com');
      expect(config.adminInviteCode, 'let-me-in-through-the-snow');
      expect(
        config.seedDemo,
        isFalse,
        reason: 'firestore never seeds by default',
      );
      expect(config.demoPassword, 'snowfall');
      expect(config.pbkdf2Iterations, 150000);
      expect(config.sessionTtlDays, 7);
      expect(config.onCloudRun, isTrue);
    });

    test('SEED_DEMO overrides the per-persistence default', () {
      expect(Config.fromEnv({'SEED_DEMO': 'false'}).seedDemo, isFalse);
      final config = Config.fromEnv({
        'PERSISTENCE': 'firestore',
        'GCP_PROJECT': 'p',
        'SEED_DEMO': 'True',
        'DEMO_PASSWORD': 'snowfall-2026',
      });
      expect(config.seedDemo, isTrue);
      expect(config.demoPassword, 'snowfall-2026');
    });

    test('real data is never seeded with a public or weak password', () {
      const firestore = {'PERSISTENCE': 'firestore', 'GCP_PROJECT': 'p'};
      const live = {'STRIPE_SECRET_KEY': 'sk_live_abc'};
      for (final env in [
        {...firestore, 'SEED_DEMO': 'true'},
        {...firestore, 'SEED_DEMO': 'true', 'DEMO_PASSWORD': 'redefine'},
        {...firestore, 'SEED_DEMO': 'true', 'DEMO_PASSWORD': 'short'},
        {...firestore, 'SEED_DEMO': 'true', 'DEMO_PASSWORD': '   '},
        // A memory server seeds by default; with a live key that is refused.
        live,
        {...live, 'DEMO_PASSWORD': 'redefine'},
        {'STRIPE_SECRET_KEY': 'rk_live_abc'},
      ]) {
        expect(
          () => Config.fromEnv(env),
          throwsA(
            isA<ConfigError>().having(
              (e) => e.message,
              'message',
              allOf(contains('DEMO_PASSWORD'), isNot(contains('redefine'))),
            ),
          ),
          reason: '$env',
        );
      }
      // Without the seed the password does not matter.
      expect(Config.fromEnv(firestore).seedDemo, isFalse);
      expect(
        Config.fromEnv({...firestore, 'SEED_DEMO': 'false'}).seedDemo,
        isFalse,
      );
      expect(Config.fromEnv({...live, 'SEED_DEMO': 'false'}).seedDemo, isFalse);
      // A test key on a memory server is a demo like any other.
      final demo = Config.fromEnv({'STRIPE_SECRET_KEY': 'sk_test_abc'});
      expect((demo.seedDemo, demo.demoPassword), (true, 'redefine'));
    });

    test('a short admin invite code is refused', () {
      for (final code in ['x', 'let-me-in', 'fifteen-chars-k']) {
        expect(code.length, lessThan(16));
        expect(
          () => Config.fromEnv({'ADMIN_INVITE_CODE': code}),
          throwsA(
            isA<ConfigError>().having(
              (e) => e.message,
              'message',
              allOf(contains('ADMIN_INVITE_CODE'), isNot(contains(code))),
            ),
          ),
        );
      }
      expect(
        Config.fromEnv({
          'ADMIN_INVITE_CODE': 'sixteen-chars-ok',
        }).adminInviteCode,
        'sixteen-chars-ok',
      );
    });

    test('the default public URL follows the port', () {
      expect(
        Config.fromEnv({'PORT': '3000'}).publicBaseUrl,
        'http://localhost:3000',
      );
    });

    test('blank values count as unset', () {
      final config = Config.fromEnv({
        'STRIPE_SECRET_KEY': '   ',
        'ADMIN_INVITE_CODE': '',
        'PORT': '',
      });
      expect(config.stripeSecretKey, isNull);
      expect(config.adminInviteCode, isNull);
      expect(config.port, 8080);
    });

    test('rejects unusable values', () {
      for (final env in [
        {'PORT': 'eighty'},
        {'PORT': '70000'},
        {'PERSISTENCE': 'postgres'},
        {'PERSISTENCE': 'firestore'},
        {'SEED_DEMO': 'maybe'},
        {'PBKDF2_ITERATIONS': '0'},
        {'SESSION_TTL_DAYS': '-1'},
        {'PUBLIC_BASE_URL': 'not a url'},
      ]) {
        expect(
          () => Config.fromEnv(env),
          throwsA(isA<ConfigError>()),
          reason: '$env',
        );
      }
    });

    test('describe never includes secrets', () {
      final config = Config.fromEnv({
        'STRIPE_SECRET_KEY': 'sk_live_supersecret',
        'ADMIN_INVITE_CODE': 'invite-secret-code',
        'DEMO_PASSWORD': 'demo-secret',
      });
      for (final text in [config.describe(), '$config']) {
        expect(text, isNot(contains('supersecret')));
        expect(text, isNot(contains('invite-secret')));
        expect(text, isNot(contains('demo-secret')));
        expect(text, contains('payments=stripe'));
      }
    });
  });

  group('time', () {
    test('isoTime is UTC with millisecond precision', () {
      expect(isoTime(DateTime.utc(2026, 1, 5, 12)), '2026-01-05T12:00:00.000Z');
      expect(
        isoTime(DateTime.utc(2026, 1, 5, 12, 0, 0, 7, 999)),
        '2026-01-05T12:00:00.007Z',
      );
      final local = DateTime(2026, 1, 5, 12);
      expect(isoTime(local), endsWith('Z'));
      expect(DateTime.parse(isoTime(local)), local.toUtc());
    });

    test('isoTime strings sort chronologically', () {
      final times = [
        DateTime.utc(2026, 1, 5, 12, 0, 0, 100),
        DateTime.utc(2025, 12, 31, 23, 59, 59, 999),
        DateTime.utc(2026, 1, 5, 12),
        DateTime.utc(2026, 10, 1),
      ];
      final sortedText = times.map(isoTime).toList()..sort();
      expect(sortedText, (times..sort()).map(isoTime));
    });

    test('parseTime returns UTC or null', () {
      expect(
        parseTime('2026-01-05T12:00:00.000Z'),
        DateTime.utc(2026, 1, 5, 12),
      );
      expect(
        parseTime('2026-01-05T07:00:00-05:00'),
        DateTime.utc(2026, 1, 5, 12),
      );
      expect(parseTime('2026-01-05T12:00:00.000Z')!.isUtc, isTrue);
      expect(parseTime('soon'), isNull);
      expect(parseTime(null), isNull);
      expect(parseTime(42), isNull);
    });

    test('localDayStart is local midnight as a UTC instant', () {
      const toronto = Duration(minutes: -300);
      // 03:30 UTC on the 6th is still 22:30 on the 5th in UTC-5.
      final now = DateTime.utc(2026, 1, 6, 3, 30);
      expect(localDayStart(now, toronto), DateTime.utc(2026, 1, 5, 5));
      expect(localDayStart(now, Duration.zero), DateTime.utc(2026, 1, 6));
      expect(
        localDayStart(now, const Duration(minutes: 330)),
        DateTime.utc(2026, 1, 5, 18, 30),
      );
      expect(
        localDayStart(DateTime.utc(2026, 1, 6), Duration.zero),
        DateTime.utc(2026, 1, 6),
      );
    });

    test('localWeekStart is Monday 00:00 local', () {
      const toronto = Duration(minutes: -300);
      // Monday 2026-01-05 03:30 UTC is still Sunday the 4th in UTC-5.
      final now = DateTime.utc(2026, 1, 5, 3, 30);
      expect(localWeekStart(now, Duration.zero), DateTime.utc(2026, 1, 5));
      expect(localWeekStart(now, toronto), DateTime.utc(2025, 12, 29, 5));
      // A Sunday belongs to the week that started six days earlier.
      expect(
        localWeekStart(DateTime.utc(2026, 1, 11, 23, 59), Duration.zero),
        DateTime.utc(2026, 1, 5),
      );
      expect(
        localWeekStart(DateTime.utc(2026, 1, 12), Duration.zero),
        DateTime.utc(2026, 1, 12),
      );
    });
  });
}

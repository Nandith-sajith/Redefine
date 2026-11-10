import 'package:redefine_api/src/config.dart';
import 'package:redefine_api/src/data/persistence.dart';
import 'package:redefine_api/src/data/seed.dart';
import 'package:redefine_api/src/model.dart';
import 'package:test/test.dart';

import 'support/harness.dart';

/// What a real deployment starts with: the three sign-in accounts and
/// nothing else. The sample data stays a fixture for tests and local
/// development.
void main() {
  group('accounts-only seed', () {
    late TestApp t;

    setUp(() async {
      t = await TestApp.start(stripe: false, seed: false);
      expect(await seedDemo(t.store, config: t.app.config, now: t.now), isTrue);
      await t.store.flush();
    });

    test('creates exactly one account per role and no data', () {
      expect(
        t.store.all(Collections.users).map((u) => u['email']),
        unorderedEquals([
          'lia@redefine.co',
          'marcus@redefine.co',
          'sarah.m@gmail.com',
        ]),
      );
      expect(t.store.count(Collections.customers), 1);
      expect(t.store.count(Collections.crew), 1);
      expect(
        t.store.require(Collections.crew, 'crew_marcus')['status'],
        CrewStatus.active,
      );
      expect(
        t.store.require(Collections.customers, 'cust_sarah')['userId'],
        'user_sarah',
      );
      for (final collection in [
        Collections.properties,
        Collections.quotes,
        Collections.jobs,
        Collections.payouts,
        Collections.sessions,
      ]) {
        expect(t.store.count(collection), 0, reason: collection);
      }
      expect(t.store.settings, isNotNull);
    });

    test('all three accounts sign in and see an empty system', () async {
      for (final email in [
        'lia@redefine.co',
        'marcus@redefine.co',
        'sarah.m@gmail.com',
      ]) {
        final res = await t.post(
          '/auth/login',
          body: {'email': email, 'password': 'redefine'},
        );
        expect(res.status, 200, reason: email);
      }
      final sarah = t.tokenFor('user_sarah');
      final properties = await t.get('/properties', token: sarah);
      expect(properties.json, isEmpty);
      final marcus = t.tokenFor('user_marcus');
      final open = await t.get('/jobs?scope=open', token: marcus);
      expect(open.json, isEmpty);
      final lia = t.tokenFor('user_lia');
      final customers = await t.get('/customers', token: lia);
      expect((customers.json as List).map((c) => c['id']), ['cust_sarah']);
      final dashboard = await t.get('/dashboard/admin', token: lia);
      final counts = (dashboard.json as Map)['counts'] as Map;
      expect(counts.values.every((v) => v == 0), isTrue, reason: '$counts');
    });

    test('does not run twice', () async {
      expect(
        await seedDemo(t.store, config: t.app.config, now: t.now),
        isFalse,
      );
      expect(t.store.count(Collections.users), 3);
    });
  });

  test('the sample data fixture adds the extra accounts and records', () async {
    final t = await TestApp.start(stripe: false, seed: false);
    expect(
      await seedDemo(
        t.store,
        config: t.app.config,
        now: t.now,
        sampleData: true,
      ),
      isTrue,
    );
    expect(t.store.count(Collections.users), 7);
    expect(t.store.count(Collections.customers), 3);
    expect(t.store.count(Collections.crew), 3);
    expect(t.store.count(Collections.properties), 4);
    expect(t.store.count(Collections.quotes), 4);
    expect(t.store.count(Collections.jobs), 5);
    expect(t.store.count(Collections.payouts), 1);
  });

  group('SEED_SAMPLE_DATA', () {
    test('is off by default and only for a memory server', () {
      expect(Config.fromEnv({}).seedSampleData, isFalse);
      expect(
        Config.fromEnv({'SEED_SAMPLE_DATA': 'true'}).seedSampleData,
        isTrue,
      );
      expect(
        Config.fromEnv({'SEED_SAMPLE_DATA': 'true'}).describe(),
        contains('seedDemo=true+sample'),
      );
      expect(
        () => Config.fromEnv({
          'PERSISTENCE': 'firestore',
          'GCP_PROJECT': 'p',
          'SEED_DEMO': 'false',
          'SEED_SAMPLE_DATA': 'true',
        }),
        throwsA(
          isA<ConfigError>().having(
            (e) => e.message,
            'message',
            contains('SEED_SAMPLE_DATA'),
          ),
        ),
      );
    });
  });
}

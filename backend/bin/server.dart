import 'dart:async';
import 'dart:io';

import 'package:redefine_api/api.dart';
import 'package:redefine_api/src/data/firestore_persistence.dart';
import 'package:redefine_api/src/data/persistence.dart';
import 'package:redefine_api/src/data/seed.dart';
import 'package:redefine_api/src/data/store.dart';
import 'package:redefine_api/src/payments/stripe_gateway.dart';
import 'package:shelf/shelf_io.dart' as io;

/// Entry point: configuration from the environment, then persistence,
/// payments, seed and the HTTP server. Exits non-zero when the configuration
/// is unusable or the database cannot be loaded.
Future<void> main() async {
  final Config config;
  try {
    config = Config.fromEnv(Platform.environment);
  } on ConfigError catch (e) {
    stderr.writeln(e);
    exit(64);
  }
  stdout.writeln('redefine-api starting: ${config.describe()}');

  final Store store;
  try {
    final persistence = config.persistence == 'firestore'
        ? await FirestorePersistence.connect(config)
        : MemoryPersistence();
    store = await Store.open(persistence);
  } on Exception catch (e) {
    stderr.writeln('redefine-api: cannot open the database: $e');
    exit(1);
  }

  final stripeKey = config.stripeSecretKey;
  final gateway = stripeKey == null
      ? null
      : StripeGateway(secretKey: stripeKey);
  final app = App(config: config, store: store, payments: gateway);

  try {
    ensureSettings(store);
    if (config.seedDemo &&
        await seedDemo(
          store,
          config: config,
          now: app.now(),
          sampleData: config.seedSampleData,
        )) {
      stdout.writeln('redefine-api: demo data loaded');
    }
    store.pruneExpiredSessions(app.now());
    await store.flush();
  } on StorageException catch (e) {
    stderr.writeln('redefine-api: cannot prepare the database: $e');
    exit(1);
  }

  final server = await io.serve(
    createApp(app),
    InternetAddress.anyIPv4,
    config.port,
  );
  stdout.writeln(
    'redefine-api listening on port ${server.port} '
    '(persistence ${store.persistenceKind}, '
    'payments ${gateway?.mode ?? 'manual'})',
  );
  unawaited(_sweepAtBoot(app));

  var stopping = false;
  Future<void> shutdown(ProcessSignal signal) async {
    if (stopping) return;
    stopping = true;
    stdout.writeln('redefine-api: $signal received, shutting down');
    var code = 0;
    try {
      // Let requests in flight finish, but not for longer than Cloud Run
      // waits before it kills the container.
      await server.close().timeout(
        const Duration(seconds: 5),
        onTimeout: () => server.close(force: true),
      );
      await store.close();
    } on Exception catch (e) {
      stderr.writeln('redefine-api: shutdown did not save everything: $e');
      code = 1;
    }
    gateway?.close();
    exit(code);
  }

  ProcessSignal.sigint.watch().listen(shutdown);
  // Windows has no SIGTERM; watching it there throws.
  if (!Platform.isWindows) ProcessSignal.sigterm.watch().listen(shutdown);
}

/// Cancels what went stale while the server was down. Runs beside the first
/// requests so slow card calls never delay the port opening.
Future<void> _sweepAtBoot(App app) async {
  await sweepStaleJobs(app, force: true);
  try {
    await app.store.flush();
  } on StorageException catch (e) {
    stderr.writeln('redefine-api: the boot sweep could not be saved yet: $e');
  }
}

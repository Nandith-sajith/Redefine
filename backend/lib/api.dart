import 'package:shelf/shelf.dart';

import 'src/app.dart';
import 'src/errors.dart';
import 'src/features/admin.dart';
import 'src/features/auth.dart';
import 'src/features/billing.dart';
import 'src/features/crew.dart';
import 'src/features/jobs.dart';
import 'src/features/properties.dart';
import 'src/http.dart';
import 'src/routes.dart';

export 'src/app.dart' show App;
export 'src/config.dart' show Config, ConfigError;
export 'src/features/jobs.dart' show sweepStaleJobs;

/// The Redefine API as a shelf handler.
///
/// The caller prepares [app]: an opened store with settings (and the demo
/// seed, if wanted) and the payment gateway, or none for manual mode.
Handler createApp(App app) {
  final routes = Routes();
  mountAuth(routes, app);
  mountAdmin(routes, app);
  mountProperties(routes, app);
  mountJobs(routes, app);
  mountBilling(routes, app);
  mountCrew(routes, app);

  var pipeline = const Pipeline();
  if (app.logRequests) pipeline = pipeline.addMiddleware(logRequests());
  return pipeline
      .addMiddleware(cors())
      .addMiddleware(errors(onError: (e, stack) => _report(app, e, stack)))
      .addMiddleware(routes.guard)
      .addMiddleware(auth(app.store, clock: app.now))
      .addMiddleware(autoFlush(app.store))
      .addMiddleware(_sweeper(app))
      .addHandler(routes.handler);
}

/// Starts the stale-job sweep when it is due, inside `autoFlush` so that
/// what it cancels is saved with the request. Nothing is awaited between
/// `auth` and the handler: the caller's rights are as fresh as its token.
Middleware _sweeper(App app) =>
    (inner) => (request) {
      sweepInBackground(app);
      return inner(request);
    };

void _report(App app, Object error, StackTrace stack) =>
    app.log(error is ApiError ? 'ERROR $error' : 'ERROR $error\n$stack');

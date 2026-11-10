import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import 'errors.dart';

/// The API's route table: a [Router] that also knows which method and path
/// pairs exist, so an unknown route is answered with 404 before the caller
/// is asked to authenticate.
class Routes {
  final Router _router = Router();
  final List<({String method, RegExp path})> _known = [];

  /// Registers [handler] for `GET` (and `HEAD`) [route]; `<name>` segments
  /// are passed to it as extra string arguments.
  void get(String route, Function handler) => _add('GET', route, handler);

  /// Registers [handler] for `POST` [route].
  void post(String route, Function handler) => _add('POST', route, handler);

  /// Whether a route exists for the method and path of [request].
  bool has(Request request) {
    final method = request.method == 'HEAD' ? 'GET' : request.method;
    final path = '/${request.url.path}';
    return _known.any((r) => r.method == method && r.path.hasMatch(path));
  }

  /// Rejects requests that match no route with 404 `not_found`. Place it
  /// under the `errors` middleware and above `auth`.
  Middleware get guard =>
      (inner) =>
          (request) =>
              has(request) ? inner(request) : throw ApiError.notFound('Route');

  /// Dispatches a request to its route.
  Handler get handler => _router.call;

  void _add(String method, String route, Function handler) {
    _router.add(method, route, handler);
    // The router's own rule: a `<name>` matches exactly one path segment.
    final pattern = route
        .split(RegExp('<[^>]+>'))
        .map(RegExp.escape)
        .join('[^/]+');
    _known.add((method: method, path: RegExp('^$pattern\$')));
  }
}

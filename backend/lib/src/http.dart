import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import 'auth/sessions.dart';
import 'data/persistence.dart' show StorageException;
import 'data/store.dart';
import 'errors.dart';
import 'payments/gateway.dart' show PaymentException;
import 'time.dart';

/// Largest request body [readJson] accepts.
const maxBodyBytes = 64 * 1024;

/// CORS headers present on every response.
const corsHeaders = {
  'access-control-allow-origin': '*',
  'access-control-allow-methods': 'GET, POST, PUT, PATCH, DELETE, OPTIONS',
  'access-control-allow-headers': 'Origin, Content-Type, Accept, Authorization',
  'access-control-max-age': '86400',
};

const _jsonHeaders = {'content-type': 'application/json; charset=utf-8'};
const _authKey = 'redefine.auth';
const _publicRoutes = {
  'GET health',
  'POST auth/login',
  'POST auth/signup',
  'GET billing/return',
};

/// The three account roles.
abstract final class Role {
  static const admin = 'admin';
  static const crew = 'crew';
  static const customer = 'customer';

  /// Every role.
  static const all = {admin, crew, customer};
}

// ---- responses ---------------------------------------------------------------

/// A JSON response (200 unless [status] says otherwise).
Response jsonOk(Object? body, {int status = 200}) =>
    Response(status, body: jsonEncode(body), headers: _jsonHeaders);

/// A 201 JSON response.
Response jsonCreated(Object? body) => jsonOk(body, status: 201);

/// The JSON response for [error]: its status and `{error, code, ...extra}`.
Response jsonError(ApiError error) =>
    jsonOk(error.toJson(), status: error.status);

// ---- request body ------------------------------------------------------------

/// Reads the request body as a JSON object. An empty body is `{}`; invalid
/// JSON, a non-object or more than [maxBodyBytes] is 400 `bad_request`.
Future<Map<String, dynamic>> readJson(Request request) async {
  final declared = request.contentLength;
  if (declared != null && declared > maxBodyBytes) {
    throw ApiError.badRequest('The request body is too large.');
  }
  final bytes = BytesBuilder(copy: false);
  await for (final chunk in request.read()) {
    bytes.add(chunk);
    if (bytes.length > maxBodyBytes) {
      throw ApiError.badRequest('The request body is too large.');
    }
  }
  final Object? decoded;
  try {
    final text = utf8.decode(bytes.takeBytes());
    if (text.trim().isEmpty) return {};
    decoded = jsonDecode(text);
  } on FormatException {
    throw ApiError.badRequest('The request body is not valid JSON.');
  }
  if (decoded is! Map<String, dynamic>) {
    throw ApiError.badRequest('The request body must be a JSON object.');
  }
  return decoded;
}

// ---- body field validators (all throw 400 `validation` naming the field) -----

/// A required string field, trimmed unless [trim] is false, [min]..[max]
/// characters long.
String reqString(
  Map<String, dynamic> body,
  String field, {
  int min = 1,
  required int max,
  bool trim = true,
}) {
  final raw = body[field];
  if (raw == null) throw ApiError.validation('$field is required.');
  if (raw is! String) throw ApiError.validation('$field must be text.');
  // JSON can spell half of a surrogate pair (`"\ud83d"`); the database
  // only stores valid Unicode.
  if (!isWellFormed(raw)) {
    throw ApiError.validation('$field contains invalid characters.');
  }
  final value = trim ? raw.trim() : raw;
  if (value.isEmpty && min > 0) {
    throw ApiError.validation('$field is required.');
  }
  if (value.length < min) {
    throw ApiError.validation('$field must be at least $min characters.');
  }
  if (value.length > max) {
    throw ApiError.validation('$field must be at most $max characters.');
  }
  return value;
}

/// An optional string field, trimmed, at most [max] characters; `''` when
/// absent or null.
String optString(Map<String, dynamic> body, String field, {required int max}) =>
    body[field] == null ? '' : reqString(body, field, min: 0, max: max);

/// A required email field, trimmed and lower-cased.
String reqEmail(Map<String, dynamic> body, String field) {
  final value = reqString(body, field, max: 254).toLowerCase();
  if (!_emailPattern.hasMatch(value)) {
    throw ApiError.validation('$field must be a valid email address.');
  }
  return value;
}

final _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

/// A required whole-number field within [min]..[max].
int reqInt(
  Map<String, dynamic> body,
  String field, {
  required int min,
  required int max,
}) {
  final raw = body[field];
  if (raw == null) throw ApiError.validation('$field is required.');
  final value = switch (raw) {
    int v => v,
    double v when v.isFinite && v == v.truncateToDouble() => v.toInt(),
    _ => null,
  };
  if (value == null || value < min || value > max) {
    throw ApiError.validation(
      '$field must be a whole number from $min to $max.',
    );
  }
  return value;
}

/// An optional whole-number field within [min]..[max]; null when absent.
int? optInt(
  Map<String, dynamic> body,
  String field, {
  required int min,
  required int max,
}) => body[field] == null ? null : reqInt(body, field, min: min, max: max);

/// An optional boolean field; [fallback] when absent or null.
bool optBool(Map<String, dynamic> body, String field, {bool fallback = false}) {
  final raw = body[field];
  if (raw == null) return fallback;
  if (raw is! bool) throw ApiError.validation('$field must be true or false.');
  return raw;
}

/// A required string field that must be one of [allowed].
String reqEnum(Map<String, dynamic> body, String field, Set<String> allowed) {
  final raw = body[field];
  if (raw == null) throw ApiError.validation('$field is required.');
  if (raw is! String || !allowed.contains(raw)) {
    throw ApiError.validation('$field must be one of: ${allowed.join(', ')}.');
  }
  return raw;
}

/// An optional string field that must be one of [allowed]; null when absent.
String? optEnum(Map<String, dynamic> body, String field, Set<String> allowed) =>
    body[field] == null ? null : reqEnum(body, field, allowed);

// ---- query validators (all throw 400 `validation` naming the parameter) ------

/// Query parameter [name], or null when absent or empty.
String? queryString(Request request, String name) {
  final value = request.url.queryParameters[name]?.trim();
  return value == null || value.isEmpty ? null : value;
}

/// Query parameter [name], which must be one of [allowed]; null when absent.
String? queryEnum(Request request, String name, Set<String> allowed) {
  final value = queryString(request, name);
  if (value != null && !allowed.contains(value)) {
    throw ApiError.validation('$name must be one of: ${allowed.join(', ')}.');
  }
  return value;
}

/// Comma-separated query parameter [name] (`?status=a,b`), each item one of
/// [allowed]; null when absent.
Set<String>? queryEnumSet(Request request, String name, Set<String> allowed) {
  final value = queryString(request, name);
  if (value == null) return null;
  final items = {
    for (final item in value.split(','))
      if (item.trim().isNotEmpty) item.trim(),
  };
  if (items.isEmpty || !allowed.containsAll(items)) {
    throw ApiError.validation(
      '$name must be a comma-separated list of: ${allowed.join(', ')}.',
    );
  }
  return items;
}

/// ISO-8601 timestamp query parameter [name] as UTC; null when absent.
DateTime? queryTime(Request request, String name) {
  final value = queryString(request, name);
  if (value == null) return null;
  return parseTime(value) ??
      (throw ApiError.validation('$name must be an ISO-8601 timestamp.'));
}

/// The caller's UTC offset from the `tz` query parameter (minutes east of
/// UTC, -840..840); zero when absent.
Duration tzOffset(Request request) {
  final value = queryString(request, 'tz');
  if (value == null) return Duration.zero;
  final minutes = int.tryParse(value);
  if (minutes == null || minutes < -840 || minutes > 840) {
    throw ApiError.validation(
      'tz must be a whole number of minutes from -840 to 840.',
    );
  }
  return Duration(minutes: minutes);
}

// ---- auth context ------------------------------------------------------------

/// Who is making the request; attached by the [auth] middleware.
class AuthCtx {
  /// The stored user document. It includes `passwordHash`: never return it
  /// to a client as is.
  final Doc user;

  /// Id of the session the request came in on (for logout).
  final String sessionId;

  /// The caller's customer id (role customer), else null.
  final String? customerId;

  /// The caller's crew id (role crew), else null.
  final String? crewId;

  /// `pending` | `active` | `rejected` for crew, else null.
  final String? crewStatus;

  const AuthCtx({
    required this.user,
    required this.sessionId,
    this.customerId,
    this.crewId,
    this.crewStatus,
  });

  /// The caller's user id.
  String get userId => user['id'] as String;

  /// The caller's role: one of [Role.all].
  String get role => user['role'] as String;

  /// Whether the caller is an admin.
  bool get isAdmin => role == Role.admin;

  /// Whether the caller is a crew member (in any approval state).
  bool get isCrew => role == Role.crew;

  /// Whether the caller is a customer.
  bool get isCustomer => role == Role.customer;

  /// Throws 403 `crew_pending` / `crew_rejected` unless the caller is an
  /// approved crew member (403 `forbidden` when not crew at all).
  void requireActiveCrew() {
    if (!isCrew) throw ApiError.forbidden();
    if (crewStatus == 'active') return;
    throw crewStatus == 'rejected'
        ? ApiError.crewRejected()
        : ApiError.crewPending();
  }
}

/// The caller of [request]. Throws 401 `unauthorized` when the route was
/// reached without authentication and 403 `forbidden` when [roles] is given
/// and does not contain the caller's role.
AuthCtx authOf(Request request, {Set<String>? roles}) {
  final ctx = request.context[_authKey];
  if (ctx is! AuthCtx) throw ApiError.unauthorized();
  if (roles != null && !roles.contains(ctx.role)) throw ApiError.forbidden();
  return ctx;
}

/// Whether [request] is on the contract's no-token allowlist (`HEAD` counts
/// as `GET`).
bool isPublicRoute(Request request) {
  final method = request.method == 'HEAD' ? 'GET' : request.method;
  return method == 'OPTIONS' ||
      _publicRoutes.contains('$method ${request.url.path}');
}

// ---- middleware --------------------------------------------------------------
// Pipeline order: logRequests -> cors -> errors -> auth -> autoFlush -> router.

/// Adds [corsHeaders] to every response and answers every `OPTIONS` itself.
Middleware cors() =>
    (inner) => (request) async {
      if (request.method == 'OPTIONS') {
        return jsonOk(const <String, Object?>{}).change(headers: corsHeaders);
      }
      final response = await inner(request);
      return response.change(headers: corsHeaders);
    };

/// Turns failures into JSON error responses: [ApiError] as is,
/// [StorageException] into 503 `storage_unavailable`, [PaymentException]
/// into 502 `payment_unavailable`, an unmatched route into 404 `not_found`
/// and anything else into 500 `internal`. Server-side failures are passed to
/// [onError] (default: one line plus the stack on stderr); nothing internal
/// reaches the client.
Middleware errors({void Function(Object error, StackTrace stack)? onError}) {
  final report = onError ?? _logError;
  return (inner) => (request) async {
    try {
      final response = await inner(request);
      return identical(response, Router.routeNotFound)
          ? jsonError(ApiError.notFound('Route'))
          : response;
    } on ApiError catch (e, stack) {
      if (e.status >= 500) report(e, stack);
      return jsonError(e);
    } on HijackException {
      rethrow;
    } on StorageException catch (e, stack) {
      report(e, stack);
      return jsonError(ApiError.storageUnavailable());
    } on PaymentException catch (e, stack) {
      report(e, stack);
      return jsonError(ApiError.paymentUnavailable());
    } catch (e, stack) {
      report(e, stack);
      return jsonError(ApiError.internal());
    }
  };
}

void _logError(Object error, StackTrace stack) {
  stderr.writeln('ERROR $error');
  if (error is! ApiError &&
      error is! StorageException &&
      error is! PaymentException) {
    stderr.writeln(stack);
  }
}

/// Resolves `Authorization: Bearer <token>` against the sessions in [store]
/// and attaches an [AuthCtx] (read it with [authOf]). Public routes pass
/// through untouched; a missing, unknown or expired token is 401
/// `unauthorized`. [clock] defaults to the system clock.
Middleware auth(Store store, {DateTime Function()? clock}) {
  final now = clock ?? DateTime.now;
  return (inner) => (request) {
    if (isPublicRoute(request)) return inner(request);
    final header = request.headers['authorization'] ?? '';
    final token =
        header.length > 7 && header.toLowerCase().startsWith('bearer ')
        ? header.substring(7).trim()
        : '';
    final session = token.isEmpty ? null : resolveSession(store, token, now());
    if (session == null) throw ApiError.unauthorized();

    final user = session.user;
    final linkedId = user['linkedId'] as String?;
    final isCrew = user['role'] == Role.crew;
    final crewDoc = isCrew && linkedId != null
        ? store.get(Collections.crew, linkedId)
        : null;
    final ctx = AuthCtx(
      user: user,
      sessionId: session.sessionId,
      customerId: user['role'] == Role.customer ? linkedId : null,
      crewId: isCrew ? linkedId : null,
      crewStatus: crewDoc?['status'] as String?,
    );
    return inner(request.change(context: {_authKey: ctx}));
  };
}

/// Persists what a request changed before its response is sent.
///
/// After a write request (anything but GET/HEAD) the store is flushed; if
/// that fails, or the store was reloaded underneath the request, the client
/// gets 503 `storage_unavailable` instead of the handler's response. After
/// reads, and after handlers that threw, anything dirty is flushed too, but
/// a failure there only stays queued for the next flush.
Middleware autoFlush(Store store) =>
    (inner) => (request) async {
      final epoch = store.epoch;
      final Response response;
      try {
        response = await inner(request);
      } catch (_) {
        // A handler may fail after committing part of its work (terminal-first
        // payment flows); what it committed must still reach the database.
        await _flushQuietly(store);
        rethrow;
      }
      if (request.method == 'GET' || request.method == 'HEAD') {
        await _flushQuietly(store);
        return response;
      }
      if (store.epoch != epoch) throw ApiError.storageUnavailable();
      await store.flush();
      return response;
    };

Future<void> _flushQuietly(Store store) async {
  if (!store.isDirty) return;
  try {
    await store.flush();
  } on StorageException {
    // Already logged by the store; the documents stay dirty and are retried.
  }
}

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_exception.dart';
import 'json.dart';
import 'models.dart';
import 'token_store.dart';

typedef _Json = Map<String, dynamic>;

const _unexpected = 'The server sent an unexpected response. Please try again.';

const _unreachable = ApiException(
  0,
  'network',
  "Couldn't reach the server. Check your connection and try again.",
);

/// REST client for the Redefine API.
///
/// The base URL is overridable at build time:
///   flutter run --dart-define=API_BASE_URL=http://localhost:8080
///
/// Every call fails with an [ApiException] and nothing else.
class ApiClient {
  ApiClient({
    String? baseUrl,
    http.Client? httpClient,
    TokenStore? tokenStore,
    Duration timeout = const Duration(seconds: 20),
  }) : baseUrl = _withoutTrailingSlash(
         baseUrl ??
             const String.fromEnvironment(
               'API_BASE_URL',
               defaultValue:
                   'https://redefine-api-867740771011.us-central1.run.app',
             ),
       ),
       _http = httpClient ?? http.Client(),
       _store = tokenStore ?? MemoryTokenStore(),
       _timeout = timeout,
       _paymentTimeout = timeout > _minPaymentTimeout
           ? timeout
           : _minPaymentTimeout;

  // Calls that place or capture a card hold wait on the payment provider.
  static const _minPaymentTimeout = Duration(seconds: 30);

  final String baseUrl;
  final http.Client _http;
  final TokenStore _store;
  final Duration _timeout;
  final Duration _paymentTimeout;

  String? _token;

  /// The signed-in user as of the last login, signup, restore or [me].
  AuthUser? currentUser;

  /// Whether a session token is held. It may still turn out to be expired.
  bool get isSignedIn => _token != null;

  /// Called once when the server rejects the current token. By then the
  /// session has already been cleared locally.
  void Function()? onSessionExpired;

  // ---- Session ------------------------------------------------------------

  /// Resumes the stored session. Returns null when there is none or the
  /// server no longer accepts it; rethrows other failures with the token kept
  /// so the caller can retry.
  Future<AuthUser?> restoreSession() async {
    final stored = await _readStored();
    if (stored == null || stored.isEmpty) {
      _token = null;
      currentUser = null;
      return null;
    }
    _token = stored;
    try {
      return await _fetchMe(notifyExpiry: false);
    } on ApiException catch (e) {
      if (e.statusCode == 401) return null;
      rethrow;
    }
  }

  Future<AuthResult> login(String email, String password) =>
      _authenticate('/auth/login', {'email': email, 'password': password});

  Future<AuthResult> signup({
    required String name,
    required String email,
    required String password,
    required String role,
    String? phone,
    String? inviteCode,
  }) => _authenticate('/auth/signup', {
    'name': name,
    'email': email,
    'password': password,
    'role': role,
    if (phone != null && phone.isNotEmpty) 'phone': phone,
    if (inviteCode != null && inviteCode.isNotEmpty) 'inviteCode': inviteCode,
  });

  /// Re-reads the signed-in user and updates [currentUser].
  Future<AuthUser> me() => _fetchMe(notifyExpiry: true);

  /// Ends the session locally straight away, then tells the server
  /// (best effort, at most 5 s).
  Future<void> logout() async {
    final token = _token;
    _token = null;
    currentUser = null;
    await _clearStored();
    if (token == null) return;
    try {
      await _send<_Json>(
        'POST',
        '/auth/logout',
        token: token,
        timeout: const Duration(seconds: 5),
      );
    } on ApiException {
      // The session is already gone on this device; the token expires
      // server-side on its own.
    }
  }

  // ---- Shared -------------------------------------------------------------

  Future<Settings> settings() => _get('/settings', Settings.fromJson);

  /// Customer: own properties. Admin: all, optionally filtered.
  Future<List<Property>> properties({String? customerId, String? status}) =>
      _getList(
        '/properties',
        Property.fromJson,
        query: {'customerId': customerId, 'status': status},
      );

  /// Adds a property, which opens a quote request. [customerId] is for
  /// admins, who must name the customer.
  Future<({Property property, Quote quote})> createProperty({
    required String name,
    required String address,
    String illustration = 'house',
    String note = '',
    String? customerId,
  }) => _post(
    '/properties',
    _propertyAndQuote,
    body: {
      'name': name,
      'address': address,
      if (illustration.isNotEmpty) 'illustration': illustration,
      if (note.isNotEmpty) 'note': note,
      'customerId': ?customerId,
    },
  );

  /// Asks for a fresh quote on a property whose last quote was declined.
  Future<({Property property, Quote quote})> requestQuoteAgain(
    String propertyId,
  ) =>
      _post('/properties/:id/request-quote', _propertyAndQuote, id: propertyId);

  Future<Quote> quote(String id) => _get('/quotes/:id', Quote.fromJson, id: id);

  Future<List<Quote>> quotes({String? status}) =>
      _getList('/quotes', Quote.fromJson, query: {'status': status});

  Future<({Quote quote, Property property})> acceptQuote(String id) =>
      _post('/quotes/:id/accept', _propertyAndQuote, id: id);

  Future<({Quote quote, Property property})> declineQuote(String id) =>
      _post('/quotes/:id/decline', _propertyAndQuote, id: id);

  /// Requests a plough. [payment] (`card` | `manual`) is admin-only.
  Future<Job> requestJob({
    required String propertyId,
    bool shovel = false,
    String? note,
    String? payment,
  }) => _post(
    '/jobs',
    Job.fromJson,
    body: {
      'propertyId': propertyId,
      'shovel': shovel,
      if (note != null && note.isNotEmpty) 'note': note,
      'payment': ?payment,
    },
    timeout: _paymentTimeout,
  );

  /// Customer: own jobs. Crew: [scope] `open` or `mine`. Admin: all, with the
  /// remaining filters.
  Future<List<Job>> jobs({
    String? scope,
    List<JobStatus>? status,
    String? propertyId,
    String? customerId,
    String? crewId,
    List<PaymentStatus>? payment,
    DateTime? from,
    DateTime? to,
  }) => _getList(
    '/jobs',
    Job.fromJson,
    query: {
      'scope': scope,
      'status': _csv(status, JobStatus.unknown),
      'propertyId': propertyId,
      'customerId': customerId,
      'crewId': crewId,
      'payment': _csv(payment, PaymentStatus.unknown),
      'from': from?.toUtc().toIso8601String(),
      'to': to?.toUtc().toIso8601String(),
    },
  );

  Future<Job> job(String id) => _get('/jobs/:id', Job.fromJson, id: id);

  Future<Job> cancelJob(String id) =>
      _post('/jobs/:id/cancel', Job.fromJson, id: id);

  // ---- Customer billing ---------------------------------------------------

  Future<Billing> billing() => _get('/billing', Billing.fromJson);

  /// The hosted page on which the customer saves a card.
  Future<Uri> createCardSetupSession() => _post('/billing/setup-session', (j) {
    final uri = Uri.tryParse(str(j['url']));
    if (uri == null ||
        uri.host.isEmpty ||
        !(uri.isScheme('https') || uri.isScheme('http'))) {
      throw const ApiException(200, 'bad_response', _unexpected);
    }
    return uri;
  });

  /// Re-checks a pending card setup with the payment provider.
  Future<Billing> refreshBilling() =>
      _post('/billing/refresh', Billing.fromJson);

  // ---- Crew ---------------------------------------------------------------

  Future<Job> claimJob(String id) =>
      _post('/jobs/:id/claim', Job.fromJson, id: id);

  Future<Job> unclaimJob(String id) =>
      _post('/jobs/:id/unclaim', Job.fromJson, id: id);

  Future<Job> startJob(String id) =>
      _post('/jobs/:id/start', Job.fromJson, id: id);

  Future<Job> completeJob(String id, {String? crewNote}) => _post(
    '/jobs/:id/complete',
    Job.fromJson,
    id: id,
    body: {if (crewNote != null && crewNote.isNotEmpty) 'crewNote': crewNote},
    timeout: _paymentTimeout,
  );

  /// [crewId] may be the literal `me`.
  Future<CrewPay> crewPay(String crewId) =>
      _get('/crew/:id/pay', CrewPay.fromJson, id: crewId, query: _tz());

  // ---- Admin --------------------------------------------------------------

  Future<AdminDashboard> adminDashboard() =>
      _get('/dashboard/admin', AdminDashboard.fromJson, query: _tz());

  /// Sends (or re-sends) the offer for a pending or sent quote.
  Future<Quote> sendQuote(
    String id, {
    required int price,
    required int crewPay,
  }) => _post(
    '/quotes/:id/send',
    Quote.fromJson,
    id: id,
    body: {'price': price, 'crewPay': crewPay},
  );

  /// Re-prices an active property; applies to future requests only.
  Future<Property> setPropertyPrice(
    String id, {
    required int price,
    required int crewPay,
  }) => _post(
    '/properties/:id/price',
    Property.fromJson,
    id: id,
    body: {'price': price, 'crewPay': crewPay},
  );

  Future<List<Customer>> customers() =>
      _getList('/customers', Customer.fromJson);

  Future<CustomerDetail> customer(String id) =>
      _get('/customers/:id', CustomerDetail.fromJson, id: id);

  Future<
    ({
      List<CrewMember> active,
      List<CrewMember> pending,
      List<CrewMember> rejected,
    })
  >
  crew() => _get(
    '/crew',
    (j) => (
      active: listOf(j['active'], CrewMember.fromJson),
      pending: listOf(j['pending'], CrewMember.fromJson),
      rejected: listOf(j['rejected'], CrewMember.fromJson),
    ),
    query: _tz(),
  );

  Future<CrewMember> approveCrew(String id) =>
      _post('/crew/:id/approve', CrewMember.fromJson, id: id, query: _tz());

  Future<CrewMember> rejectCrew(String id) =>
      _post('/crew/:id/reject', CrewMember.fromJson, id: id, query: _tz());

  /// Pays out the crew member's whole unpaid balance.
  Future<({Payout payout, CrewPay pay})> recordPayout(
    String crewId, {
    String? note,
  }) => _post(
    '/crew/:id/payouts',
    (j) => (
      payout: Payout.fromJson(mapOf(j['payout'])),
      pay: CrewPay.fromJson(mapOf(j['pay'])),
    ),
    id: crewId,
    query: _tz(),
    body: {if (note != null && note.isNotEmpty) 'note': note},
  );

  Future<Job> markJobPaid(String id) =>
      _post('/jobs/:id/mark-paid', Job.fromJson, id: id);

  Future<Job> retryJobPayment(String id) =>
      _post('/jobs/:id/retry-payment', Job.fromJson, id: id);

  Future<Settings> updateSettings({
    int? shovelPrice,
    int? crewShovelBonus,
    int? openJobExpiryHours,
  }) => _post(
    '/settings',
    Settings.fromJson,
    body: {
      'shovelPrice': ?shovelPrice,
      'crewShovelBonus': ?crewShovelBonus,
      'openJobExpiryHours': ?openJobExpiryHours,
    },
  );

  // ---- Plumbing -----------------------------------------------------------

  static String _withoutTrailingSlash(String url) {
    var end = url.length;
    while (end > 0 && url.codeUnitAt(end - 1) == 0x2F) {
      end--;
    }
    return url.substring(0, end);
  }

  // The caller's UTC offset, so the server's "today" and "this week" are local.
  static Map<String, String?> _tz() => {
    'tz': '${DateTime.now().timeZoneOffset.inMinutes}',
  };

  static String? _csv<T extends Enum>(List<T>? values, T unknown) =>
      values?.where((v) => v != unknown).map((v) => v.name).join(',');

  static ({Property property, Quote quote}) _propertyAndQuote(_Json j) => (
    property: Property.fromJson(mapOf(j['property'])),
    quote: Quote.fromJson(mapOf(j['quote'])),
  );

  Future<T> _get<T>(
    String route,
    T Function(_Json) parse, {
    String? id,
    Map<String, String?> query = const {},
  }) async => parse(await _send<_Json>('GET', route, id: id, query: query));

  Future<List<T>> _getList<T>(
    String route,
    T Function(_Json) parse, {
    Map<String, String?> query = const {},
  }) async =>
      listOf(await _send<List<dynamic>>('GET', route, query: query), parse);

  Future<T> _post<T>(
    String route,
    T Function(_Json) parse, {
    String? id,
    Map<String, String?> query = const {},
    _Json? body,
    Duration? timeout,
  }) async => parse(
    await _send<_Json>(
      'POST',
      route,
      id: id,
      query: query,
      body: body,
      timeout: timeout,
    ),
  );

  Future<AuthResult> _authenticate(String route, _Json body) async {
    final result = AuthResult.fromJson(
      await _send<_Json>('POST', route, body: body, auth: false),
    );
    if (result.token.isEmpty) {
      throw const ApiException(200, 'bad_response', _unexpected);
    }
    _token = result.token;
    currentUser = result.user;
    await _writeStored(result.token);
    return result;
  }

  Future<AuthUser> _fetchMe({required bool notifyExpiry}) async {
    final token = _token;
    final user = AuthUser.fromJson(
      await _send<_Json>('GET', '/auth/me', notifyExpiry: notifyExpiry),
    );
    // A sign-out or re-login may have happened while this was in flight.
    if (_token == token) currentUser = user;
    return user;
  }

  // Persistence is best effort: when the store fails the session still works
  // in memory for this run.
  Future<String?> _readStored() async {
    try {
      return await _store.read();
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeStored(String token) async {
    try {
      await _store.write(token);
    } catch (_) {}
  }

  Future<void> _clearStored() async {
    try {
      await _store.clear();
    } catch (_) {}
  }

  /// Fills the route's `:id` with the percent-encoded [id] and appends the
  /// non-empty [query] values.
  Uri _uri(String route, String? id, Map<String, String?> query) {
    var path = route;
    if (id != null) {
      // '' would address the collection and Uri resolves '.' and '..' away,
      // so none of them can name a resource.
      if (id.isEmpty || id == '.' || id == '..') {
        throw ApiException(404, 'not_found', _defaultMessage(404));
      }
      path = route.replaceFirst(':id', Uri.encodeComponent(id));
    }
    final params = <String, String>{
      for (final MapEntry(:key, :value) in query.entries)
        if (value != null && value.isNotEmpty) key: value,
    };
    // A base URL that does not parse has no server behind it.
    final uri = Uri.tryParse('$baseUrl$path');
    if (uri == null) throw _unreachable;
    return params.isEmpty ? uri : uri.replace(queryParameters: params);
  }

  /// The one place that talks HTTP. [T] is the expected top-level JSON type
  /// (object or array). [token] overrides the session token (logout sends the
  /// one it has just dropped).
  Future<T> _send<T>(
    String method,
    String route, {
    String? id,
    Map<String, String?> query = const {},
    _Json? body,
    bool auth = true,
    bool notifyExpiry = true,
    String? token,
    Duration? timeout,
  }) async {
    final sent = auth ? (token ?? _token) : null;
    if (auth && sent == null) {
      throw const ApiException(
        401,
        'unauthorized',
        'Please sign in to continue.',
      );
    }

    final request = http.Request(method, _uri(route, id, query))
      ..headers['accept'] = 'application/json';
    if (sent != null) request.headers['authorization'] = 'Bearer $sent';
    if (method == 'POST') {
      request.headers['content-type'] = 'application/json';
      request.bodyBytes = utf8.encode(jsonEncode(body ?? const {}));
    }

    final http.Response res;
    try {
      res = await _http
          .send(request)
          .then(http.Response.fromStream)
          .timeout(timeout ?? _timeout);
    } on TimeoutException {
      throw const ApiException(
        0,
        'timeout',
        'The server took too long to respond. Please try again.',
      );
    } catch (_) {
      // Errors as well as exceptions: dart:io raises an ArgumentError for a
      // base URL it cannot open (one given without its scheme, say), and
      // callers only ever handle ApiException.
      throw _unreachable;
    }

    Object? json;
    try {
      json = jsonDecode(utf8.decode(res.bodyBytes));
    } on FormatException {
      // Not JSON (an HTML error page, plain text, an empty body).
    }

    if (res.statusCode >= 200 && res.statusCode < 300) {
      if (json is T) return json;
      throw ApiException(res.statusCode, 'bad_response', _unexpected);
    }
    if (res.statusCode == 401 && sent != null) {
      await _expire(sent, notify: notifyExpiry);
    }
    throw _errorOf(res.statusCode, json);
  }

  // Only the first 401 for the current token ends the session; later ones
  // (in-flight polls, requests sent with an older token) find it changed.
  Future<void> _expire(String token, {required bool notify}) async {
    if (_token != token) return;
    _token = null;
    currentUser = null;
    // Cleared before notifying so a sign-in started from the callback cannot
    // have its new token wiped by this clear.
    await _clearStored();
    if (notify && _token == null) onSessionExpired?.call();
  }

  static ApiException _errorOf(int status, Object? json) {
    final body = json is _Json ? json : const <String, dynamic>{};
    final code = body['code'];
    final message = body['error'];
    return ApiException(
      status,
      code is String && code.isNotEmpty
          ? code
          : (status == 401 ? 'unauthorized' : 'bad_response'),
      message is String && message.trim().isNotEmpty
          ? message
          : _defaultMessage(status),
      extra: {
        for (final e in body.entries)
          if (e.key != 'error' && e.key != 'code') e.key: e.value,
      },
    );
  }

  static String _defaultMessage(int status) => switch (status) {
    400 =>
      "That request couldn't be processed. Check the details and try again.",
    401 => 'Please sign in again.',
    402 => "The payment couldn't be processed. Check your card and try again.",
    403 => "You don't have permission to do that.",
    404 => "We couldn't find that. It may have been removed.",
    409 => "That's no longer possible. Refresh and try again.",
    429 => 'Too many attempts. Wait a moment and try again.',
    502 ||
    503 ||
    504 => 'The server is temporarily unavailable. Try again in a moment.',
    _ => 'Something went wrong. Please try again.',
  };
}

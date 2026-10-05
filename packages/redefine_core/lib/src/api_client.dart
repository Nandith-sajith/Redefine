import 'dart:convert';

import 'package:http/http.dart' as http;

import 'models.dart';

/// Thin REST client for the Redefine API.
///
/// Base URL is overridable at build time:
///   flutter run --dart-define=API_BASE_URL=https://redefine-api-xxxx.run.app
class ApiClient {
  ApiClient({String? baseUrl})
      : baseUrl = baseUrl ??
            const String.fromEnvironment('API_BASE_URL',
                defaultValue: 'https://redefine-api-867740771011.us-central1.run.app');

  final String baseUrl;
  final http.Client _http = http.Client();

  /// Set after login/signup; sent as a Bearer token on subsequent requests.
  String? authToken;
  AuthUser? currentUser;

  Uri _u(String path, [Map<String, String>? q]) =>
      Uri.parse('$baseUrl$path').replace(queryParameters: q);

  Map<String, String> _headers() => {
        'content-type': 'application/json',
        if (authToken != null) 'authorization': 'Bearer $authToken',
      };

  Future<dynamic> _get(String path, [Map<String, String>? q]) async {
    final res = await _http.get(_u(path, q), headers: _headers());
    if (res.statusCode >= 400) {
      throw ApiException(res.statusCode, res.body);
    }
    return jsonDecode(res.body);
  }

  Future<dynamic> _post(String path, [Map<String, dynamic>? body]) async {
    final res = await _http.post(_u(path),
        headers: _headers(), body: jsonEncode(body ?? {}));
    if (res.statusCode >= 400) {
      throw ApiException(res.statusCode, res.body);
    }
    return jsonDecode(res.body);
  }

  List<Map<String, dynamic>> _list(dynamic v) =>
      (v as List).cast<Map<String, dynamic>>();

  // ---- Auth ---------------------------------------------------------------
  Future<AuthResult> login(String email, String password) =>
      _auth('/auth/login', {'email': email, 'password': password});

  Future<AuthResult> signup({
    required String name,
    required String email,
    required String password,
    required String role,
    String? phone,
    String? business,
  }) =>
      _auth('/auth/signup', {
        'name': name,
        'email': email,
        'password': password,
        'role': role,
        if (phone != null && phone.isNotEmpty) 'phone': phone,
        if (business != null && business.isNotEmpty) 'business': business,
      });

  Future<AuthResult> _auth(String path, Map<String, dynamic> body) async {
    try {
      final j = (await _post(path, body)) as Map<String, dynamic>;
      final result = AuthResult.fromJson(j);
      authToken = result.token;
      currentUser = result.user;
      return result;
    } on ApiException catch (e) {
      throw AuthException(_extractError(e.body));
    }
  }

  void signOut() {
    authToken = null;
    currentUser = null;
  }

  String _extractError(String body) {
    try {
      final m = jsonDecode(body);
      if (m is Map && m['error'] != null) return m['error'].toString();
    } catch (_) {}
    return 'Something went wrong. Please try again.';
  }

  // ---- Dashboard ----------------------------------------------------------
  Future<Map<String, dynamic>> adminDashboard() async =>
      (await _get('/dashboard/admin')) as Map<String, dynamic>;

  // ---- Quotes -------------------------------------------------------------
  Future<List<Quote>> quotes({String? status}) async => _list(
          await _get('/quotes', status == null ? null : {'status': status}))
      .map(Quote.fromJson)
      .toList();

  Future<Quote> quote(String id) async =>
      Quote.fromJson((await _get('/quotes/$id')) as Map<String, dynamic>);

  Future<Quote> createQuote(Map<String, dynamic> body) async =>
      Quote.fromJson((await _post('/quotes', body)) as Map<String, dynamic>);

  Future<Quote> sendQuote(String id, int biweeklyPrice) async => Quote.fromJson(
      (await _post('/quotes/$id/send', {'biweeklyPrice': biweeklyPrice}))
          as Map<String, dynamic>);

  Future<Quote> acceptQuote(String id, String plan) async => Quote.fromJson(
      (await _post('/quotes/$id/accept', {'plan': plan})) as Map<String, dynamic>);

  // ---- Crew ---------------------------------------------------------------
  Future<({List<CrewMember> active, List<CrewMember> pending})> crew() async {
    final j = (await _get('/crew')) as Map<String, dynamic>;
    return (
      active: _list(j['active']).map(CrewMember.fromJson).toList(),
      pending: _list(j['pending']).map(CrewMember.fromJson).toList(),
    );
  }

  Future<void> approveCrew(String id) async => _post('/crew/$id/approve');
  Future<void> rejectCrew(String id) async => _post('/crew/$id/reject');

  // ---- Customers ----------------------------------------------------------
  Future<({int total, int active, List<Customer> customers})> customers(
      {String? status}) async {
    final j = (await _get('/customers',
        status == null ? null : {'status': status})) as Map<String, dynamic>;
    return (
      total: (j['total'] as num).toInt(),
      active: (j['activeSubscriptions'] as num).toInt(),
      customers: _list(j['customers']).map(Customer.fromJson).toList(),
    );
  }

  Future<Map<String, dynamic>> customer(String id) async =>
      (await _get('/customers/$id')) as Map<String, dynamic>;

  Future<List<Property>> properties({String? customerId}) async => _list(
          await _get('/properties',
              customerId == null ? null : {'customerId': customerId}))
      .map(Property.fromJson)
      .toList();

  // ---- Job cards ----------------------------------------------------------
  Future<List<JobCard>> jobCards({String? status}) async => _list(
          await _get('/job-cards', status == null ? null : {'status': status}))
      .map(JobCard.fromJson)
      .toList();

  Future<JobCard> postJobCard(Map<String, dynamic> body) async =>
      JobCard.fromJson((await _post('/job-cards', body)) as Map<String, dynamic>);

  Future<List<JobCard>> pendingJobs() async =>
      _list(await _get('/pending-jobs')).map(JobCard.fromJson).toList();

  Future<JobCard> claimJob(String id, String crewId, String date, String window) async =>
      JobCard.fromJson((await _post('/job-cards/$id/claim',
          {'crewId': crewId, 'date': date, 'window': window})) as Map<String, dynamic>);

  Future<void> startJob(String id) async => _post('/job-cards/$id/start');
  Future<void> completeJob(String id) async => _post('/job-cards/$id/complete');

  // ---- Crew home / pay ----------------------------------------------------
  Future<Map<String, dynamic>> crewJobs(String crewId) async =>
      (await _get('/crew/$crewId/jobs')) as Map<String, dynamic>;
  Future<Map<String, dynamic>> crewPay(String crewId) async =>
      (await _get('/crew/$crewId/pay')) as Map<String, dynamic>;

  // ---- Visits -------------------------------------------------------------
  Future<List<Visit>> visits({String? propertyId}) async => _list(
          await _get('/visits', propertyId == null ? null : {'propertyId': propertyId}))
      .map(Visit.fromJson)
      .toList();

  Future<Visit> visit(String id) async =>
      Visit.fromJson((await _get('/visits/$id')) as Map<String, dynamic>);
}

class ApiException implements Exception {
  ApiException(this.statusCode, this.body);
  final int statusCode;
  final String body;
  @override
  String toString() => 'ApiException($statusCode): $body';
}

/// A friendly, user-facing auth failure (bad credentials, email taken, …).
class AuthException implements Exception {
  AuthException(this.message);
  final String message;
  @override
  String toString() => message;
}

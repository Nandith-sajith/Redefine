import 'dart:async';
import 'dart:convert';

import 'package:googleapis_auth/auth_io.dart' as gauth;
import 'package:http/http.dart' as http;

import '../auth/tokens.dart';
import '../config.dart';
import 'firestore_codec.dart';
import 'persistence.dart';

/// Firestore (Native mode) persistence over the REST API.
///
/// A lease document (`meta/lease`) guards against two server instances
/// writing at once: [load] takes the lease unconditionally, and every commit
/// renews it with an `updateTime` precondition. A failed precondition means
/// another instance took over and surfaces as [LeaseLostException].
class FirestorePersistence implements Persistence {
  final http.Client _client;
  final String _host;
  final String _database;
  final String _owner;
  final Duration _timeout;
  final int _pageSize;
  final int _maxWrites;

  String? _leaseTime;
  int _seq = 0;

  /// [client] must add Google credentials itself (tests pass a `MockClient`).
  /// [maxWritesPerCommit] includes the lease write.
  FirestorePersistence({
    required http.Client client,
    required String project,
    String database = '(default)',
    String? owner,
    String host = 'https://firestore.googleapis.com',
    Duration timeout = const Duration(seconds: 20),
    int pageSize = 300,
    int maxWritesPerCommit = 400,
  }) : _client = client,
       _host = host,
       _database = 'projects/$project/databases/$database',
       _owner = owner ?? newId('inst'),
       _timeout = timeout,
       _pageSize = pageSize,
       _maxWrites = maxWritesPerCommit {
    if (pageSize < 1) throw ArgumentError.value(pageSize, 'pageSize');
    if (maxWritesPerCommit < 2) {
      throw ArgumentError.value(maxWritesPerCommit, 'maxWritesPerCommit');
    }
  }

  /// Connects with Google credentials: the metadata server on Cloud Run,
  /// application-default credentials elsewhere.
  static Future<FirestorePersistence> connect(Config config) async {
    final project = config.gcpProject;
    if (project == null) {
      throw const ConfigError('GCP_PROJECT is required for Firestore.');
    }
    final client = config.onCloudRun
        ? await gauth.clientViaMetadataServer()
        : await gauth.clientViaApplicationDefaultCredentials(
            scopes: const ['https://www.googleapis.com/auth/datastore'],
          );
    return FirestorePersistence(
      client: client,
      project: project,
      database: config.firestoreDatabase,
    );
  }

  @override
  String get kind => 'firestore';

  String get _documents => '$_database/documents';
  String get _leaseName => '$_documents/meta/lease';

  @override
  Future<Map<String, Map<String, Doc>>> load() async {
    // The lease is taken before reading so nothing another instance writes
    // after our snapshot can land; it only counts once the snapshot is whole.
    _leaseTime = null;
    final lease = await _takeLease();
    final data = <String, Map<String, Doc>>{};
    for (final collection in Collections.all) {
      data[collection] = await _list(collection);
    }
    _leaseTime = lease;
    return data;
  }

  @override
  Future<void> commit(List<DocWrite> writes) async {
    final perCommit = _maxWrites - 1;
    for (var start = 0; start < writes.length; start += perCommit) {
      final lease = _leaseTime;
      if (lease == null) {
        throw const LeaseLostException('The database lease is not held.');
      }
      final end = start + perCommit > writes.length
          ? writes.length
          : start + perCommit;
      final response = await _send('commit', () {
        return _client.post(
          Uri.parse('$_host/v1/$_documents:commit'),
          headers: const {'content-type': 'application/json'},
          body: jsonEncode({
            'writes': [
              _leaseWrite(precondition: lease),
              for (final w in writes.getRange(start, end)) _encodeWrite(w),
            ],
          }),
        );
      });
      if (response.statusCode != 200) {
        final error = _FirestoreError.parse(response);
        if (error.status == 'FAILED_PRECONDITION' ||
            error.status == 'NOT_FOUND') {
          _leaseTime = null;
          throw LeaseLostException(
            'Another instance took over the database (${error.message}).',
          );
        }
        throw error.toException('commit');
      }
      _leaseTime = _leaseUpdateTime(response);
    }
  }

  @override
  Future<void> close() async => _client.close();

  Future<String> _takeLease() async {
    final response = await _send('lease', () {
      return _client.post(
        Uri.parse('$_host/v1/$_documents:commit'),
        headers: const {'content-type': 'application/json'},
        body: jsonEncode({
          'writes': [_leaseWrite()],
        }),
      );
    });
    if (response.statusCode != 200) {
      throw _FirestoreError.parse(response).toException('lease');
    }
    return _leaseUpdateTime(response);
  }

  Map<String, dynamic> _leaseWrite({String? precondition}) => {
    'update': {
      'name': _leaseName,
      // seq changes on every write so Firestore always issues a new updateTime.
      'fields': encodeFields({'owner': _owner, 'seq': ++_seq}),
    },
    if (precondition != null) 'currentDocument': {'updateTime': precondition},
  };

  Map<String, dynamic> _encodeWrite(DocWrite w) {
    final name = '$_documents/${w.collection}/${w.id}';
    final data = w.data;
    return data == null
        ? {'delete': name}
        : {
            'update': {'name': name, 'fields': encodeFields(data)},
          };
  }

  String _leaseUpdateTime(http.Response response) {
    try {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final results = body['writeResults'] as List;
      return (results.first as Map<String, dynamic>)['updateTime'] as String;
    } on Object {
      throw const StorageException(
        'Firestore commit returned no lease update time.',
      );
    }
  }

  Future<Map<String, Doc>> _list(String collection) async {
    final docs = <String, Doc>{};
    String? pageToken;
    do {
      final uri = Uri.parse('$_host/v1/$_documents/$collection').replace(
        queryParameters: {'pageSize': '$_pageSize', 'pageToken': ?pageToken},
      );
      final response = await _send('list $collection', () => _client.get(uri));
      if (response.statusCode != 200) {
        throw _FirestoreError.parse(response).toException('list $collection');
      }
      try {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        for (final raw in (body['documents'] as List?) ?? const []) {
          final document = raw as Map<String, dynamic>;
          final name = document['name'] as String;
          final id = name.substring(name.lastIndexOf('/') + 1);
          docs[id] = decodeFields(document['fields'] as Map<String, dynamic>?)
            ..['id'] = id;
        }
        final next = body['nextPageToken'] as String?;
        pageToken = next == null || next.isEmpty ? null : next;
      } on StorageException {
        rethrow;
      } on Object catch (e) {
        throw StorageException(
          'Firestore list $collection returned unreadable data: $e',
        );
      }
    } while (pageToken != null);
    return docs;
  }

  Future<http.Response> _send(
    String operation,
    Future<http.Response> Function() request,
  ) async {
    try {
      return await request().timeout(_timeout);
    } on Exception catch (e) {
      // Network failures, timeouts and token-refresh errors are all worth a retry.
      throw StorageException(
        'Firestore $operation failed: $e',
        transient: true,
      );
    }
  }
}

class _FirestoreError {
  final int httpStatus;
  final String status;
  final String message;

  _FirestoreError(this.httpStatus, this.status, this.message);

  factory _FirestoreError.parse(http.Response response) {
    var status = '';
    var message = '';
    try {
      final error =
          (jsonDecode(response.body) as Map<String, dynamic>)['error']
              as Map<String, dynamic>;
      status = error['status'] as String? ?? '';
      message = error['message'] as String? ?? '';
    } on Object {
      // Not a Google error body (e.g. a proxy page); the HTTP status has to do.
    }
    return _FirestoreError(response.statusCode, status, message);
  }

  StorageException toException(String operation) => StorageException(
    'Firestore $operation failed: HTTP $httpStatus $status $message'.trim(),
    transient: httpStatus == 409 || httpStatus == 429 || httpStatus >= 500,
    // The request itself is at fault (INVALID_ARGUMENT and the like), not
    // the service or this server's access to it.
    refused: httpStatus == 400 || httpStatus == 413,
  );
}

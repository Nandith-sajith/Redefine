import 'dart:convert';

/// A stored entity: a JSON-ready map whose `id` equals its document id.
typedef Doc = Map<String, dynamic>;

/// Names of the persisted collections.
abstract final class Collections {
  static const users = 'users';
  static const sessions = 'sessions';
  static const customers = 'customers';
  static const crew = 'crew';
  static const properties = 'properties';
  static const quotes = 'quotes';
  static const jobs = 'jobs';
  static const payouts = 'payouts';
  static const settings = 'settings';

  /// Id of the single settings document (`settings/main`).
  static const settingsId = 'main';

  /// Every collection the store loads and writes.
  static const all = [
    users,
    sessions,
    customers,
    crew,
    properties,
    quotes,
    jobs,
    payouts,
    settings,
  ];
}

/// One document write inside an atomic commit: a full replace or a delete.
class DocWrite {
  /// The collection written to.
  final String collection;

  /// The document id.
  final String id;

  /// The complete new document, or null for a delete.
  final Doc? data;

  /// Creates or replaces `collection/id` with [data].
  const DocWrite.put(this.collection, this.id, Doc this.data);

  /// Deletes `collection/id` (a no-op when it does not exist).
  const DocWrite.delete(this.collection, this.id) : data = null;

  /// Whether this write removes the document.
  bool get isDelete => data == null;

  @override
  String toString() => '${isDelete ? 'delete' : 'put'} $collection/$id';
}

/// A persistence call failed; nothing from the failed commit may be assumed
/// to be stored.
class StorageException implements Exception {
  /// What failed, for logs (never shown to clients).
  final String message;

  /// True when retrying the same call may succeed (network, 429, 5xx).
  final bool transient;

  /// True when the database refused the writes themselves, such as a
  /// document it cannot store: the same commit can never succeed.
  final bool refused;

  const StorageException(
    this.message, {
    this.transient = false,
    this.refused = false,
  });

  @override
  String toString() => 'StorageException: $message';
}

/// Another server instance took over the database; this instance must
/// [Persistence.load] again before it may write.
class LeaseLostException extends StorageException {
  const LeaseLostException(super.message);

  @override
  String toString() => 'LeaseLostException: $message';
}

/// Durable storage behind the in-memory store.
abstract interface class Persistence {
  /// `memory` or `firestore` (reported by `GET /health`).
  String get kind;

  /// Takes ownership of the database and returns every document as
  /// `collection -> id -> doc`. Throws [StorageException] on failure.
  Future<Map<String, Map<String, Doc>>> load();

  /// Applies [writes] atomically. Throws [LeaseLostException] when another
  /// instance owns the database, [StorageException] on any other failure.
  Future<void> commit(List<DocWrite> writes);

  /// Releases network resources.
  Future<void> close();
}

/// Volatile [Persistence] for local runs and tests, with failure injection.
///
/// Documents are deep-copied in and out, so several stores opened over the
/// same instance behave like separate processes sharing one database.
class MemoryPersistence implements Persistence {
  final Map<String, Map<String, Doc>> _docs = {
    for (final c in Collections.all) c: {},
  };
  int _commitFailures = 0;
  bool _commitFailuresTransient = true;
  bool _loseLease = false;
  int _loadFailures = 0;

  /// When set, every commit holding a write this accepts is refused, the
  /// way a real database refuses a document it cannot store.
  bool Function(DocWrite write)? rejectWrite;

  /// Every successful commit, oldest first.
  final List<List<DocWrite>> commits = [];

  /// Number of [commit] calls, including failed ones.
  int commitAttempts = 0;

  /// Number of successful [load] calls.
  int loadCount = 0;

  @override
  String get kind => 'memory';

  /// Makes the next [count] commits throw a [StorageException].
  void failNextCommits(int count, {bool transient = true}) {
    _commitFailures = count;
    _commitFailuresTransient = transient;
  }

  /// Makes the next commit throw a [LeaseLostException].
  void loseLeaseOnNextCommit() => _loseLease = true;

  /// Makes the next [count] loads throw a transient [StorageException].
  void failNextLoads(int count) => _loadFailures = count;

  /// A copy of the persisted `collection/id`, or null.
  Doc? doc(String collection, String id) {
    final found = _collection(collection)[id];
    return found == null ? null : _copy(found);
  }

  /// Copies of every persisted document in [collection], keyed by id.
  Map<String, Doc> docs(String collection) => {
    for (final e in _collection(collection).entries) e.key: _copy(e.value),
  };

  @override
  Future<Map<String, Map<String, Doc>>> load() async {
    if (_loadFailures > 0) {
      _loadFailures--;
      throw const StorageException('Injected load failure.', transient: true);
    }
    loadCount++;
    return {for (final c in Collections.all) c: docs(c)};
  }

  @override
  Future<void> commit(List<DocWrite> writes) async {
    commitAttempts++;
    if (_loseLease) {
      _loseLease = false;
      throw const LeaseLostException('Injected lease loss.');
    }
    if (_commitFailures > 0) {
      _commitFailures--;
      throw StorageException(
        'Injected commit failure.',
        transient: _commitFailuresTransient,
      );
    }
    if (rejectWrite case final rejects? when writes.any(rejects)) {
      throw const StorageException(
        'Injected rejection of a document.',
        refused: true,
      );
    }
    final staged = [
      for (final w in writes)
        (
          target: _collection(w.collection),
          id: w.id,
          data: w.isDelete ? null : _copy(w.data!),
        ),
    ];
    for (final s in staged) {
      if (s.data == null) {
        s.target.remove(s.id);
      } else {
        s.target[s.id] = s.data!;
      }
    }
    commits.add(List.unmodifiable(writes));
  }

  @override
  Future<void> close() async {}

  Map<String, Doc> _collection(String name) =>
      _docs[name] ?? (throw ArgumentError.value(name, 'collection'));

  static Doc _copy(Doc doc) => jsonDecode(jsonEncode(doc)) as Doc;
}

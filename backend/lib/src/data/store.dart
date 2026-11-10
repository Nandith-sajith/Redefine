import 'dart:async';
import 'dart:io';

import '../errors.dart';
import '../time.dart';
import 'persistence.dart';

export 'persistence.dart' show Collections, Doc;

/// Read access to the working copy; implemented by [Store] (committed state)
/// and [Tx] (committed state plus the transaction's own writes).
///
/// Returned documents are deeply unmodifiable. Lists are fresh and in no
/// particular order: sort them explicitly.
abstract class DocReader {
  /// The document `collection/id`, or null.
  Doc? get(String collection, String id);

  Iterable<Doc> _scan(String collection);

  /// The document `collection/id`; throws 404 `not_found` ("[what] not
  /// found.") when it does not exist.
  Doc require(String collection, String id, {String what = 'Resource'}) =>
      get(collection, id) ?? (throw ApiError.notFound(what));

  /// Every document in [collection].
  List<Doc> all(String collection) => _scan(collection).toList();

  /// The documents in [collection] that satisfy [test].
  List<Doc> where(String collection, bool Function(Doc doc) test) =>
      _scan(collection).where(test).toList();

  /// The first document in [collection] that satisfies [test], or null.
  Doc? firstWhere(String collection, bool Function(Doc doc) test) {
    for (final doc in _scan(collection)) {
      if (test(doc)) return doc;
    }
    return null;
  }

  /// Whether any document in [collection] satisfies [test].
  bool any(String collection, bool Function(Doc doc) test) =>
      firstWhere(collection, test) != null;

  /// How many documents in [collection] satisfy [test] (all when omitted).
  int count(String collection, [bool Function(Doc doc)? test]) => test == null
      ? _scan(collection).length
      : _scan(collection).where(test).length;

  /// The session stored under [tokenHash] (`{id, userId, createdAt,
  /// expiresAt}`), or null. Expiry is NOT checked here.
  Doc? session(String tokenHash) => get(Collections.sessions, tokenHash);

  /// The user whose email equals [email] (trimmed, case-insensitive), or null.
  Doc? userByEmail(String email) {
    final wanted = email.trim().toLowerCase();
    return firstWhere(
      Collections.users,
      (u) => (u['email'] as String?)?.toLowerCase() == wanted,
    );
  }

  /// The `settings/main` document, or null before it is first written.
  Doc? get settings => get(Collections.settings, Collections.settingsId);
}

/// The in-memory working copy of the whole database.
///
/// Reads never touch the network. Writes happen inside [tx] and are queued
/// for [flush], which commits them to the [Persistence] atomically.
class Store extends DocReader {
  /// The durable storage behind this store.
  final Persistence persistence;

  /// How many times a failed commit is retried within one [flush].
  final int flushRetries;

  /// Delay before the first retry; doubles on each further retry.
  final Duration retryDelay;

  final void Function(String message) _log;
  final Map<String, Map<String, Doc>> _data = {};
  Set<(String, String)> _dirty = {};
  Future<void> _flushTail = Future.value();
  bool _inTx = false;
  int _epoch = 0;

  Store._(this.persistence, this.flushRetries, this.retryDelay, this._log);

  /// Loads everything from [persistence]; throws [StorageException] when the
  /// load fails (boot must then fail fast). [log] receives storage warnings
  /// (default: stderr).
  static Future<Store> open(
    Persistence persistence, {
    int flushRetries = 3,
    Duration retryDelay = const Duration(milliseconds: 200),
    void Function(String message)? log,
  }) async {
    final store = Store._(
      persistence,
      flushRetries,
      retryDelay,
      log ?? stderr.writeln,
    );
    store._replaceAll(await persistence.load());
    return store;
  }

  /// `memory` or `firestore`.
  String get persistenceKind => persistence.kind;

  /// Whether committed changes are waiting for a [flush].
  bool get isDirty => _dirty.isNotEmpty;

  /// Number of documents waiting for a [flush].
  int get dirtyCount => _dirty.length;

  /// Incremented by every [reload]. A request that observes a change lost
  /// its unflushed writes and must fail with 503.
  int get epoch => _epoch;

  @override
  Doc? get(String collection, String id) => _collection(collection)[id];

  @override
  Iterable<Doc> _scan(String collection) => _collection(collection).values;

  /// Runs [body] as an atomic transaction and returns its result.
  ///
  /// [body] must be synchronous (never return a Future): that is what makes
  /// check-then-write atomic. Writes are applied only if [body] returns
  /// normally; if it throws, they are discarded and the error propagates.
  T tx<T>(T Function(Tx tx) body) {
    if (_inTx) throw StateError('Store.tx cannot be nested.');
    final tx = Tx._(this);
    _inTx = true;
    try {
      final result = body(tx);
      if (result is Future) {
        throw StateError('Store.tx body must be synchronous.');
      }
      tx._writes.forEach((collection, docs) {
        final target = _data[collection]!;
        docs.forEach((id, doc) {
          if (doc == null) {
            target.remove(id);
          } else {
            target[id] = doc;
          }
          _dirty.add((collection, id));
        });
      });
      return result;
    } finally {
      tx._closed = true;
      _inTx = false;
    }
  }

  /// Deletes every session whose `expiresAt` is not after [now]; returns how
  /// many were removed. Call at boot.
  int pruneExpiredSessions(DateTime now) => tx((tx) {
    final expired = tx.where(Collections.sessions, (s) {
      final expiresAt = parseTime(s['expiresAt']);
      return expiresAt == null || !expiresAt.isAfter(now);
    });
    for (final s in expired) {
      tx.delete(Collections.sessions, s['id'] as String);
    }
    return expired.length;
  });

  /// Commits every dirty document to persistence in one atomic write.
  ///
  /// Flushes run one at a time, in call order. Throws [StorageException]
  /// when the commit still fails after [flushRetries] retries (the documents
  /// stay dirty and go out with the next flush), when the database refuses
  /// the writes themselves, or when another instance took over: in the last
  /// two cases the store is reloaded and unflushed writes are gone.
  Future<void> flush() {
    final epoch = _epoch;
    final run = _flushTail.then((_) => _flushNow(epoch));
    _flushTail = run.then<void>((_) {}, onError: (_) {});
    return run;
  }

  /// Replaces the working copy with what persistence holds, dropping any
  /// unflushed writes, and bumps [epoch].
  Future<void> reload() async {
    final loaded = await persistence.load();
    _replaceAll(loaded);
    _dirty = {};
    _epoch++;
  }

  /// Flushes outstanding writes, then closes the persistence.
  Future<void> close() async {
    try {
      await flush();
    } finally {
      await persistence.close();
    }
  }

  Future<void> _flushNow(int epochAtCall) async {
    if (epochAtCall != _epoch) {
      throw const StorageException(
        'The store was reloaded before these writes were saved.',
      );
    }
    if (_dirty.isEmpty) return;
    final pending = _dirty;
    _dirty = {};
    final writes = [
      for (final (collection, id) in pending)
        switch (_data[collection]![id]) {
          null => DocWrite.delete(collection, id),
          final doc => DocWrite.put(collection, id, doc),
        },
    ];
    for (var attempt = 0; ; attempt++) {
      try {
        await persistence.commit(writes);
        return;
      } on LeaseLostException catch (e) {
        _log('storage: $e; reloading');
        try {
          await reload();
        } on StorageException catch (reloadError) {
          _dirty.addAll(pending);
          _log('storage: reload failed: $reloadError');
        }
        throw StorageException(e.message);
      } on StorageException catch (e) {
        if (e.transient && attempt < flushRetries) {
          await Future<void>.delayed(retryDelay * (1 << attempt));
          continue;
        }
        _log('storage: flush of ${writes.length} docs failed: $e');
        if (!e.refused) {
          _dirty.addAll(pending);
          rethrow;
        }
        // The database will never take this batch. Queued again it would
        // fail every later flush as well, so it is given up and memory goes
        // back to what is stored.
        _log(
          'storage: giving up the refused writes '
          '(${writes.take(20).join(', ')}); reloading',
        );
        try {
          await reload();
        } on StorageException catch (reloadError) {
          _dirty.addAll(pending);
          _log('storage: reload failed: $reloadError');
        }
        rethrow;
      }
    }
  }

  void _replaceAll(Map<String, Map<String, Doc>> loaded) {
    _data.clear();
    for (final collection in Collections.all) {
      _data[collection] = {
        for (final e in (loaded[collection] ?? const <String, Doc>{}).entries)
          e.key: freezeDoc(e.value),
      };
    }
  }

  Map<String, Doc> _collection(String name) =>
      _data[name] ??
      (throw ArgumentError.value(name, 'collection', 'Unknown collection'));
}

final _idPattern = RegExp(r'^[A-Za-z0-9_-]{1,200}$');

/// A transaction over the [Store]: reads see its own writes; nothing is
/// visible to anyone else until the body passed to [Store.tx] returns.
final class Tx extends DocReader {
  final Store _store;
  final Map<String, Map<String, Doc?>> _writes = {};
  bool _closed = false;

  Tx._(this._store);

  @override
  Doc? get(String collection, String id) {
    _check();
    final base = _store._collection(collection);
    final own = _writes[collection];
    return own != null && own.containsKey(id) ? own[id] : base[id];
  }

  @override
  Iterable<Doc> _scan(String collection) sync* {
    _check();
    final base = _store._collection(collection);
    final own = _writes[collection];
    if (own == null) {
      yield* base.values;
      return;
    }
    for (final e in base.entries) {
      final doc = own.containsKey(e.key) ? own[e.key] : e.value;
      if (doc != null) yield doc;
    }
    for (final e in own.entries) {
      final doc = e.value;
      if (doc != null && !base.containsKey(e.key)) yield doc;
    }
  }

  /// Creates or replaces `collection/doc['id']` and returns the stored
  /// (unmodifiable) document. [doc] must be JSON-ready, with an `id` of 1-200
  /// characters from `A-Z a-z 0-9 _ -`.
  Doc put(String collection, Doc doc) {
    _check();
    _store._collection(collection);
    final frozen = freezeDoc(doc);
    final id = frozen['id'];
    if (id is! String || !_idPattern.hasMatch(id)) {
      throw ArgumentError.value(id, 'doc.id', 'Not a usable document id');
    }
    (_writes[collection] ??= {})[id] = frozen;
    return frozen;
  }

  /// Like [put], but throws [StateError] when `collection/doc['id']` exists.
  Doc insert(String collection, Doc doc) {
    final id = doc['id'];
    if (id is String && get(collection, id) != null) {
      throw StateError('$collection/$id already exists.');
    }
    return put(collection, doc);
  }

  /// Applies [change] to a mutable deep copy of `collection/id`, stores the
  /// result and returns it. Throws 404 `not_found` when the document is
  /// missing.
  Doc update(
    String collection,
    String id,
    void Function(Doc draft) change, {
    String what = 'Resource',
  }) {
    final draft = copyDoc(require(collection, id, what: what));
    change(draft);
    if (draft['id'] != id) {
      throw StateError('The id of $collection/$id must not change.');
    }
    return put(collection, draft);
  }

  /// Shallow-merges [changes] into `collection/id` and returns the stored
  /// result. Throws 404 `not_found` when the document is missing.
  Doc patch(
    String collection,
    String id,
    Map<String, dynamic> changes, {
    String what = 'Resource',
  }) => update(collection, id, (draft) => draft.addAll(changes), what: what);

  /// Deletes `collection/id`; returns whether it existed.
  bool delete(String collection, String id) {
    final existed = get(collection, id) != null;
    if (existed) (_writes[collection] ??= {})[id] = null;
    return existed;
  }

  void _check() {
    if (_closed) throw StateError('This transaction has already ended.');
  }
}

/// A deeply unmodifiable copy of [doc].
///
/// Throws [ArgumentError] when it holds anything that is not JSON-ready
/// (null, bool, num, String, List, Map with string keys) or that Firestore
/// cannot store (non-finite numbers, a list directly inside a list, text
/// that is not valid Unicode).
Doc freezeDoc(Map<dynamic, dynamic> doc) => _freezeMap(doc, r'$');

/// Whether [text] is valid Unicode: every UTF-16 surrogate is half of a
/// pair. Anything else cannot be encoded as UTF-8.
bool isWellFormed(String text) {
  for (var i = 0; i < text.length; i++) {
    final unit = text.codeUnitAt(i);
    if (unit & 0xF800 != 0xD800) continue;
    final paired =
        unit < 0xDC00 &&
        i + 1 < text.length &&
        text.codeUnitAt(i + 1) & 0xFC00 == 0xDC00;
    if (!paired) return false;
    i++;
  }
  return true;
}

/// A deep, mutable copy of [doc] (for building a changed version).
Doc copyDoc(Map<dynamic, dynamic> doc) => {
  for (final e in doc.entries) e.key as String: _copy(e.value),
};

Object? _copy(Object? value) => switch (value) {
  Map v => copyDoc(v),
  List v => <dynamic>[for (final item in v) _copy(item)],
  _ => value,
};

Doc _freezeMap(Map<dynamic, dynamic> map, String path) {
  final out = <String, dynamic>{};
  for (final e in map.entries) {
    final key = e.key;
    if (key is! String) {
      throw ArgumentError.value(key, path, 'Map keys must be strings');
    }
    if (!isWellFormed(key)) {
      throw ArgumentError('A map key at $path is not valid Unicode');
    }
    out[key] = _freeze(e.value, '$path.$key');
  }
  return Map.unmodifiable(out);
}

Object? _freeze(Object? value, String path) {
  switch (value) {
    case null || bool() || int():
      return value;
    case String():
      if (!isWellFormed(value)) {
        throw ArgumentError('The text at $path is not valid Unicode');
      }
      return value;
    case double():
      if (!value.isFinite) {
        throw ArgumentError.value(value, path, 'Numbers must be finite');
      }
      return value;
    case Map():
      return _freezeMap(value, path);
    case List():
      final out = <dynamic>[];
      for (final (i, item) in value.indexed) {
        if (item is List) {
          throw ArgumentError.value(
            item,
            '$path[$i]',
            'A list directly inside a list cannot be stored',
          );
        }
        out.add(_freeze(item, '$path[$i]'));
      }
      return List<dynamic>.unmodifiable(out);
    default:
      throw ArgumentError.value(
        value,
        path,
        'Not JSON-ready (${value.runtimeType})',
      );
  }
}

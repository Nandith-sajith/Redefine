import '../data/store.dart';
import '../time.dart';
import 'tokens.dart';

/// Stores a new session for [userId] and returns its bearer token. Only the
/// token's hash is stored: `sessions/<hash> {id, userId, createdAt, expiresAt}`.
String createSession(
  Tx tx,
  String userId, {
  required DateTime now,
  required Duration ttl,
}) {
  final token = newToken();
  tx.put(Collections.sessions, {
    'id': tokenHash(token),
    'userId': userId,
    'createdAt': isoTime(now),
    'expiresAt': isoTime(now.add(ttl)),
  });
  return token;
}

/// The user that bearer [token] belongs to and the session's id (the token
/// hash), or null when the token is unknown, expired at [now], or orphaned.
({Doc user, String sessionId})? resolveSession(
  DocReader db,
  String token,
  DateTime now,
) {
  final sessionId = tokenHash(token);
  final session = db.session(sessionId);
  if (session == null) return null;
  final expiresAt = parseTime(session['expiresAt']);
  if (expiresAt == null || !expiresAt.isAfter(now)) return null;
  final userId = session['userId'];
  final user = userId is String ? db.get(Collections.users, userId) : null;
  return user == null ? null : (user: user, sessionId: sessionId);
}

/// Deletes session [sessionId] (logout); returns whether it existed.
bool revokeSession(Tx tx, String sessionId) =>
    tx.delete(Collections.sessions, sessionId);

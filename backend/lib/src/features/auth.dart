import 'package:shelf/shelf.dart';

import '../app.dart';
import '../auth/limits.dart';
import '../auth/passwords.dart';
import '../auth/sessions.dart';
import '../auth/tokens.dart';
import '../data/docs.dart';
import '../data/store.dart';
import '../errors.dart';
import '../http.dart';
import '../model.dart';
import '../routes.dart';
import 'views.dart';

const _minute = Duration(minutes: 1);

/// Health, signup, login, logout and the caller's own account.
void mountAuth(Routes r, App app) {
  final store = app.store;
  final config = app.config;
  // Failed logins per client and email; a success wipes the slate. Keyed on
  // both, so nobody can lock an account for its owner from elsewhere.
  final loginFailures = RateLimiter(max: 5, window: _minute);
  // Logins and signups per client, whatever their outcome: each one costs a
  // password hash.
  final authAttempts = RateLimiter(max: 30, window: _minute);
  final signups = RateLimiter(
    max: 10,
    window: const Duration(minutes: 10),
    message:
        'Too many accounts were created from this network. Try again in ten '
        'minutes.',
  );
  // Wrong admin invite codes, per client and from everybody together.
  final inviteGuesses = RateLimiter(max: 5, window: _minute);
  final allInviteGuesses = RateLimiter(max: 20, window: _minute);
  // Password hashing is the one CPU-heavy thing the API does for anonymous
  // callers; however many ask, the rest of the API keeps its share.
  final hashing = WorkGate(maxRunning: 2, maxWaiting: 10);
  // Verified against when the email is unknown, so that case takes as long
  // as a wrong password does. Made once, so it stays outside the gate.
  late final decoyHash = hashPassword(
    newToken(),
    iterations: config.pbkdf2Iterations,
  );

  String client(Request req) => clientKey(req, behindProxy: config.onCloudRun);

  r.get(
    '/health',
    (Request _) => jsonOk({
      'status': 'ok',
      'service': 'redefine-api',
      'persistence': store.persistenceKind,
      'payments': app.payments?.mode ?? PaymentMode.manual,
    }),
  );

  r.post('/auth/signup', (Request req) async {
    final body = await readJson(req);
    final name = reqString(body, 'name', max: 80);
    final email = reqEmail(body, 'email');
    final password = reqString(body, 'password', min: 8, max: 200, trim: false);
    final role = optEnum(body, 'role', Role.all) ?? Role.customer;
    final phone = optString(body, 'phone', max: 40);
    final inviteCode = optString(body, 'inviteCode', max: 200);

    final now = app.now();
    final from = client(req);
    if (role == Role.admin) {
      final code = config.adminInviteCode;
      if (code == null || code.isEmpty) throw ApiError.inviteRequired();
      // Checked before the code is looked at: while the limit holds, a
      // correct guess is refused like any other.
      inviteGuesses.check(from, now);
      allInviteGuesses.check('', now);
      if (!_sameText(code, inviteCode)) {
        inviteGuesses.record(from, now);
        allInviteGuesses.record('', now);
        throw ApiError.inviteRequired();
      }
    }
    authAttempts.hit(from, now);
    signups.hit(from, now);
    if (store.userByEmail(email) != null) throw ApiError.emailTaken();
    final passwordHash = await hashing.run(
      () => hashPassword(password, iterations: config.pbkdf2Iterations),
    );

    final (:token, :user) = store.tx((tx) {
      // Checked again: another signup may have finished during the hashing.
      if (tx.userByEmail(email) != null) throw ApiError.emailTaken();
      final user = tx.insert(
        Collections.users,
        userDoc(
          id: newId('user'),
          name: name,
          email: email,
          role: role,
          color:
              avatarColors[tx.count(Collections.users) % avatarColors.length],
          passwordHash: passwordHash,
          createdAt: now,
          phone: phone,
          linkedId: switch (role) {
            Role.customer => newId('cust'),
            Role.crew => newId('crew'),
            _ => null,
          },
        ),
      );
      if (role == Role.customer) {
        tx.insert(Collections.customers, customerDoc(user));
      } else if (role == Role.crew) {
        tx.insert(Collections.crew, crewDoc(user));
      }
      final token = createSession(
        tx,
        user['id'] as String,
        now: now,
        ttl: config.sessionTtl,
      );
      return (token: token, user: user);
    });
    return jsonCreated({'token': token, 'user': userView(store, user)});
  });

  r.post('/auth/login', (Request req) async {
    final body = await readJson(req);
    final email = reqString(body, 'email', max: 254).toLowerCase();
    final password = reqString(body, 'password', max: 200, trim: false);

    final now = app.now();
    final from = client(req);
    final attempt = '$from $email';
    authAttempts.hit(from, now);
    // Counted before the password is checked, so parallel guesses cannot
    // slip past the limit together.
    loginFailures.hit(attempt, now);
    final user = store.userByEmail(email);
    final stored = user?['passwordHash'] as String? ?? await decoyHash;
    final matches = await hashing.run(() => verifyPassword(password, stored));
    if (user == null || !matches) throw ApiError.invalidCredentials();
    loginFailures.clear(attempt);

    final token = store.tx(
      (tx) => createSession(
        tx,
        user['id'] as String,
        now: now,
        ttl: config.sessionTtl,
      ),
    );
    return jsonOk({'token': token, 'user': userView(store, user)});
  });

  r.post('/auth/logout', (Request req) {
    final ctx = authOf(req);
    store.tx((tx) => revokeSession(tx, ctx.sessionId));
    return jsonOk({'ok': true});
  });

  r.get('/auth/me', (Request req) => jsonOk(userView(store, authOf(req).user)));
}

/// Whether [given] equals [secret], compared in constant time.
bool _sameText(String secret, String given) {
  final a = secret.codeUnits;
  final b = given.codeUnits;
  var diff = a.length ^ b.length;
  for (var i = 0; i < a.length; i++) {
    diff |= a[i] ^ (i < b.length ? b[i] : 0);
  }
  return diff == 0;
}

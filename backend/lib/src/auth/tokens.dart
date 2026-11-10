import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

const _base32 = 'abcdefghijklmnopqrstuvwxyz234567';
final _random = Random.secure();

/// A new opaque session token: `rdf_` + base64url of 32 secure random bytes.
String newToken() {
  final bytes = [for (var i = 0; i < 32; i++) _random.nextInt(256)];
  return 'rdf_${base64Url.encode(bytes).replaceAll('=', '')}';
}

/// The id a session is stored under: the hex SHA-256 of [token].
String tokenHash(String token) => sha256.convert(utf8.encode(token)).toString();

/// A new entity id: `<prefix>_` + 12 random base32 characters (60 bits).
String newId(String prefix) {
  final buffer = StringBuffer(prefix)..write('_');
  for (var i = 0; i < 12; i++) {
    buffer.write(_base32[_random.nextInt(32)]);
  }
  return buffer.toString();
}

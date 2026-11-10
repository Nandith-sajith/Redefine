import 'dart:convert';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

const _scheme = 'pbkdf2-sha256';
const _saltLength = 16;
const _keyLength = 32;
const _maxIterations = 10000000;

/// PBKDF2-HMAC-SHA256 (RFC 8018): derives [keyLength] bytes from [password].
Uint8List pbkdf2HmacSha256(
  List<int> password,
  List<int> salt,
  int iterations,
  int keyLength,
) {
  if (iterations < 1) throw ArgumentError.value(iterations, 'iterations');
  if (keyLength < 1) throw ArgumentError.value(keyLength, 'keyLength');
  final hmac = Hmac(sha256, password);
  final out = Uint8List(keyLength);
  var offset = 0;
  for (var block = 1; offset < keyLength; block++) {
    var u = hmac.convert([
      ...salt,
      block >> 24 & 0xff,
      block >> 16 & 0xff,
      block >> 8 & 0xff,
      block & 0xff,
    ]).bytes;
    final t = Uint8List.fromList(u);
    for (var i = 1; i < iterations; i++) {
      u = hmac.convert(u).bytes;
      for (var j = 0; j < t.length; j++) {
        t[j] ^= u[j];
      }
    }
    final take = min(t.length, keyLength - offset);
    out.setRange(offset, offset + take, t);
    offset += take;
  }
  return out;
}

/// Hashes [password] off the main isolate; returns
/// `pbkdf2-sha256$<iterations>$<saltB64>$<hashB64>`.
Future<String> hashPassword(String password, {required int iterations}) async {
  if (iterations < 1 || iterations > _maxIterations) {
    throw ArgumentError.value(iterations, 'iterations');
  }
  final random = Random.secure();
  final salt = Uint8List.fromList([
    for (var i = 0; i < _saltLength; i++) random.nextInt(256),
  ]);
  final secret = utf8.encode(password);
  final key = await Isolate.run(
    () => pbkdf2HmacSha256(secret, salt, iterations, _keyLength),
  );
  return '$_scheme\$$iterations\$${base64.encode(salt)}\$${base64.encode(key)}';
}

/// Checks [password] against a hash made by [hashPassword], off the main
/// isolate and in constant time. A malformed [stored] value never matches.
Future<bool> verifyPassword(String password, String stored) async {
  final parts = stored.split(r'$');
  if (parts.length != 4 || parts[0] != _scheme) return false;
  final iterations = int.tryParse(parts[1]);
  if (iterations == null || iterations < 1 || iterations > _maxIterations) {
    return false;
  }
  final Uint8List salt;
  final Uint8List expected;
  try {
    salt = base64.decode(parts[2]);
    expected = base64.decode(parts[3]);
  } on FormatException {
    return false;
  }
  if (expected.isEmpty) return false;
  final secret = utf8.encode(password);
  final length = expected.length;
  final actual = await Isolate.run(
    () => pbkdf2HmacSha256(secret, salt, iterations, length),
  );
  var diff = 0;
  for (var i = 0; i < length; i++) {
    diff |= actual[i] ^ expected[i];
  }
  return diff == 0;
}

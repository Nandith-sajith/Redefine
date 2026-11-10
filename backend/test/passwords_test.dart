import 'dart:convert';

import 'package:redefine_api/src/auth/passwords.dart';
import 'package:test/test.dart';

String _hex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

void main() {
  group('pbkdf2HmacSha256', () {
    String derive(String password, String salt, int iterations, int length) =>
        _hex(
          pbkdf2HmacSha256(
            utf8.encode(password),
            utf8.encode(salt),
            iterations,
            length,
          ),
        );

    test('matches the RFC test vector (c=4096, dkLen=32)', () {
      expect(
        derive('password', 'salt', 4096, 32),
        'c5e478d59288c841aa530db6845c4c8d962893a001ce4e11a4963873aa98134a',
      );
    });

    test('matches the single- and double-iteration vectors', () {
      expect(
        derive('password', 'salt', 1, 32),
        '120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b',
      );
      expect(
        derive('password', 'salt', 2, 32),
        'ae4d0c95af6b46d32d0adff928f06dd02a303f8ef3c251dfd6e2d85a95474c43',
      );
    });

    test('derives keys longer than one hash block', () {
      expect(
        derive(
          'passwordPASSWORDpassword',
          'saltSALTsaltSALTsaltSALTsaltSALTsalt',
          4096,
          40,
        ),
        '348c89dbcbd32b2f32d814b8116e84cf2b17347ebc1800181c4e2a1fb8dd53e1'
        'c635518c7dac47e9',
      );
    });

    test('rejects non-positive iterations and lengths', () {
      expect(() => pbkdf2HmacSha256([1], [2], 0, 32), throwsArgumentError);
      expect(() => pbkdf2HmacSha256([1], [2], 1, 0), throwsArgumentError);
    });
  });

  group('hashPassword / verifyPassword', () {
    test('produces pbkdf2-sha256\$<iterations>\$<salt>\$<hash>', () async {
      final stored = await hashPassword('correct horse', iterations: 25);
      final parts = stored.split(r'$');
      expect(parts, hasLength(4));
      expect(parts[0], 'pbkdf2-sha256');
      expect(parts[1], '25');
      expect(base64.decode(parts[2]), hasLength(16));
      expect(base64.decode(parts[3]), hasLength(32));
    });

    test('verifies the right password and rejects a wrong one', () async {
      final stored = await hashPassword('correct horse', iterations: 25);
      expect(await verifyPassword('correct horse', stored), isTrue);
      expect(await verifyPassword('correct horsf', stored), isFalse);
      expect(await verifyPassword('', stored), isFalse);
    });

    test('salts every hash differently', () async {
      final a = await hashPassword('same', iterations: 10);
      final b = await hashPassword('same', iterations: 10);
      expect(a, isNot(b));
      expect(await verifyPassword('same', a), isTrue);
      expect(await verifyPassword('same', b), isTrue);
    });

    test('verifies with the iteration count stored in the hash', () async {
      final salt = base64.encode(utf8.encode('salt'));
      final key = base64.encode(
        pbkdf2HmacSha256(
          utf8.encode('password'),
          utf8.encode('salt'),
          4096,
          32,
        ),
      );
      expect(
        await verifyPassword('password', 'pbkdf2-sha256\$4096\$$salt\$$key'),
        isTrue,
      );
      expect(
        await verifyPassword('password', 'pbkdf2-sha256\$4095\$$salt\$$key'),
        isFalse,
      );
    });

    test('handles non-ASCII passwords', () async {
      final stored = await hashPassword('neige ❄ été', iterations: 10);
      expect(await verifyPassword('neige ❄ été', stored), isTrue);
      expect(await verifyPassword('neige ❄ ete', stored), isFalse);
    });

    test('never matches a malformed stored value', () async {
      for (final stored in [
        '',
        'plain-text',
        'sha256\$10\$c2FsdA==\$aGFzaA==',
        'pbkdf2-sha256\$0\$c2FsdA==\$aGFzaA==',
        'pbkdf2-sha256\$ten\$c2FsdA==\$aGFzaA==',
        'pbkdf2-sha256\$10\$not base64!\$aGFzaA==',
        'pbkdf2-sha256\$10\$c2FsdA==\$',
        'pbkdf2-sha256\$10\$c2FsdA==',
      ]) {
        expect(
          await verifyPassword('password', stored),
          isFalse,
          reason: stored,
        );
      }
    });

    test('rejects an unusable iteration count', () {
      expect(hashPassword('x', iterations: 0), throwsArgumentError);
    });
  });
}

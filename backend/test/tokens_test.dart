import 'package:redefine_api/src/auth/tokens.dart';
import 'package:test/test.dart';

void main() {
  test('newToken is rdf_ + 43 url-safe characters and unique', () {
    final tokens = {for (var i = 0; i < 200; i++) newToken()};
    expect(tokens, hasLength(200));
    for (final token in tokens) {
      expect(token, matches(RegExp(r'^rdf_[A-Za-z0-9_-]{43}$')));
    }
  });

  test('tokenHash is the hex SHA-256 of the token', () {
    expect(
      tokenHash('rdf_test'),
      'aaa4f4e2103c325c9a56545eeffb477bf1ec79007fe79856cabd7d155e56791d',
    );
  });

  test('newId is <prefix>_ + 12 base32 characters and unique', () {
    final ids = {for (var i = 0; i < 200; i++) newId('job')};
    expect(ids, hasLength(200));
    for (final id in ids) {
      expect(id, matches(RegExp(r'^job_[a-z2-7]{12}$')));
    }
  });
}

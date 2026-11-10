import 'dart:convert';

import 'package:redefine_api/src/data/firestore_codec.dart';
import 'package:test/test.dart';

void main() {
  group('encodeValue', () {
    test('encodes every scalar type', () {
      expect(encodeValue(null), {'nullValue': null});
      expect(encodeValue(true), {'booleanValue': true});
      expect(encodeValue('hi'), {'stringValue': 'hi'});
      expect(encodeValue(1.5), {'doubleValue': 1.5});
    });

    test('encodes integers as decimal strings', () {
      expect(encodeValue(45), {'integerValue': '45'});
      expect(encodeValue(-3), {'integerValue': '-3'});
      expect(encodeValue(9007199254740993), {
        'integerValue': '9007199254740993',
      });
    });

    test('encodes non-finite doubles as strings', () {
      expect(encodeValue(double.nan), {'doubleValue': 'NaN'});
      expect(encodeValue(double.infinity), {'doubleValue': 'Infinity'});
      expect(encodeValue(double.negativeInfinity), {
        'doubleValue': '-Infinity',
      });
    });

    test('encodes arrays and maps recursively', () {
      expect(
        encodeValue([
          1,
          'a',
          {'k': false},
        ]),
        {
          'arrayValue': {
            'values': [
              {'integerValue': '1'},
              {'stringValue': 'a'},
              {
                'mapValue': {
                  'fields': {
                    'k': {'booleanValue': false},
                  },
                },
              },
            ],
          },
        },
      );
    });

    test('omits values/fields for empty arrays and maps', () {
      expect(encodeValue(<dynamic>[]), {'arrayValue': <String, dynamic>{}});
      expect(encodeValue(<String, dynamic>{}), {
        'mapValue': <String, dynamic>{},
      });
    });

    test('rejects what Firestore cannot store', () {
      expect(() => encodeValue(DateTime(2026)), throwsArgumentError);
      expect(() => encodeValue({1: 'a'}), throwsArgumentError);
      expect(
        () => encodeValue([
          [1],
        ]),
        throwsArgumentError,
      );
    });
  });

  group('decodeValue', () {
    test('parses integerValue strings to ints', () {
      expect(decodeValue({'integerValue': '45'}), 45);
      expect(decodeValue({'integerValue': '-3'}), -3);
      expect(decodeValue({'integerValue': 7}), 7);
      expect(decodeValue({'integerValue': '45'}), isA<int>());
    });

    test('decodes doubles, including integral and non-finite ones', () {
      expect(decodeValue({'doubleValue': 1.5}), 1.5);
      expect(decodeValue({'doubleValue': 3}), isA<double>());
      expect(decodeValue({'doubleValue': 'Infinity'}), double.infinity);
      expect(
        decodeValue({'doubleValue': '-Infinity'}),
        double.negativeInfinity,
      );
      expect((decodeValue({'doubleValue': 'NaN'}) as double).isNaN, isTrue);
    });

    test('decodes empty arrays and maps without values/fields', () {
      expect(decodeValue({'arrayValue': <String, dynamic>{}}), isEmpty);
      expect(decodeValue({'arrayValue': <String, dynamic>{}}), isA<List>());
      expect(
        decodeValue({'mapValue': <String, dynamic>{}}),
        isA<Map<String, dynamic>>(),
      );
      expect(decodeValue({'mapValue': <String, dynamic>{}}), isEmpty);
    });

    test('rejects malformed and unsupported values', () {
      expect(
        () => decodeValue({'timestampValue': '2026-01-01T00:00:00Z'}),
        throwsFormatException,
      );
      expect(() => decodeValue({}), throwsFormatException);
      expect(() => decodeValue({'doubleValue': 'big'}), throwsFormatException);
    });
  });

  group('fields', () {
    final job = <String, dynamic>{
      'id': 'job_abc',
      'propertyId': 'prop_maple',
      'shovel': true,
      'price': 45,
      'shovelPrice': 20,
      'total': 65,
      'crewId': null,
      'note': 'Gate code 1234 — "back" lane',
      'requestedAt': '2026-01-05T12:00:00.000Z',
      'payment': {
        'mode': 'stripe',
        'status': 'authorized',
        'error': null,
        'paymentIntentId': 'pi_1',
      },
      'tags': <dynamic>[],
      'meta': <String, dynamic>{},
      'history': [
        {'at': '2026-01-05T12:00:00.000Z', 'status': 'open'},
      ],
      'rating': 4.5,
    };

    test('round-trips a document unchanged', () {
      expect(decodeFields(encodeFields(job)), job);
    });

    test('round-trips through the JSON wire format with exact types', () {
      final wire = jsonDecode(jsonEncode(encodeFields(job)));
      final decoded = decodeFields(wire as Map<String, dynamic>);
      expect(decoded, job);
      expect(decoded['price'], isA<int>());
      expect(decoded['rating'], isA<double>());
      expect(decoded['payment'], isA<Map<String, dynamic>>());
      expect(decoded['tags'], isA<List>());
    });

    test('decodes a document as Firestore returns it', () {
      final fields =
          jsonDecode('''
        {
          "name": {"stringValue": "Maple Street home"},
          "price": {"integerValue": "45"},
          "active": {"booleanValue": true},
          "quoteId": {"nullValue": null},
          "empty": {"arrayValue": {}},
          "nested": {"mapValue": {"fields": {"n": {"integerValue": "1"}}}},
          "blank": {"mapValue": {}}
        }''')
              as Map<String, dynamic>;
      expect(decodeFields(fields), {
        'name': 'Maple Street home',
        'price': 45,
        'active': true,
        'quoteId': null,
        'empty': <dynamic>[],
        'nested': {'n': 1},
        'blank': <String, dynamic>{},
      });
    });

    test('decodes a document without fields as empty', () {
      expect(decodeFields(null), <String, dynamic>{});
    });
  });
}

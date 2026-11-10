/// Converts between JSON-ready documents and Firestore's typed REST `Value`s.
library;

/// Encodes a document as a Firestore `fields` map.
Map<String, dynamic> encodeFields(Map<String, dynamic> doc) => {
  for (final e in doc.entries) e.key: encodeValue(e.value),
};

/// Encodes one JSON-ready value as a Firestore `Value`.
///
/// Throws [ArgumentError] for anything Firestore cannot hold (non-JSON
/// objects, non-string map keys, an array directly inside an array).
Map<String, dynamic> encodeValue(Object? value) => switch (value) {
  null => {'nullValue': null},
  bool v => {'booleanValue': v},
  int v => {'integerValue': v.toString()},
  double v => {'doubleValue': _encodeDouble(v)},
  String v => {'stringValue': v},
  List v => {
    'arrayValue': {
      if (v.isNotEmpty) 'values': [for (final item in v) _encodeItem(item)],
    },
  },
  Map v => {
    'mapValue': {
      if (v.isNotEmpty)
        'fields': {
          for (final e in v.entries) _key(e.key): encodeValue(e.value),
        },
    },
  },
  _ => throw ArgumentError.value(
    value,
    'value',
    'Not storable in Firestore (${value.runtimeType})',
  ),
};

/// Decodes a Firestore `fields` map (absent on an empty document).
Map<String, dynamic> decodeFields(Map<String, dynamic>? fields) => {
  if (fields != null)
    for (final e in fields.entries)
      e.key: decodeValue(e.value as Map<String, dynamic>),
};

/// Decodes one Firestore `Value`; throws [FormatException] for value types
/// this server never writes.
Object? decodeValue(Map<String, dynamic> value) {
  if (value.length != 1) {
    throw FormatException('Malformed Firestore value: $value');
  }
  final MapEntry(key: type, value: raw) = value.entries.single;
  switch (type) {
    case 'nullValue':
      return null;
    case 'booleanValue':
      return raw as bool;
    case 'integerValue':
      return raw is int ? raw : int.parse(raw as String);
    case 'doubleValue':
      return _decodeDouble(raw);
    case 'stringValue':
      return raw as String;
    case 'arrayValue':
      final values = (raw as Map<String, dynamic>)['values'] as List?;
      return <dynamic>[
        if (values != null)
          for (final item in values) decodeValue(item as Map<String, dynamic>),
      ];
    case 'mapValue':
      return decodeFields(
        (raw as Map<String, dynamic>)['fields'] as Map<String, dynamic>?,
      );
    default:
      throw FormatException('Unsupported Firestore value type "$type".');
  }
}

Map<String, dynamic> _encodeItem(Object? item) {
  if (item is List) {
    throw ArgumentError.value(
      item,
      'value',
      'Firestore cannot store an array directly inside an array',
    );
  }
  return encodeValue(item);
}

String _key(Object? key) => key is String
    ? key
    : throw ArgumentError.value(key, 'key', 'Map keys must be strings');

Object _encodeDouble(double v) {
  if (v.isNaN) return 'NaN';
  if (v.isInfinite) return v.isNegative ? '-Infinity' : 'Infinity';
  return v;
}

double _decodeDouble(Object? raw) => switch (raw) {
  num n => n.toDouble(),
  'NaN' => double.nan,
  'Infinity' => double.infinity,
  '-Infinity' => double.negativeInfinity,
  _ => throw FormatException('Malformed Firestore doubleValue: $raw'),
};

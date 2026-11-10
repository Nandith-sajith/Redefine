// Tolerant JSON readers: a missing or wrongly-typed value yields a default,
// never a throw, so one bad field cannot take a whole screen down.

String str(Object? v, [String d = '']) => v is String ? v : d;

String? strOrNull(Object? v) => v is String ? v : null;

int intOf(Object? v, [int d = 0]) => intOrNull(v) ?? d;

// isFinite: toInt() throws on NaN and infinity.
int? intOrNull(Object? v) => v is num && v.isFinite ? v.toInt() : null;

bool boolOf(Object? v) => v == true;

/// Parses an ISO-8601 timestamp into the device's local time.
DateTime? dateOrNull(Object? v) =>
    v is String ? DateTime.tryParse(v)?.toLocal() : null;

Map<String, dynamic> mapOf(Object? v) {
  if (v is Map<String, dynamic>) return v;
  if (v is Map) {
    return {
      for (final e in v.entries)
        if (e.key is String) e.key as String: e.value,
    };
  }
  return const <String, dynamic>{};
}

/// Maps every object in a JSON array through [f]; non-object items are skipped.
List<T> listOf<T>(Object? v, T Function(Map<String, dynamic>) f) => [
  if (v is List)
    for (final e in v)
      if (e is Map) f(mapOf(e)),
];

List<String> strList(Object? v) => [
  if (v is List)
    for (final e in v)
      if (e is String) e,
];

/// Matches [v] against the enum's `.name`; anything else is [fallback].
T enumOf<T extends Enum>(List<T> values, Object? v, T fallback) {
  if (v is String) {
    for (final e in values) {
      if (e.name == v) return e;
    }
  }
  return fallback;
}

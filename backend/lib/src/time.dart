/// [time] as the API's timestamp format: ISO-8601 UTC, millisecond
/// precision, ending in `Z`. Strings in this format sort chronologically.
String isoTime(DateTime time) => DateTime.fromMillisecondsSinceEpoch(
  time.millisecondsSinceEpoch,
  isUtc: true,
).toIso8601String();

/// Parses an ISO-8601 timestamp to a UTC [DateTime]; null when [value] is
/// not a parseable string.
DateTime? parseTime(Object? value) =>
    value is String ? DateTime.tryParse(value)?.toUtc() : null;

/// The UTC instant at which the caller's local day containing [now] began.
/// [tz] is the caller's offset east of UTC.
DateTime localDayStart(DateTime now, Duration tz) {
  final local = now.toUtc().add(tz);
  return DateTime.utc(local.year, local.month, local.day).subtract(tz);
}

/// The UTC instant at which the caller's local week (Monday 00:00)
/// containing [now] began. [tz] is the caller's offset east of UTC.
DateTime localWeekStart(DateTime now, Duration tz) {
  final local = now.toUtc().add(tz);
  return DateTime.utc(
    local.year,
    local.month,
    local.day - (local.weekday - DateTime.monday),
  ).subtract(tz);
}

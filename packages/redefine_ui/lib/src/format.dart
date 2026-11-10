// Display formatting for money, dates and durations. Dates are shown in the
// device's local time.

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

String _two(int n) => n.toString().padLeft(2, '0');

/// Whole dollars: `$45`, `$1,250`, `-$20`.
String money(int dollars) {
  final digits = dollars.abs().toString();
  final grouped = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) grouped.write(',');
    grouped.write(digits[i]);
  }
  return '${dollars < 0 ? '-' : ''}\$$grouped';
}

/// `Today`, `Yesterday`, `Oct 2`, or `Oct 2, 2025` outside the current year.
String fmtDay(DateTime date) {
  final d = date.toLocal();
  final now = DateTime.now();
  // Calendar days apart, immune to daylight-saving shifts.
  final daysAgo = DateTime.utc(
    now.year,
    now.month,
    now.day,
  ).difference(DateTime.utc(d.year, d.month, d.day)).inDays;
  if (daysAgo == 0) return 'Today';
  if (daysAgo == 1) return 'Yesterday';
  final day = '${_months[d.month - 1]} ${d.day}';
  return d.year == now.year ? day : '$day, ${d.year}';
}

/// `9:42 am`.
String fmtTime(DateTime date) {
  final d = date.toLocal();
  final hour = d.hour % 12 == 0 ? 12 : d.hour % 12;
  return '$hour:${_two(d.minute)} ${d.hour < 12 ? 'am' : 'pm'}';
}

/// `Oct 2, 9:42 am` (the day as in [fmtDay], so also `Today, 9:42 am`).
String fmtDayTime(DateTime date) => '${fmtDay(date)}, ${fmtTime(date)}';

/// `just now`, `6 min ago`, `2 h ago`, `3 days ago`.
String fmtAgo(DateTime date, {DateTime? now}) {
  final elapsed = (now ?? DateTime.now()).difference(date);
  if (elapsed.inMinutes < 1) return 'just now';
  if (elapsed.inHours < 1) return '${elapsed.inMinutes} min ago';
  if (elapsed.inDays < 1) return '${elapsed.inHours} h ago';
  return elapsed.inDays == 1 ? '1 day ago' : '${elapsed.inDays} days ago';
}

/// How long something took: `47 min`, `1 h 05 min`, or `< 1 min`.
String fmtDuration(Duration duration) {
  final minutes = duration.isNegative ? 0 : duration.inMinutes;
  if (minutes < 1) return '< 1 min';
  if (minutes < 60) return '$minutes min';
  return '${minutes ~/ 60} h ${_two(minutes % 60)} min';
}

/// A running clock: `18 min` under an hour, then `1:05:22`.
String fmtElapsed(Duration duration) {
  final seconds = duration.isNegative ? 0 : duration.inSeconds;
  if (seconds < 3600) return '${seconds ~/ 60} min';
  return '${seconds ~/ 3600}:${_two(seconds % 3600 ~/ 60)}:${_two(seconds % 60)}';
}

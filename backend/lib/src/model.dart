/// The contract's enumerations and the small pure rules shared by the
/// features, the views and the seed.
library;

/// The API's only currency.
const currency = 'cad';

/// Avatar colour keys, handed out round-robin at signup.
const avatarColors = ['lime', 'teal', 'paper'];

/// Property illustration keys; the first is the default.
const illustrations = {
  'house',
  'bungalow',
  'townhouse',
  'cabin',
  'duplex',
  'farmhouse',
  'cottage',
  'apartment',
  'garage',
};

abstract final class CrewStatus {
  static const pending = 'pending';
  static const active = 'active';
  static const rejected = 'rejected';
}

abstract final class PropertyStatus {
  static const quoteRequested = 'quoteRequested';
  static const quoted = 'quoted';
  static const active = 'active';
  static const declined = 'declined';
  static const all = {quoteRequested, quoted, active, declined};
}

abstract final class QuoteStatus {
  static const pending = 'pending';
  static const sent = 'sent';
  static const accepted = 'accepted';
  static const declined = 'declined';
  static const all = {pending, sent, accepted, declined};
}

abstract final class JobStatus {
  static const open = 'open';
  static const claimed = 'claimed';
  static const inProgress = 'inProgress';
  static const done = 'done';
  static const cancelled = 'cancelled';
  static const all = {open, claimed, inProgress, done, cancelled};

  /// A property may have only one job in these states.
  static const unfinished = {open, claimed, inProgress};
}

abstract final class PaymentMode {
  static const stripe = 'stripe';
  static const manual = 'manual';
}

abstract final class PaymentStatus {
  static const none = 'none';
  static const authorized = 'authorized';
  static const captured = 'captured';
  static const released = 'released';
  static const failed = 'failed';
  static const due = 'due';
  static const paid = 'paid';
  static const all = {none, authorized, captured, released, failed, due, paid};

  /// Money the customer has paid.
  static const billed = {captured, paid};

  /// Money the customer still owes.
  static const outstanding = {due, failed};

  /// What the customer's billing history lists.
  static const charges = {authorized, captured, failed, due, paid};
}

/// How long a card hold is shown as valid; the card networks drop holds
/// after about a week.
const holdLifetime = Duration(days: 4, hours: 18);

/// Initials for an avatar: first letters of the first and last word, or the
/// first two letters of a single word.
String initialsOf(String name) {
  final words = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
  if (words.isEmpty) return '';
  String head(String word, int count) =>
      String.fromCharCodes(word.runes.take(count)).toUpperCase();
  return words.length == 1
      ? head(words.first, 2)
      : head(words.first, 1) + head(words.last, 1);
}

/// Sorts [docs] by the ISO timestamp stored under [field], oldest first
/// (newest first when [descending]); documents without one sort as oldest,
/// ties are broken by id so the order is stable across reloads.
void sortByTime(
  List<Map<String, dynamic>> docs,
  String field, {
  bool descending = false,
}) => sortByKey(docs, (d) => d[field] as String? ?? '', descending: descending);

/// Sorts [docs] by [key], ascending unless [descending]; ties by id.
void sortByKey(
  List<Map<String, dynamic>> docs,
  String Function(Map<String, dynamic> doc) key, {
  bool descending = false,
}) {
  docs.sort((a, b) {
    final byKey = key(a).compareTo(key(b));
    final order = byKey != 0
        ? byKey
        : (a['id'] as String).compareTo(b['id'] as String);
    return descending ? -order : order;
  });
}

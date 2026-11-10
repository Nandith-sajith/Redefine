import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:shelf/shelf.dart';

import '../errors.dart';

/// Allows [max] hits per key per [window], in memory.
class RateLimiter {
  final int max;
  final Duration window;

  /// What a refused caller is told, when the default does not fit [window].
  final String? message;
  final Map<String, List<DateTime>> _hits = {};

  RateLimiter({required this.max, required this.window, this.message});

  /// Throws 429 `rate_limited` when [key] has used up its hits at [now].
  void check(String key, DateTime now) {
    final hits = _hits[key];
    if (hits == null) return;
    final cutoff = now.subtract(window);
    hits.removeWhere((t) => !t.isAfter(cutoff));
    if (hits.length >= max) throw ApiError.rateLimited(message);
  }

  /// Counts one hit for [key] at [now].
  void record(String key, DateTime now) {
    if (_hits.length > 10000) {
      final cutoff = now.subtract(window);
      _hits.removeWhere(
        (_, times) => times.isEmpty || !times.last.isAfter(cutoff),
      );
    }
    (_hits[key] ??= []).add(now);
  }

  /// [check], then [record]. Call it before the work it guards, so parallel
  /// requests cannot slip past the limit together.
  void hit(String key, DateTime now) {
    check(key, now);
    record(key, now);
  }

  /// Forgets the hits of [key].
  void clear(String key) => _hits.remove(key);
}

/// Runs at most [maxRunning] jobs at a time and lets at most [maxWaiting]
/// more wait their turn, first come first served.
class WorkGate {
  final int maxRunning;
  final int maxWaiting;
  final Queue<Completer<void>> _waiting = Queue();
  int _running = 0;

  WorkGate({required this.maxRunning, required this.maxWaiting});

  /// Runs [job] when a slot is free; throws 429 `rate_limited` at once when
  /// the waiting line is full.
  Future<T> run<T>(Future<T> Function() job) async {
    if (_running < maxRunning) {
      _running++;
    } else {
      if (_waiting.length >= maxWaiting) throw ApiError.rateLimited();
      final turn = Completer<void>();
      _waiting.add(turn);
      // Whoever finishes hands its slot over, so the count stays as it is.
      await turn.future;
    }
    try {
      return await job();
    } finally {
      if (_waiting.isEmpty) {
        _running--;
      } else {
        _waiting.removeFirst().complete();
      }
    }
  }
}

/// Who sent [request], as a rate-limiting key: the client's IP address, with
/// IPv6 addresses cut to their /64 network (one subscriber owns all of it).
///
/// With [behindProxy] (Cloud Run) the address is the last entry of
/// `X-Forwarded-For`: the front end appends the address it saw to whatever
/// the client sent, so the earlier entries cannot be trusted. Otherwise it
/// is the socket's remote address. `unknown` when there is neither.
String clientKey(Request request, {required bool behindProxy}) {
  String? address;
  if (behindProxy) {
    address = request.headers['x-forwarded-for']?.split(',').last.trim();
  }
  if (address == null || address.isEmpty) {
    final connection = request.context['shelf.io.connection_info'];
    if (connection is! HttpConnectionInfo) return 'unknown';
    address = connection.remoteAddress.address;
  }
  final ip = InternetAddress.tryParse(address);
  if (ip == null) return 'unknown';
  if (ip.type != InternetAddressType.IPv6) return ip.address;
  final raw = ip.rawAddress;
  // An IPv4 client seen through a dual-stack socket (::ffff:a.b.c.d).
  if (raw.take(10).every((byte) => byte == 0) &&
      raw[10] == 0xff &&
      raw[11] == 0xff) {
    return raw.skip(12).join('.');
  }
  final network = raw
      .take(8)
      .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join();
  return '$network/64';
}

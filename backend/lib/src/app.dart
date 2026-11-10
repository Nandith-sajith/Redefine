import 'dart:io';

import 'config.dart';
import 'data/store.dart';
import 'model.dart';
import 'payments/gateway.dart';

/// Everything a request handler needs: configuration, data, payments, time.
class App {
  final Config config;
  final Store store;

  /// Card payments; null when the server runs in manual mode.
  final PaymentGateway? payments;

  /// Whether `createApp` logs one line per request to stdout.
  final bool logRequests;

  final DateTime Function() _clock;
  final void Function(String message) _log;

  /// Properties with a card hold being placed for a new job. A second
  /// request for the same property must wait for the first to finish.
  final Set<String> busyProperties = {};

  /// Jobs with a capture, charge or release in flight. Whoever adds the id
  /// owns that job's payment until it removes the id again.
  final Set<String> busyJobs = {};

  /// When the stale-job sweep last started.
  DateTime? lastSweepAt;

  /// [clock] defaults to the system clock and [log] to stderr.
  App({
    required this.config,
    required this.store,
    this.payments,
    this.logRequests = true,
    DateTime Function()? clock,
    void Function(String message)? log,
  }) : _clock = clock ?? DateTime.now,
       _log = log ?? stderr.writeln;

  /// The current time in UTC.
  DateTime now() => _clock().toUtc();

  /// Server-side diagnostics. Never pass secrets, tokens or card data.
  void log(String message) => _log(message);

  /// `stripe` or `manual`: how new customer requests are paid.
  String get paymentsMode =>
      payments == null ? PaymentMode.manual : PaymentMode.stripe;
}

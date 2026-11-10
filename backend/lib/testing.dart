/// What tests in other packages need to run the real API in-process:
/// build an [App] over a [MemoryPersistence] (and a [FakePaymentGateway]
/// for card payments), seed it and serve [createApp].
library;

export 'api.dart' show App, Config, createApp, sweepStaleJobs;
export 'src/data/persistence.dart' show Collections, MemoryPersistence;
export 'src/data/seed.dart' show ensureSettings, seedDemo;
export 'src/data/store.dart' show Store;
export 'src/payments/fake_gateway.dart';
export 'src/payments/gateway.dart' show PaymentOutcome;

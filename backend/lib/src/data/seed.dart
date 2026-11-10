import '../auth/passwords.dart';
import '../config.dart';
import '../http.dart' show Role;
import '../model.dart';
import '../time.dart';
import 'docs.dart';
import 'store.dart';

/// Settings a new database starts with.
const defaultSettings = {
  'shovelPrice': 20,
  'crewShovelBonus': 10,
  'openJobExpiryHours': 48,
};

/// Writes `settings/main` with [defaultSettings] unless it already exists.
void ensureSettings(Store store) => store.tx(_settings);

Doc _settings(Tx tx) =>
    tx.settings ??
    tx.put(Collections.settings, {
      'id': Collections.settingsId,
      ...defaultSettings,
    });

/// Loads the three demo accounts (Lia, Marcus, Sarah) into an empty
/// database and, with [sampleData], the sample properties, jobs and extra
/// accounts the tests work with; does nothing (and returns false) once any
/// user exists. Every demo account gets [Config.demoPassword]; timestamps
/// are relative to [now].
Future<bool> seedDemo(
  Store store, {
  required Config config,
  required DateTime now,
  bool sampleData = false,
}) async {
  if (store.count(Collections.users) > 0) return false;
  final passwordHash = await hashPassword(
    config.demoPassword,
    iterations: config.pbkdf2Iterations,
  );
  return store.tx((tx) {
    if (tx.count(Collections.users) > 0) return false;
    _Seeder(tx, now.toUtc(), passwordHash).run(sampleData: sampleData);
    return true;
  });
}

class _Seeder {
  final Tx tx;
  final DateTime now;
  final String passwordHash;
  late final Doc settings = _settings(tx);

  _Seeder(this.tx, this.now, this.passwordHash);

  void run({required bool sampleData}) {
    accounts();
    if (sampleData) sample();
  }

  /// The sign-in accounts every deployment starts with: one per role.
  void accounts() {
    account(
      'lia',
      'Lia Robinson',
      'lia@redefine.co',
      Role.admin,
      color: 0,
      daysAgo: 60,
    );
    account(
      'marcus',
      'Marcus Reid',
      'marcus@redefine.co',
      Role.crew,
      color: 1,
      phone: '(807) 555-0111',
      crewStatus: CrewStatus.active,
      daysAgo: 45,
    );
    account(
      'sarah',
      'Sarah Mitchell',
      'sarah.m@gmail.com',
      Role.customer,
      color: 4,
      phone: '(807) 555-0142',
      daysAgo: 21,
    );
  }

  /// Extra accounts, properties, quotes and jobs for tests and local
  /// development; never loaded into a real database.
  void sample() {
    account(
      'jordan',
      'Jordan Park',
      'jordan@redefine.co',
      Role.crew,
      color: 2,
      phone: '(807) 555-0127',
      crewStatus: CrewStatus.active,
      daysAgo: 38,
    );
    account(
      'tasha',
      'Tasha Rivera',
      'tasha@redefine.co',
      Role.crew,
      color: 3,
      phone: '(807) 555-0164',
      crewStatus: CrewStatus.pending,
      daysAgo: 1,
    );
    account(
      'anna',
      'Anna Tomlinson',
      'anna.t@gmail.com',
      Role.customer,
      color: 5,
      daysAgo: 14,
    );
    account(
      'paul',
      'Paul Larson',
      'paul.l@gmail.com',
      Role.customer,
      color: 6,
      daysAgo: 2,
    );

    final maple = property(
      'maple',
      'sarah',
      'Maple Street home',
      '412 Maple St, Thunder Bay, ON',
      'house',
      created: ago(days: 21),
      sent: ago(days: 20, hours: 6),
      accepted: ago(days: 20),
      price: 45,
      crewPay: 25,
    );
    property(
      'cabin',
      'sarah',
      'Cabin',
      '88 Lakeside Rd, Thunder Bay, ON',
      'cabin',
      note: 'Long gravel driveway, about 60 m from the road to the cabin.',
      created: ago(hours: 3),
    );
    final cedar = property(
      'cedar',
      'anna',
      'Cedar Ave home',
      '78 Cedar Ave, Thunder Bay, ON',
      'bungalow',
      created: ago(days: 14),
      sent: ago(days: 13, hours: 4),
      accepted: ago(days: 13),
      price: 55,
      crewPay: 30,
    );
    property(
      'birch',
      'paul',
      'Birch Road home',
      '21 Birch Rd, Thunder Bay, ON',
      'townhouse',
      note: 'Double driveway, please keep the snow off the hedge.',
      created: ago(days: 2),
      sent: ago(days: 1),
      price: 60,
      crewPay: 35,
    );

    tx.insert(
      Collections.payouts,
      payoutDoc(
        id: 'payout_1',
        crewId: 'crew_marcus',
        amount: 35,
        jobCount: 1,
        paidAt: ago(days: 14),
        note: 'e-transfer',
      ),
    );
    doneJob(
      'job_maple_1',
      maple,
      'crew_marcus',
      completed: ago(days: 16),
      shovel: true,
      paid: true,
      payoutId: 'payout_1',
    );
    doneJob(
      'job_maple_2',
      maple,
      'crew_marcus',
      completed: ago(days: 9),
      paid: true,
    );
    doneJob(
      'job_maple_3',
      maple,
      'crew_marcus',
      completed: ago(days: 2),
      paid: true,
    );
    doneJob(
      'job_cedar_1',
      cedar,
      'crew_jordan',
      completed: ago(days: 3),
      paid: false,
    );
    tx.insert(
      Collections.jobs,
      jobDoc(
        id: 'job_cedar_2',
        property: cedar,
        settings: settings,
        shovel: true,
        note: 'Please clear the path to the side door too.',
        source: 'customer',
        requestedAt: ago(minutes: 10),
        payment: manualPayment(),
      ),
    );
  }

  DateTime ago({int days = 0, int hours = 0, int minutes = 0}) =>
      now.subtract(Duration(days: days, hours: hours, minutes: minutes));

  void account(
    String key,
    String name,
    String email,
    String role, {
    required int color,
    required int daysAgo,
    String phone = '',
    String crewStatus = CrewStatus.pending,
  }) {
    final user = tx.insert(
      Collections.users,
      userDoc(
        id: 'user_$key',
        name: name,
        email: email,
        role: role,
        color: avatarColors[color % avatarColors.length],
        passwordHash: passwordHash,
        createdAt: ago(days: daysAgo),
        phone: phone,
        linkedId: switch (role) {
          Role.customer => 'cust_$key',
          Role.crew => 'crew_$key',
          _ => null,
        },
      ),
    );
    if (role == Role.customer) {
      tx.insert(Collections.customers, customerDoc(user));
    } else if (role == Role.crew) {
      tx.insert(Collections.crew, crewDoc(user, status: crewStatus));
    }
  }

  /// A property and its quote: pending, sent ([sent] set) or accepted
  /// ([accepted] set as well).
  Doc property(
    String key,
    String customerKey,
    String name,
    String address,
    String illustration, {
    required DateTime created,
    String note = '',
    DateTime? sent,
    DateTime? accepted,
    int? price,
    int? crewPay,
  }) {
    final base = propertyDoc(
      id: 'prop_$key',
      customerId: 'cust_$customerKey',
      name: name,
      address: address,
      illustration: illustration,
      note: note,
      quoteId: 'quote_$key',
      createdAt: created,
    );
    tx.insert(Collections.quotes, {
      ...quoteDoc(id: 'quote_$key', property: base, createdAt: created),
      'status': accepted != null
          ? QuoteStatus.accepted
          : sent != null
          ? QuoteStatus.sent
          : QuoteStatus.pending,
      'price': price,
      'crewPay': crewPay,
      'sentAt': sent == null ? null : isoTime(sent),
      'decidedAt': accepted == null ? null : isoTime(accepted),
    });
    return tx.insert(Collections.properties, {
      ...base,
      'status': accepted != null
          ? PropertyStatus.active
          : sent != null
          ? PropertyStatus.quoted
          : PropertyStatus.quoteRequested,
      'price': price,
      'crewPay': crewPay,
    });
  }

  /// A finished, manually billed job: [paid] or still due.
  void doneJob(
    String id,
    Doc property,
    String crewId, {
    required DateTime completed,
    required bool paid,
    bool shovel = false,
    String? payoutId,
  }) {
    final requested = completed.subtract(const Duration(hours: 2));
    tx.insert(Collections.jobs, {
      ...jobDoc(
        id: id,
        property: property,
        settings: settings,
        shovel: shovel,
        note: '',
        source: 'customer',
        requestedAt: requested,
        payment: {
          ...manualPayment(),
          'status': paid ? PaymentStatus.paid : PaymentStatus.due,
          'capturedAt': paid
              ? isoTime(completed.add(const Duration(days: 1)))
              : null,
        },
      ),
      'status': JobStatus.done,
      'crewId': crewId,
      'claimedAt': isoTime(requested.add(const Duration(minutes: 15))),
      'startedAt': isoTime(completed.subtract(const Duration(minutes: 40))),
      'completedAt': isoTime(completed),
      'payoutId': payoutId,
    });
  }
}

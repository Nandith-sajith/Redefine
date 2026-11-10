/// Thrown by [Config.fromEnv] when an environment variable is unusable.
class ConfigError implements Exception {
  /// What is wrong, naming the variable.
  final String message;
  const ConfigError(this.message);

  @override
  String toString() => 'ConfigError: $message';
}

/// Password of the demo accounts unless `DEMO_PASSWORD` says otherwise. It
/// is public knowledge: fit for a local memory server only.
const defaultDemoPassword = 'redefine';

/// Shortest `ADMIN_INVITE_CODE` the server starts with.
const minInviteCodeLength = 16;

const _minDemoPasswordLength = 8;

/// Server configuration, read once at boot from the environment.
class Config {
  /// TCP port to listen on (`PORT`).
  final int port;

  /// `memory` or `firestore` (`PERSISTENCE`).
  final String persistence;

  /// Google Cloud project that owns the Firestore database (`GCP_PROJECT`).
  final String? gcpProject;

  /// Firestore database id (`FIRESTORE_DATABASE`).
  final String firestoreDatabase;

  /// Stripe secret key (`STRIPE_SECRET_KEY`); null means manual payments.
  final String? stripeSecretKey;

  /// Public origin of this API without a trailing slash (`PUBLIC_BASE_URL`).
  final String publicBaseUrl;

  /// Code required for admin signup (`ADMIN_INVITE_CODE`); null disables it.
  final String? adminInviteCode;

  /// Whether to load the demo data into an empty database (`SEED_DEMO`).
  final bool seedDemo;

  /// Password of every demo account (`DEMO_PASSWORD`).
  final String demoPassword;

  /// Whether the demo seed also loads the sample properties, jobs and extra
  /// accounts the tests use (`SEED_SAMPLE_DATA`); memory persistence only.
  final bool seedSampleData;

  /// PBKDF2 rounds for new password hashes (`PBKDF2_ITERATIONS`).
  final int pbkdf2Iterations;

  /// Lifetime of a login session in days (`SESSION_TTL_DAYS`).
  final int sessionTtlDays;

  /// True on Cloud Run (`K_SERVICE` is set): use the metadata server for tokens.
  final bool onCloudRun;

  /// Defaults describe a local memory server in manual-payment mode; tests
  /// override what they need (e.g. a low [pbkdf2Iterations]).
  const Config({
    this.port = 8080,
    this.persistence = 'memory',
    this.gcpProject,
    this.firestoreDatabase = '(default)',
    this.stripeSecretKey,
    this.publicBaseUrl = 'http://localhost:8080',
    this.adminInviteCode,
    this.seedDemo = true,
    this.demoPassword = defaultDemoPassword,
    this.seedSampleData = false,
    this.pbkdf2Iterations = 100000,
    this.sessionTtlDays = 30,
    this.onCloudRun = false,
  });

  /// Builds the configuration from [env]; throws [ConfigError] on bad values.
  factory Config.fromEnv(Map<String, String> env) {
    String? text(String key) {
      final value = env[key]?.trim();
      return value == null || value.isEmpty ? null : value;
    }

    int integer(
      String key,
      int fallback, {
      required int min,
      required int max,
    }) {
      final raw = text(key);
      if (raw == null) return fallback;
      final value = int.tryParse(raw);
      if (value == null || value < min || value > max) {
        throw ConfigError('$key must be a whole number from $min to $max.');
      }
      return value;
    }

    bool flag(String key, bool fallback) {
      final raw = text(key)?.toLowerCase();
      if (raw == null) return fallback;
      if (const {'true', '1', 'yes', 'on'}.contains(raw)) return true;
      if (const {'false', '0', 'no', 'off'}.contains(raw)) return false;
      throw ConfigError('$key must be true or false.');
    }

    final port = integer('PORT', 8080, min: 1, max: 65535);
    final persistence = (text('PERSISTENCE') ?? 'memory').toLowerCase();
    if (persistence != 'memory' && persistence != 'firestore') {
      throw const ConfigError('PERSISTENCE must be "memory" or "firestore".');
    }
    final gcpProject = text('GCP_PROJECT');
    if (persistence == 'firestore' && gcpProject == null) {
      throw const ConfigError(
        'GCP_PROJECT is required when PERSISTENCE=firestore.',
      );
    }
    var baseUrl = text('PUBLIC_BASE_URL') ?? 'http://localhost:$port';
    while (baseUrl.endsWith('/')) {
      baseUrl = baseUrl.substring(0, baseUrl.length - 1);
    }
    final baseUri = Uri.tryParse(baseUrl);
    if (baseUri == null || !baseUri.hasScheme || baseUri.host.isEmpty) {
      throw const ConfigError('PUBLIC_BASE_URL must be an absolute URL.');
    }

    final adminInviteCode = text('ADMIN_INVITE_CODE');
    if (adminInviteCode != null &&
        adminInviteCode.length < minInviteCodeLength) {
      throw const ConfigError(
        'ADMIN_INVITE_CODE must be at least $minInviteCodeLength characters.',
      );
    }
    final stripeSecretKey = text('STRIPE_SECRET_KEY');
    final seedDemo = flag('SEED_DEMO', persistence == 'memory');
    final seedSampleData = flag('SEED_SAMPLE_DATA', false);
    if (seedSampleData && persistence != 'memory') {
      throw const ConfigError(
        'SEED_SAMPLE_DATA is for a memory server only; a real database gets '
        'the demo accounts and nothing else.',
      );
    }
    final demoPassword = text('DEMO_PASSWORD');
    // The demo accounts include an admin. Where real data or real money is
    // at stake they must not get a password anyone can look up.
    final realData =
        persistence == 'firestore' ||
        (stripeSecretKey != null && _liveKey.hasMatch(stripeSecretKey));
    if (seedDemo &&
        realData &&
        (demoPassword == null ||
            demoPassword == defaultDemoPassword ||
            demoPassword.length < _minDemoPasswordLength)) {
      throw const ConfigError(
        'SEED_DEMO=true with PERSISTENCE=firestore or a live Stripe key needs '
        'DEMO_PASSWORD set to a private password of at least '
        '$_minDemoPasswordLength characters (or set SEED_DEMO=false).',
      );
    }

    return Config(
      port: port,
      persistence: persistence,
      gcpProject: gcpProject,
      firestoreDatabase: text('FIRESTORE_DATABASE') ?? '(default)',
      stripeSecretKey: stripeSecretKey,
      publicBaseUrl: baseUrl,
      adminInviteCode: adminInviteCode,
      seedDemo: seedDemo,
      demoPassword: demoPassword ?? defaultDemoPassword,
      seedSampleData: seedSampleData,
      pbkdf2Iterations: integer(
        'PBKDF2_ITERATIONS',
        100000,
        min: 1,
        max: 10000000,
      ),
      sessionTtlDays: integer('SESSION_TTL_DAYS', 30, min: 1, max: 3650),
      onCloudRun: text('K_SERVICE') != null,
    );
  }

  static final _liveKey = RegExp('^[a-z]+_live_');

  /// True when a Stripe key is configured (payments mode `stripe`).
  bool get stripeConfigured => stripeSecretKey != null;

  /// Lifetime of a login session.
  Duration get sessionTtl => Duration(days: sessionTtlDays);

  /// One-line boot summary that is safe to log (no secrets).
  String describe() =>
      'port=$port persistence=$persistence'
      '${persistence == 'firestore' ? ' project=$gcpProject database=$firestoreDatabase' : ''}'
      ' payments=${stripeConfigured ? 'stripe' : 'manual'}'
      ' adminInvite=${adminInviteCode == null ? 'off' : 'on'}'
      ' seedDemo=$seedDemo${seedSampleData ? "+sample" : ""}'
      ' publicBaseUrl=$publicBaseUrl';

  @override
  String toString() => 'Config(${describe()})';
}

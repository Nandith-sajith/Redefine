// Typed, immutable models mirroring the Redefine API JSON.
//
// Parsing never throws: a field that is missing from a role's view (or has the
// wrong type) falls back to its default (0, '', false, null, enum `unknown`).

import 'json.dart';

enum PropertyStatus { quoteRequested, quoted, active, declined, unknown }

enum QuoteStatus { pending, sent, accepted, declined, unknown }

enum JobStatus { open, claimed, inProgress, done, cancelled, unknown }

enum PaymentMode { stripe, manual, unknown }

enum PaymentStatus {
  none,
  authorized,
  captured,
  released,
  failed,
  due,
  paid,
  unknown,
}

enum CrewStatus { pending, active, rejected, unknown }

T? _objOrNull<T>(Object? v, T Function(Map<String, dynamic>) f) =>
    v is Map ? f(mapOf(v)) : null;

class AuthUser {
  final String id, name, email, role, initials, color, phone;

  /// The customer id (role customer) or crew id (role crew); null for admin.
  final String? linkedId;

  /// Set for crew accounts only.
  final CrewStatus? crewStatus;

  AuthUser.fromJson(Map<String, dynamic> j)
    : id = str(j['id']),
      name = str(j['name']),
      email = str(j['email']),
      role = str(j['role']),
      initials = str(j['initials']),
      color = str(j['color']),
      phone = str(j['phone']),
      linkedId = strOrNull(j['linkedId']),
      crewStatus = j['crewStatus'] == null
          ? null
          : enumOf(CrewStatus.values, j['crewStatus'], CrewStatus.unknown);

  String get firstName {
    final trimmed = name.trim();
    return trimmed.isEmpty ? '' : trimmed.split(RegExp(r'\s+')).first;
  }
}

class AuthResult {
  final String token;
  final AuthUser user;

  AuthResult.fromJson(Map<String, dynamic> j)
    : token = str(j['token']),
      user = AuthUser.fromJson(mapOf(j['user']));
}

/// Role-shaped: customers do not receive the crew fields and vice versa.
class Settings {
  final int shovelPrice, crewShovelBonus, openJobExpiryHours;
  final String currency;
  final PaymentMode paymentsMode;

  Settings.fromJson(Map<String, dynamic> j)
    : shovelPrice = intOf(j['shovelPrice']),
      crewShovelBonus = intOf(j['crewShovelBonus']),
      openJobExpiryHours = intOf(j['openJobExpiryHours']),
      currency = str(j['currency']),
      paymentsMode = enumOf(
        PaymentMode.values,
        j['paymentsMode'],
        PaymentMode.unknown,
      );
}

class PaymentInfo {
  final PaymentMode mode;
  final PaymentStatus status;
  final String? error;
  final DateTime? holdExpiresAt, capturedAt;

  PaymentInfo.fromJson(Map<String, dynamic> j)
    : mode = enumOf(PaymentMode.values, j['mode'], PaymentMode.unknown),
      status = enumOf(PaymentStatus.values, j['status'], PaymentStatus.unknown),
      error = strOrNull(j['error']),
      holdExpiresAt = dateOrNull(j['holdExpiresAt']),
      capturedAt = dateOrNull(j['capturedAt']);
}

class Job {
  final String id, propertyId, customerId, propertyName, address, illustration;
  final String customerName, customerInitials, customerPhone;
  final bool shovel;

  /// [total] = [price] + [shovelPrice]. [crewPay] already includes the
  /// shovelling bonus.
  final int price, shovelPrice, total, crewPay;
  final JobStatus status;
  final String crewId, crewName, crewInitials, crewColor;
  final String note, crewNote, source;
  final DateTime? requestedAt, claimedAt, startedAt, completedAt, cancelledAt;

  /// `customer` | `admin` | `system`, or '' when the job was not cancelled.
  final String cancelledBy;
  final PaymentInfo payment;
  final bool paidOut;

  Job.fromJson(Map<String, dynamic> j)
    : id = str(j['id']),
      propertyId = str(j['propertyId']),
      customerId = str(j['customerId']),
      propertyName = str(j['propertyName']),
      address = str(j['address']),
      illustration = str(j['illustration']),
      customerName = str(j['customerName']),
      customerInitials = str(j['customerInitials']),
      customerPhone = str(j['customerPhone']),
      shovel = boolOf(j['shovel']),
      price = intOf(j['price']),
      shovelPrice = intOf(j['shovelPrice']),
      total = intOf(j['total']),
      crewPay = intOf(j['crewPay']),
      status = enumOf(JobStatus.values, j['status'], JobStatus.unknown),
      crewId = str(j['crewId']),
      crewName = str(j['crewName']),
      crewInitials = str(j['crewInitials']),
      crewColor = str(j['crewColor']),
      note = str(j['note']),
      crewNote = str(j['crewNote']),
      source = str(j['source']),
      requestedAt = dateOrNull(j['requestedAt']),
      claimedAt = dateOrNull(j['claimedAt']),
      startedAt = dateOrNull(j['startedAt']),
      completedAt = dateOrNull(j['completedAt']),
      cancelledAt = dateOrNull(j['cancelledAt']),
      cancelledBy = str(j['cancelledBy']),
      payment = PaymentInfo.fromJson(mapOf(j['payment'])),
      paidOut = boolOf(j['paidOut']);

  bool get isActive =>
      status == JobStatus.open ||
      status == JobStatus.claimed ||
      status == JobStatus.inProgress;

  bool get canCustomerCancel =>
      status == JobStatus.open || status == JobStatus.claimed;

  /// Time on site; null unless the job was both started and completed.
  Duration? get duration {
    final start = startedAt, end = completedAt;
    if (start == null || end == null) return null;
    final d = end.difference(start);
    return d.isNegative ? Duration.zero : d;
  }

  /// 0 requested, 1 crew assigned, 2 in progress, 3 done. A cancelled job
  /// reports the last step it reached.
  int get stepIndex => switch (status) {
    JobStatus.open => 0,
    JobStatus.claimed => 1,
    JobStatus.inProgress => 2,
    JobStatus.done => 3,
    JobStatus.cancelled ||
    JobStatus.unknown => startedAt != null ? 2 : (claimedAt != null ? 1 : 0),
  };
}

class Property {
  final String id, name, address, illustration, note;
  final PropertyStatus status;

  /// What the customer pays per plough; null until a quote has been sent.
  final int? price;
  final String quoteId;
  final DateTime? createdAt;

  /// The property's unfinished job, if any.
  final Job? activeJob;

  // Admin view only.
  final String customerId, customerName;
  final int? crewPay;

  Property.fromJson(Map<String, dynamic> j)
    : id = str(j['id']),
      name = str(j['name']),
      address = str(j['address']),
      illustration = str(j['illustration']),
      note = str(j['note']),
      status = enumOf(
        PropertyStatus.values,
        j['status'],
        PropertyStatus.unknown,
      ),
      price = intOrNull(j['price']),
      quoteId = str(j['quoteId']),
      createdAt = dateOrNull(j['createdAt']),
      activeJob = _objOrNull(j['activeJob'], Job.fromJson),
      customerId = str(j['customerId']),
      customerName = str(j['customerName']),
      crewPay = intOrNull(j['crewPay']);
}

class Quote {
  final String id, propertyId, customerId;
  final QuoteStatus status;
  final String note;

  /// Null while pending; [crewPay] is always null in the customer view.
  final int? price, crewPay;
  final DateTime? createdAt, sentAt, decidedAt;
  final String customerName, customerInitials, customerColor;
  final String email, phone, propertyName, address, illustration;

  Quote.fromJson(Map<String, dynamic> j)
    : id = str(j['id']),
      propertyId = str(j['propertyId']),
      customerId = str(j['customerId']),
      status = enumOf(QuoteStatus.values, j['status'], QuoteStatus.unknown),
      note = str(j['note']),
      price = intOrNull(j['price']),
      crewPay = intOrNull(j['crewPay']),
      createdAt = dateOrNull(j['createdAt']),
      sentAt = dateOrNull(j['sentAt']),
      decidedAt = dateOrNull(j['decidedAt']),
      customerName = str(j['customerName']),
      customerInitials = str(j['customerInitials']),
      customerColor = str(j['customerColor']),
      email = str(j['email']),
      phone = str(j['phone']),
      propertyName = str(j['propertyName']),
      address = str(j['address']),
      illustration = str(j['illustration']);
}

class CardInfo {
  final String brand, last4;
  final int expMonth, expYear;
  final DateTime? updatedAt;

  CardInfo.fromJson(Map<String, dynamic> j)
    : brand = str(j['brand']),
      last4 = str(j['last4']),
      expMonth = intOf(j['expMonth']),
      expYear = intOf(j['expYear']),
      updatedAt = dateOrNull(j['updatedAt']);
}

class Charge {
  final String jobId, propertyName;
  final DateTime? date;
  final int total;
  final bool shovel;
  final PaymentStatus status;

  Charge.fromJson(Map<String, dynamic> j)
    : jobId = str(j['jobId']),
      propertyName = str(j['propertyName']),
      date = dateOrNull(j['date']),
      total = intOf(j['total']),
      shovel = boolOf(j['shovel']),
      status = enumOf(PaymentStatus.values, j['status'], PaymentStatus.unknown);
}

class Billing {
  final PaymentMode mode;
  final CardInfo? card;
  final bool pendingSetup;
  final int balanceDue;
  final List<Charge> charges;

  Billing.fromJson(Map<String, dynamic> j)
    : mode = enumOf(PaymentMode.values, j['mode'], PaymentMode.unknown),
      card = _objOrNull(j['card'], CardInfo.fromJson),
      pendingSetup = boolOf(j['pendingSetup']),
      balanceDue = intOf(j['balanceDue']),
      charges = listOf(j['charges'], Charge.fromJson);

  /// A card must be saved before a plough can be requested.
  bool get needsCard => mode == PaymentMode.stripe && card == null;
}

class Customer {
  final String id, name, initials, color, email, phone;
  final DateTime? createdAt, lastJobAt;
  final int propertyCount, activeProperties, jobCount;
  final bool hasCard;
  final List<String> addresses;

  Customer.fromJson(Map<String, dynamic> j)
    : id = str(j['id']),
      name = str(j['name']),
      initials = str(j['initials']),
      color = str(j['color']),
      email = str(j['email']),
      phone = str(j['phone']),
      createdAt = dateOrNull(j['createdAt']),
      lastJobAt = dateOrNull(j['lastJobAt']),
      propertyCount = intOf(j['propertyCount']),
      activeProperties = intOf(j['activeProperties']),
      jobCount = intOf(j['jobCount']),
      hasCard = boolOf(j['hasCard']),
      addresses = strList(j['addresses']);
}

/// `GET /customers/:id`: the list-item fields plus card, properties, jobs
/// (newest first) and totals.
class CustomerDetail {
  final Customer customer;
  final CardInfo? card;
  final List<Property> properties;
  final List<Job> jobs;
  final int billed, outstanding;

  CustomerDetail.fromJson(Map<String, dynamic> j)
    : customer = Customer.fromJson(j),
      card = _objOrNull(j['card'], CardInfo.fromJson),
      properties = listOf(j['properties'], Property.fromJson),
      jobs = listOf(j['jobs'], Job.fromJson),
      billed = intOf(mapOf(j['totals'])['billed']),
      outstanding = intOf(mapOf(j['totals'])['outstanding']);
}

class CrewMember {
  final String id, userId, name, initials, color, email, phone;
  final CrewStatus status;
  final DateTime? appliedAt;

  /// [unpaidJobs] is a count.
  final int jobsThisWeek, earnedThisWeek, unpaidTotal, unpaidJobs;

  CrewMember.fromJson(Map<String, dynamic> j)
    : id = str(j['id']),
      userId = str(j['userId']),
      name = str(j['name']),
      initials = str(j['initials']),
      color = str(j['color']),
      email = str(j['email']),
      phone = str(j['phone']),
      status = enumOf(CrewStatus.values, j['status'], CrewStatus.unknown),
      appliedAt = dateOrNull(j['appliedAt']),
      jobsThisWeek = intOf(j['jobsThisWeek']),
      earnedThisWeek = intOf(j['earnedThisWeek']),
      unpaidTotal = intOf(j['unpaidTotal']),
      unpaidJobs = intOf(j['unpaidJobs']);
}

class Payout {
  final String id, crewId;
  final int amount, jobCount;
  final DateTime? paidAt;
  final String note;

  Payout.fromJson(Map<String, dynamic> j)
    : id = str(j['id']),
      crewId = str(j['crewId']),
      amount = intOf(j['amount']),
      jobCount = intOf(j['jobCount']),
      paidAt = dateOrNull(j['paidAt']),
      note = str(j['note']);
}

class CrewPay {
  final String crewId, name;
  final int earnedToday, jobsToday, earnedThisWeek, jobsThisWeek;
  final int earnedAllTime, unpaidTotal;
  final List<Job> unpaidJobs;

  /// Newest first.
  final List<Payout> payouts;

  CrewPay.fromJson(Map<String, dynamic> j)
    : crewId = str(j['crewId']),
      name = str(j['name']),
      earnedToday = intOf(j['earnedToday']),
      jobsToday = intOf(j['jobsToday']),
      earnedThisWeek = intOf(j['earnedThisWeek']),
      jobsThisWeek = intOf(j['jobsThisWeek']),
      earnedAllTime = intOf(j['earnedAllTime']),
      unpaidTotal = intOf(j['unpaidTotal']),
      unpaidJobs = listOf(j['unpaidJobs'], Job.fromJson),
      payouts = listOf(j['payouts'], Payout.fromJson);
}

class DashboardCounts {
  final int pendingQuotes, sentQuotes, pendingCrew;
  final int openJobs, claimedJobs, inProgressJobs;
  final int doneToday, cancelledToday, revenueToday, paymentIssues;

  DashboardCounts.fromJson(Map<String, dynamic> j)
    : pendingQuotes = intOf(j['pendingQuotes']),
      sentQuotes = intOf(j['sentQuotes']),
      pendingCrew = intOf(j['pendingCrew']),
      openJobs = intOf(j['openJobs']),
      claimedJobs = intOf(j['claimedJobs']),
      inProgressJobs = intOf(j['inProgressJobs']),
      doneToday = intOf(j['doneToday']),
      cancelledToday = intOf(j['cancelledToday']),
      revenueToday = intOf(j['revenueToday']),
      paymentIssues = intOf(j['paymentIssues']);
}

class AdminDashboard {
  final DateTime? serverTime;
  final DashboardCounts counts;

  /// Oldest first.
  final List<Quote> pendingQuotes;

  /// Open, claimed and in-progress jobs, oldest request first.
  final List<Job> liveJobs;
  final List<CrewMember> pendingCrew;

  /// Jobs whose payment failed or is due.
  final List<Job> paymentIssues;

  AdminDashboard.fromJson(Map<String, dynamic> j)
    : serverTime = dateOrNull(j['serverTime']),
      counts = DashboardCounts.fromJson(mapOf(j['counts'])),
      pendingQuotes = listOf(j['pendingQuotes'], Quote.fromJson),
      liveJobs = listOf(j['liveJobs'], Job.fromJson),
      pendingCrew = listOf(j['pendingCrew'], CrewMember.fromJson),
      paymentIssues = listOf(j['paymentIssues'], Job.fromJson);
}

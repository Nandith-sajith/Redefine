// Pure helpers behind the customer screens: what to poll, which property to
// select, what to say about a job and its payment, and form validation.
// Nothing here builds widgets or talks to the network.

import 'package:redefine_ui/redefine_ui.dart';

/// The customer's settings and billing, which the home screen loads together.
class Account {
  const Account({required this.settings, required this.billing});
  final Settings settings;
  final Billing billing;

  /// Whether a plough is paid for by a hold on a saved card rather than
  /// billed after the job.
  bool get paysByCard => billing.mode == PaymentMode.stripe;
}

// ---- Properties -----------------------------------------------------------

/// What an action on this device made of a property's unfinished job: the job
/// a request returned, or none once it was cancelled. It is shown in place of
/// what the properties say until they have been loaded afresh, so that the
/// screen does not depend on that reload succeeding.
class JobChange {
  const JobChange(this.job, {required this.afterLoad});

  /// The requested job; null when the property's job was cancelled.
  final Job? job;

  /// How many loads of the properties had been started when the action took
  /// effect. Only a later load is sure to include it.
  final int afterLoad;

  /// Whether properties that came from load number [load] include this change.
  bool knownTo(int load) => load > afterLoad;
}

/// The unfinished job to show for [property]: what [changes] (by property id)
/// says an action on this device made of it, else what the property carries.
Job? shownJob(Property property, [Map<String, JobChange> changes = const {}]) {
  final change = changes[property.id];
  return change == null ? property.activeJob : change.job;
}

/// Whether the property is waiting on the customer or has work under way.
bool needsAttention(Property property, [Map<String, JobChange> changes = const {}]) =>
    property.status == PropertyStatus.quoted || shownJob(property, changes) != null;

/// The property to open on: one with a job under way, else one with a quote
/// to answer, else the first. Null when there are none.
String? defaultPropertyId(List<Property> properties) {
  if (properties.isEmpty) return null;
  for (final p in properties) {
    if (p.activeJob != null) return p.id;
  }
  for (final p in properties) {
    if (p.status == PropertyStatus.quoted) return p.id;
  }
  return properties.first.id;
}

/// Keeps [selectedId] while that property still exists, else picks the
/// default one.
String? keepSelection(String? selectedId, List<Property> properties) =>
    properties.any((p) => p.id == selectedId) ? selectedId : defaultPropertyId(properties);

const activeJobPoll = Duration(seconds: 5);
const quotePoll = Duration(seconds: 15);
const idlePoll = Duration(seconds: 60);

/// How often to reload the properties: quickly while a job is under way or
/// the properties have yet to catch up with [changes], fairly often while a
/// quote is awaited, otherwise once a minute.
Duration propertiesPollInterval(
  List<Property> properties, [
  Map<String, JobChange> changes = const {},
]) {
  if (changes.isNotEmpty || properties.any((p) => p.activeJob != null)) return activeJobPoll;
  if (properties.any((p) => p.status == PropertyStatus.quoteRequested)) return quotePoll;
  return idlePoll;
}

/// Compares the jobs being followed ([following]: property id -> job id) with
/// the latest [properties], seen through [changes]. `ended` lists the followed
/// jobs that are no longer their property's unfinished job: they were
/// completed or cancelled.
({Map<String, String> following, List<({String propertyId, String jobId})> ended}) followActiveJobs(
  Map<String, String> following,
  List<Property> properties, [
  Map<String, JobChange> changes = const {},
]) {
  final next = <String, String>{};
  final ended = <({String propertyId, String jobId})>[];
  for (final p in properties) {
    final current = shownJob(p, changes)?.id;
    final before = following[p.id];
    if (before != null && before != current) ended.add((propertyId: p.id, jobId: before));
    if (current != null) next[p.id] = current;
  }
  return (following: next, ended: ended);
}

// ---- Prices and cards -----------------------------------------------------

int ploughTotal({required int price, required bool shovel, required int shovelPrice}) =>
    price + (shovel ? shovelPrice : 0);

/// What a plough request is priced and paid from: the property's price per
/// plough, and the account's shovelling price and card.
typedef RequestTerms = ({int price, Account account});

/// What shovelling adds to a plough: `+$20`, or `at no extra charge`.
String shovelExtra(int shovelPrice) =>
    shovelPrice > 0 ? '+${money(shovelPrice)}' : 'at no extra charge';

/// A card network's display name from its API key (`visa` -> `Visa`).
String cardBrand(String brand) => switch (brand.trim().toLowerCase()) {
  '' || 'unknown' => 'Card',
  'visa' => 'Visa',
  'mastercard' => 'Mastercard',
  'amex' || 'american_express' => 'American Express',
  'discover' => 'Discover',
  'diners' || 'diners_club' => 'Diners Club',
  'jcb' => 'JCB',
  'unionpay' => 'UnionPay',
  final other => other[0].toUpperCase() + other.substring(1).replaceAll('_', ' '),
};

/// `Visa ending 4242`.
String cardLabel(CardInfo card) =>
    card.last4.isEmpty ? cardBrand(card.brand) : '${cardBrand(card.brand)} ending ${card.last4}';

/// `Expires 04/27`, or empty when the expiry is not known.
String cardExpiry(CardInfo card) {
  if (card.expMonth < 1 || card.expMonth > 12 || card.expYear <= 0) return '';
  final month = card.expMonth.toString().padLeft(2, '0');
  final year = (card.expYear % 100).toString().padLeft(2, '0');
  return 'Expires $month/$year';
}

/// Whether a card setup that began with [before] on file has now saved a
/// card: there is one, and it is not the one that was already there.
bool cardSaved(CardInfo? before, CardInfo? after) =>
    after != null && (before == null || after.updatedAt != before.updatedAt);

/// What the customer agrees to when requesting a plough for [total]. When
/// that is no longer the total the screen showed as they asked ([shownTotal]),
/// it says so first.
String requestConfirmation(int total, Billing billing, {int? shownTotal}) {
  final card = billing.card;
  final terms = billing.mode == PaymentMode.stripe && card != null
      ? "We'll place a hold of ${money(total)} on your ${cardLabel(card)}. "
            "You're charged only when the job is done."
      : "You'll be billed ${money(total)} after the job.";
  return shownTotal == null || shownTotal == total
      ? terms
      : 'The price has changed, so the total is now ${money(total)}, '
            'not ${money(shownTotal)}. $terms';
}

/// The news that [job] was requested. The server prices the job itself, so
/// its total can differ from the one the customer [confirmed] when the price
/// changed in that very moment; the message then says what it really is.
String requestedMessage(Job job, {required int confirmed}) => job.total == confirmed
    ? 'Plough requested. The crew that accepts it shows up here.'
    : 'Plough requested, but the price changed as you confirmed: the total is '
          '${money(job.total)}, not ${money(confirmed)}. You can still cancel the request.';

// ---- Jobs -----------------------------------------------------------------

/// The one-line news that a followed job has ended, or null while it has not.
String? jobOutcomeMessage(Job job) {
  final total = money(job.total);
  return switch (job.status) {
    JobStatus.done => switch (job.payment.status) {
      PaymentStatus.captured => 'Plough complete · $total charged',
      PaymentStatus.paid => 'Plough complete · $total paid',
      PaymentStatus.failed => "Plough complete · we couldn't charge your card",
      _ => 'Plough complete · $total billed',
    },
    JobStatus.cancelled => switch (job.payment.status) {
      PaymentStatus.released => 'Request cancelled · hold released',
      PaymentStatus.authorized => 'Request cancelled · the hold is being released',
      _ => 'Request cancelled',
    },
    _ => null,
  };
}

/// Who cancelled a job, from its `cancelledBy`.
String cancelledLabel(String cancelledBy) => switch (cancelledBy) {
  'customer' => 'Cancelled by you',
  'admin' => 'Cancelled by the office',
  'system' => 'Expired before a crew accepted',
  _ => 'Cancelled',
};

String? _when(DateTime? at) => at == null ? null : fmtDayTime(at);

String? _joined(Iterable<String?> parts) {
  final shown = [
    for (final part in parts)
      if (part != null && part.isNotEmpty) part,
  ];
  return shown.isEmpty ? null : shown.join(' · ');
}

/// The job's progress as tracker steps: requested, crew assigned, in
/// progress (work started, once it is over), done. A cancelled job shows the
/// steps it reached and then who cancelled it. [elapsed] is the running time
/// of a job in progress.
List<RStep> jobSteps(Job job, {Duration? elapsed}) {
  RStep crewAssigned(RStepState state) => RStep(
    'Crew assigned',
    subtitle: state == RStepState.upcoming ? null : _joined([job.crewName, _when(job.claimedAt)]),
    state: state,
  );
  if (job.status == JobStatus.cancelled) {
    return [
      RStep('Requested', subtitle: _when(job.requestedAt), state: RStepState.done),
      if (job.claimedAt != null) crewAssigned(RStepState.done),
      if (job.startedAt != null)
        RStep('Work started', subtitle: _when(job.startedAt), state: RStepState.done),
      RStep(
        cancelledLabel(job.cancelledBy),
        subtitle: _when(job.cancelledAt),
        state: RStepState.current,
      ),
    ];
  }

  final at = job.stepIndex;
  final done = at >= 3;
  RStepState state(int step) => done || step < at
      ? RStepState.done
      : step == at
      ? RStepState.current
      : RStepState.upcoming;
  final started = job.startedAt;
  final duration = job.duration;
  return [
    RStep(
      'Requested',
      subtitle: _joined([_when(job.requestedAt), if (at == 0) 'waiting for a crew to accept']),
      state: state(0),
    ),
    crewAssigned(state(1)),
    RStep(
      done ? 'Work started' : 'In progress',
      subtitle: switch (at) {
        2 => _joined([
          if (started != null) 'Started ${fmtTime(started)}',
          if (elapsed != null) fmtElapsed(elapsed),
        ]),
        3 => _when(started),
        _ => null,
      },
      state: state(2),
    ),
    RStep(
      'Done',
      subtitle: done
          ? _joined([_when(job.completedAt), if (duration != null) 'took ${fmtDuration(duration)}'])
          : null,
      state: state(3),
    ),
  ];
}

/// The finished part of a job list: done and cancelled jobs, in list order.
List<Job> pastJobs(List<Job> jobs) => [
  for (final job in jobs)
    if (job.status == JobStatus.done || job.status == JobStatus.cancelled) job,
];

/// When a finished job ended (falling back to when it was requested).
DateTime? pastJobDate(Job job) => job.completedAt ?? job.cancelledAt ?? job.requestedAt;

/// The line under a past job's date: who did it and how long it took, or who
/// cancelled it.
String pastJobSummary(Job job) {
  if (job.status == JobStatus.cancelled) return cancelledLabel(job.cancelledBy);
  final duration = job.duration;
  return _joined([
        job.crewName,
        if (duration != null) fmtDuration(duration),
        if (job.shovel) 'with shovelling',
      ]) ??
      serviceLabel(shovel: job.shovel);
}

/// How an unfinished job will be paid for.
String activePaymentLine(PaymentInfo payment) =>
    payment.mode == PaymentMode.stripe ? 'Hold placed on your card' : 'Billed after the job';

/// Whether [job] was cancelled with a card hold that has yet to be released:
/// the payment provider could not be reached and the server keeps trying.
bool holdBeingReleased(Job job) =>
    job.status == JobStatus.cancelled && job.payment.status == PaymentStatus.authorized;

/// A sentence on where a job's payment stands. Empty when there is nothing
/// to say.
String paymentSummary(Job job) {
  final total = money(job.total);
  final captured = job.payment.capturedAt;
  return switch (job.payment.status) {
    PaymentStatus.authorized => switch (job.status) {
      JobStatus.cancelled =>
        'The hold of $total on your card is being released. You will not be charged.',
      JobStatus.done => 'The job is done and $total is being charged to your card.',
      _ => "A hold of $total is on your card. You're charged only when the job is done.",
    },
    PaymentStatus.captured =>
      captured == null
          ? '$total was charged to your card.'
          : '$total was charged to your card on ${fmtDayTime(captured)}.',
    PaymentStatus.released => 'The hold on your card was released. You were not charged.',
    PaymentStatus.failed => "We couldn't charge your card for this job.",
    PaymentStatus.due => '$total is due for this job.',
    PaymentStatus.paid => 'Paid. Thank you.',
    PaymentStatus.none || PaymentStatus.unknown => switch (job.status) {
      JobStatus.cancelled => 'This request was cancelled, so nothing is billed.',
      JobStatus.done || JobStatus.unknown => '',
      _ => "You'll be billed $total after the job.",
    },
  };
}

// ---- Add-property form ----------------------------------------------------

const propertyNameMax = 60;
const propertyAddressMax = 160;
const propertyNoteMax = 500;

/// The problem with each field of the add-property form; null when it is fine.
class PropertyFormErrors {
  const PropertyFormErrors({this.name, this.address, this.note});
  final String? name, address, note;

  bool get isEmpty => name == null && address == null && note == null;
}

/// Checks the (already trimmed) add-property fields against the API's limits.
PropertyFormErrors validatePropertyForm({
  required String name,
  required String address,
  required String note,
}) => PropertyFormErrors(
  name: name.isEmpty
      ? 'Give this property a name.'
      : name.length > propertyNameMax
      ? 'Use $propertyNameMax characters or fewer.'
      : null,
  address: address.isEmpty
      ? 'Enter the address to plough.'
      : address.length > propertyAddressMax
      ? 'Use $propertyAddressMax characters or fewer.'
      : null,
  note: note.length > propertyNoteMax ? 'Use $propertyNoteMax characters or fewer.' : null,
);

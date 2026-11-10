/// Builders for the stored documents, so the features and the demo seed
/// write the same shapes.
library;

import '../model.dart';
import '../time.dart';
import 'persistence.dart';

/// `users/<id>`. `passwordHash` is private to the server.
Doc userDoc({
  required String id,
  required String name,
  required String email,
  required String role,
  required String color,
  required String passwordHash,
  required DateTime createdAt,
  String phone = '',
  String? linkedId,
}) => {
  'id': id,
  'name': name,
  'email': email,
  'role': role,
  'initials': initialsOf(name),
  'color': color,
  'phone': phone,
  'linkedId': linkedId,
  'passwordHash': passwordHash,
  'createdAt': isoTime(createdAt),
};

/// `customers/<user.linkedId>` for a customer [user]. The Stripe ids and the
/// pending setup session are private to the server.
Doc customerDoc(Doc user) => {
  'id': user['linkedId'],
  'userId': user['id'],
  'name': user['name'],
  'email': user['email'],
  'phone': user['phone'],
  'initials': user['initials'],
  'color': user['color'],
  'createdAt': user['createdAt'],
  'card': null,
  'stripeCustomerId': null,
  'stripePaymentMethodId': null,
  'pendingSetupSessionId': null,
  'pendingSetupAt': null,
};

/// `crew/<user.linkedId>` for a crew [user].
Doc crewDoc(Doc user, {String status = CrewStatus.pending}) => {
  'id': user['linkedId'],
  'userId': user['id'],
  'name': user['name'],
  'email': user['email'],
  'phone': user['phone'],
  'initials': user['initials'],
  'color': user['color'],
  'status': status,
  'appliedAt': user['createdAt'],
};

/// A new property awaiting its first quote ([quoteId]).
Doc propertyDoc({
  required String id,
  required String customerId,
  required String name,
  required String address,
  required String illustration,
  required String note,
  required String quoteId,
  required DateTime createdAt,
}) => {
  'id': id,
  'customerId': customerId,
  'name': name,
  'address': address,
  'illustration': illustration,
  'note': note,
  'status': PropertyStatus.quoteRequested,
  'price': null,
  'crewPay': null,
  'quoteId': quoteId,
  'createdAt': isoTime(createdAt),
};

/// A pending quote request for [property].
Doc quoteDoc({
  required String id,
  required Doc property,
  required DateTime createdAt,
}) => {
  'id': id,
  'propertyId': property['id'],
  'customerId': property['customerId'],
  'status': QuoteStatus.pending,
  'note': property['note'],
  'price': null,
  'crewPay': null,
  'createdAt': isoTime(createdAt),
  'sentAt': null,
  'decidedAt': null,
};

/// An open job for the active [property], with the money snapshotted from
/// the property and [settings]. `crewPay` already includes the shovel bonus.
/// `payment.paymentIntentId`, `payment.paymentMethodId`, `payment.attempts`
/// and `payoutId` are private to the server.
Doc jobDoc({
  required String id,
  required Doc property,
  required Doc settings,
  required bool shovel,
  required String note,
  required String source,
  required DateTime requestedAt,
  required Map<String, dynamic> payment,
}) {
  final price = property['price'] as int;
  final shovelPrice = shovel ? settings['shovelPrice'] as int : 0;
  final bonus = shovel ? settings['crewShovelBonus'] as int : 0;
  return {
    'id': id,
    'propertyId': property['id'],
    'customerId': property['customerId'],
    'shovel': shovel,
    'price': price,
    'shovelPrice': shovelPrice,
    'total': price + shovelPrice,
    'crewPay': (property['crewPay'] as int) + bonus,
    'status': JobStatus.open,
    'crewId': null,
    'note': note,
    'crewNote': '',
    'source': source,
    'requestedAt': isoTime(requestedAt),
    'claimedAt': null,
    'startedAt': null,
    'completedAt': null,
    'cancelledAt': null,
    'cancelledBy': null,
    'payment': payment,
    'payoutId': null,
  };
}

/// The payment of a job that is billed by hand.
Map<String, dynamic> manualPayment() => {
  'mode': PaymentMode.manual,
  'status': PaymentStatus.none,
  'error': null,
  'holdExpiresAt': null,
  'capturedAt': null,
  'paymentIntentId': null,
  'paymentMethodId': null,
  'attempts': 0,
};

/// The payment of a job whose total is held on a card since [heldAt].
Map<String, dynamic> cardHoldPayment({
  required String paymentIntentId,
  required String paymentMethodId,
  required DateTime heldAt,
}) => {
  'mode': PaymentMode.stripe,
  'status': PaymentStatus.authorized,
  'error': null,
  'holdExpiresAt': isoTime(heldAt.add(holdLifetime)),
  'capturedAt': null,
  'paymentIntentId': paymentIntentId,
  'paymentMethodId': paymentMethodId,
  'attempts': 0,
};

/// A recorded payout of [amount] dollars covering [jobCount] jobs.
Doc payoutDoc({
  required String id,
  required String crewId,
  required int amount,
  required int jobCount,
  required DateTime paidAt,
  required String note,
}) => {
  'id': id,
  'crewId': crewId,
  'amount': amount,
  'jobCount': jobCount,
  'paidAt': isoTime(paidAt),
  'note': note,
};

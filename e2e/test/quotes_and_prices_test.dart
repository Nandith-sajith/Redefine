import 'package:redefine_core/redefine_core.dart';
import 'package:redefine_e2e/redefine_e2e.dart';
import 'package:test/test.dart';

import 'support/harness.dart';

void main() {
  late TestServer server;
  late ApiClient lia, sarah, marcus, paul;

  setUp(() async {
    server = await startServer(stripe: false, seed: true);
    lia = await signIn(server, 'lia@redefine.co');
    sarah = await signIn(server, 'sarah.m@gmail.com');
    marcus = await signIn(server, 'marcus@redefine.co');
    paul = await signIn(server, 'paul.l@gmail.com');
  });

  test('a declined quote can be requested again', () async {
    final declined = await paul.declineQuote('quote_birch');
    expect(declined.quote.status, QuoteStatus.declined);
    expect(declined.quote.decidedAt, isNotNull);
    expect(declined.property.status, PropertyStatus.declined);
    await expectApiError(
      paul.acceptQuote('quote_birch'),
      409,
      'quote_not_open',
    );
    await expectApiError(
      lia.sendQuote('quote_birch', price: 50, crewPay: 30),
      409,
      'quote_not_open',
    );
    await expectApiError(
      paul.requestJob(propertyId: 'prop_birch'),
      409,
      'invalid_state',
    );

    final again = await paul.requestQuoteAgain('prop_birch');
    expect(again.quote.id, isNot('quote_birch'));
    expect(again.quote.status, QuoteStatus.pending);
    expect(again.quote.propertyId, 'prop_birch');
    expect(again.quote.note, contains('hedge'));
    expect(again.property.status, PropertyStatus.quoteRequested);
    expect(again.property.quoteId, again.quote.id);
    expect(again.property.price, isNull);
    await expectApiError(
      paul.requestQuoteAgain('prop_birch'),
      409,
      'invalid_state',
    );
    final inbox = await lia.adminDashboard();
    expect(inbox.pendingQuotes.map((q) => q.id), [
      'quote_cabin',
      again.quote.id,
    ]);

    // Sending again before the customer decides replaces the offer.
    await lia.sendQuote(again.quote.id, price: 58, crewPay: 33);
    final better = await lia.sendQuote(again.quote.id, price: 52, crewPay: 30);
    expect(
      (better.status, better.price, better.crewPay),
      (QuoteStatus.sent, 52, 30),
    );
    expect((await paul.properties()).single.price, 52);

    final accepted = await paul.acceptQuote(again.quote.id);
    expect(accepted.property.status, PropertyStatus.active);
    expect(accepted.property.price, 52);
    expect(
      (await paul.acceptQuote(again.quote.id)).quote.status,
      QuoteStatus.accepted,
    );
    await expectApiError(
      paul.declineQuote(again.quote.id),
      409,
      'quote_not_open',
    );
    expect((await paul.quotes()).map((q) => (q.id, q.status)), [
      (again.quote.id, QuoteStatus.accepted),
      ('quote_birch', QuoteStatus.declined),
    ]);

    final job = await paul.requestJob(propertyId: 'prop_birch');
    expect((job.price, job.total), (52, 52));
    expect((await lia.job(job.id)).crewPay, 30);
  });

  test('a new price applies to later requests only', () async {
    final first = await sarah.requestJob(propertyId: 'prop_maple');
    expect(first.price, 45);

    final repriced = await lia.setPropertyPrice(
      'prop_maple',
      price: 50,
      crewPay: 28,
    );
    expect(
      (repriced.id, repriced.status),
      ('prop_maple', PropertyStatus.active),
    );
    expect((repriced.price, repriced.crewPay), (50, 28));
    expect((repriced.activeJob?.id, repriced.activeJob?.price), (first.id, 45));
    expect((await sarah.properties()).first.price, 50);

    final running = await lia.job(first.id);
    expect((running.price, running.total, running.crewPay), (45, 45, 25));
    await plough(marcus, first.id);
    expect((await sarah.job(first.id)).total, 45);

    final second = await sarah.requestJob(
      propertyId: 'prop_maple',
      shovel: true,
    );
    expect((second.price, second.shovelPrice, second.total), (50, 20, 70));
    expect((await lia.job(second.id)).crewPay, 38);
    final earlier = await lia.job('job_maple_3');
    expect((earlier.price, earlier.crewPay), (45, 25));

    await expectApiError(
      lia.setPropertyPrice('prop_birch', price: 50, crewPay: 30),
      409,
      'invalid_state',
    );
    await expectApiError(
      lia.setPropertyPrice('prop_maple', price: 50, crewPay: 51),
      400,
      'validation',
    );
    await expectApiError(
      lia.setPropertyPrice('prop_nowhere', price: 50, crewPay: 30),
      404,
      'not_found',
    );
  });

  test('shovelling is priced by the settings at request time', () async {
    final updated = await lia.updateSettings(
      shovelPrice: 30,
      crewShovelBonus: 12,
    );
    expect((updated.shovelPrice, updated.crewShovelBonus), (30, 12));
    expect(updated.openJobExpiryHours, 48);
    expect((await sarah.settings()).shovelPrice, 30);
    expect((await marcus.settings()).crewShovelBonus, 12);

    final job = await sarah.requestJob(propertyId: 'prop_maple', shovel: true);
    expect((job.price, job.shovelPrice, job.total), (45, 30, 75));
    final open = await marcus.jobs(scope: 'open');
    expect(open.map((j) => (j.id, j.crewPay)), [
      ('job_cedar_2', 40),
      (job.id, 37),
    ]);
    final before = await lia.job('job_cedar_2');
    expect((before.shovelPrice, before.total), (20, 75));

    final rejected = await expectApiError(
      lia.updateSettings(crewShovelBonus: 31),
      400,
      'validation',
    );
    expect(rejected.message, contains('crewShovelBonus'));
    expect((await lia.settings()).crewShovelBonus, 12);
  });

  test('the admin adds a property for a customer', () async {
    final added = await lia.createProperty(
      name: 'Workshop',
      address: '5 Pine Court',
      illustration: 'garage',
      note: 'Behind the house',
      customerId: 'cust_paul',
    );
    expect(
      (added.property.customerId, added.property.customerName),
      ('cust_paul', 'Paul Larson'),
    );
    expect(
      (added.property.illustration, added.property.note),
      ('garage', 'Behind the house'),
    );
    expect(added.property.status, PropertyStatus.quoteRequested);
    expect(
      (added.quote.customerId, added.quote.status),
      ('cust_paul', QuoteStatus.pending),
    );
    expect((await paul.properties()).map((p) => p.id), [
      'prop_birch',
      added.property.id,
    ]);

    await expectApiError(
      lia.createProperty(
        name: 'Workshop',
        address: '5 Pine Court',
        customerId: 'cust_nobody',
      ),
      404,
      'not_found',
    );
    final missing = await expectApiError(
      lia.createProperty(name: 'Workshop', address: '5 Pine Court'),
      400,
      'validation',
    );
    expect(missing.message, contains('customerId'));
    final unnamed = await expectApiError(
      paul.createProperty(name: ' ', address: '5 Pine Court'),
      400,
      'validation',
    );
    expect(unnamed.message, contains('name'));
  });

  test('names and notes keep their accents and symbols', () async {
    const name = 'Chalet Élan';
    const address = '9 Rue de l’Érable, Québec';
    const note = 'Entrée côté nord — ❄ 20 cm';

    final added = await paul.createProperty(
      name: name,
      address: address,
      note: note,
    );
    expect(
      (added.property.name, added.property.address, added.property.note),
      (name, address, note),
    );
    final seen = await lia.quote(added.quote.id);
    expect((seen.propertyName, seen.address, seen.note), (name, address, note));
  });
}

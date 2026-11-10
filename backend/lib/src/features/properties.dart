import 'package:shelf/shelf.dart';

import '../app.dart';
import '../auth/tokens.dart';
import '../data/docs.dart';
import '../data/store.dart';
import '../errors.dart';
import '../http.dart';
import '../model.dart';
import '../routes.dart';
import '../time.dart';
import 'views.dart';

/// Properties and their quotes.
void mountProperties(Routes r, App app) {
  final store = app.store;

  /// Adds a pending quote for [property] and points the property at it.
  ({Doc property, Doc quote}) requestQuote(Tx tx, Doc property) {
    final quote = tx.insert(
      Collections.quotes,
      quoteDoc(id: newId('quote'), property: property, createdAt: app.now()),
    );
    final updated = tx.put(Collections.properties, {
      ...property,
      'status': PropertyStatus.quoteRequested,
      'price': null,
      'crewPay': null,
      'quoteId': quote['id'],
    });
    return (property: updated, quote: quote);
  }

  r.get('/properties', (Request req) {
    final ctx = authOf(req, roles: {Role.customer, Role.admin});
    final status = queryEnum(req, 'status', PropertyStatus.all);
    final customerId = ctx.isAdmin
        ? queryString(req, 'customerId')
        : ctx.customerId;
    final found = store.where(
      Collections.properties,
      (p) =>
          (customerId == null || p['customerId'] == customerId) &&
          (status == null || p['status'] == status),
    );
    sortByTime(found, 'createdAt');
    return jsonOk(found.map(Views.of(store, ctx).property).toList());
  });

  r.post('/properties', (Request req) async {
    final ctx = authOf(req, roles: {Role.customer, Role.admin});
    final body = await readJson(req);
    final customerId = ctx.isAdmin
        ? reqString(body, 'customerId', max: 200)
        : ctx.customerId!;
    final name = reqString(body, 'name', max: 60);
    final address = reqString(body, 'address', max: 160);
    final illustration =
        optEnum(body, 'illustration', illustrations) ?? illustrations.first;
    final note = optString(body, 'note', max: 500);

    final created = store.tx((tx) {
      tx.require(Collections.customers, customerId, what: 'Customer');
      return requestQuote(
        tx,
        propertyDoc(
          id: newId('prop'),
          customerId: customerId,
          name: name,
          address: address,
          illustration: illustration,
          note: note,
          quoteId: '',
          createdAt: app.now(),
        ),
      );
    });
    final views = Views.of(store, ctx);
    return jsonCreated({
      'property': views.property(created.property),
      'quote': views.quote(created.quote),
    });
  });

  r.post('/properties/<id>/request-quote', (Request req, String id) {
    final ctx = authOf(req, roles: {Role.customer});
    final created = store.tx((tx) {
      final property = _owned(tx, Collections.properties, id, ctx, 'Property');
      if (property['status'] != PropertyStatus.declined) {
        throw ApiError.invalidState(
          'A new quote can only be requested after declining the last one.',
        );
      }
      return requestQuote(tx, property);
    });
    final views = Views.of(store, ctx);
    return jsonOk({
      'property': views.property(created.property),
      'quote': views.quote(created.quote),
    });
  });

  r.post('/properties/<id>/price', (Request req, String id) async {
    final ctx = authOf(req, roles: {Role.admin});
    store.require(Collections.properties, id, what: 'Property');
    final (:price, :crewPay) = _offer(await readJson(req));
    final property = store.tx((tx) {
      final current = tx.require(Collections.properties, id, what: 'Property');
      if (current['status'] != PropertyStatus.active) {
        throw ApiError.invalidState(
          'Only a property with an accepted quote can be re-priced.',
        );
      }
      return tx.patch(Collections.properties, id, {
        'price': price,
        'crewPay': crewPay,
      });
    });
    return jsonOk(Views.of(store, ctx).property(property));
  });

  r.get('/quotes', (Request req) {
    final ctx = authOf(req, roles: {Role.customer, Role.admin});
    final status = queryEnum(req, 'status', QuoteStatus.all);
    final found = store.where(
      Collections.quotes,
      (q) =>
          (ctx.isAdmin || q['customerId'] == ctx.customerId) &&
          (status == null || q['status'] == status),
    );
    sortByTime(found, 'createdAt', descending: true);
    return jsonOk(found.map(Views.of(store, ctx).quote).toList());
  });

  r.get('/quotes/<id>', (Request req, String id) {
    final ctx = authOf(req, roles: {Role.customer, Role.admin});
    final quote = _owned(store, Collections.quotes, id, ctx, 'Quote');
    return jsonOk(Views.of(store, ctx).quote(quote));
  });

  r.post('/quotes/<id>/send', (Request req, String id) async {
    final ctx = authOf(req, roles: {Role.admin});
    store.require(Collections.quotes, id, what: 'Quote');
    final (:price, :crewPay) = _offer(await readJson(req));
    final quote = store.tx((tx) {
      final current = tx.require(Collections.quotes, id, what: 'Quote');
      if (current['status'] != QuoteStatus.pending &&
          current['status'] != QuoteStatus.sent) {
        throw ApiError.quoteNotOpen();
      }
      tx.patch(Collections.properties, current['propertyId'] as String, {
        'status': PropertyStatus.quoted,
        'price': price,
        'crewPay': crewPay,
      }, what: 'Property');
      return tx.patch(Collections.quotes, id, {
        'status': QuoteStatus.sent,
        'price': price,
        'crewPay': crewPay,
        'sentAt': isoTime(app.now()),
      });
    });
    return jsonOk(Views.of(store, ctx).quote(quote));
  });

  /// Accepts or declines a sent quote; repeating the same decision is a
  /// no-op that returns the current state.
  Response decide(Request req, String id, {required bool accept}) {
    final ctx = authOf(req, roles: {Role.customer});
    final decision = accept ? QuoteStatus.accepted : QuoteStatus.declined;
    final decided = store.tx((tx) {
      final quote = _owned(tx, Collections.quotes, id, ctx, 'Quote');
      final propertyId = quote['propertyId'] as String;
      if (quote['status'] == decision) {
        return (
          quote: quote,
          property: tx.require(
            Collections.properties,
            propertyId,
            what: 'Property',
          ),
        );
      }
      if (quote['status'] != QuoteStatus.sent) throw ApiError.quoteNotOpen();
      return (
        quote: tx.patch(Collections.quotes, id, {
          'status': decision,
          'decidedAt': isoTime(app.now()),
        }),
        property: tx.patch(Collections.properties, propertyId, {
          'status': accept ? PropertyStatus.active : PropertyStatus.declined,
        }, what: 'Property'),
      );
    });
    final views = Views.of(store, ctx);
    return jsonOk({
      'quote': views.quote(decided.quote),
      'property': views.property(decided.property),
    });
  }

  r.post(
    '/quotes/<id>/accept',
    (Request req, String id) => decide(req, id, accept: true),
  );
  r.post(
    '/quotes/<id>/decline',
    (Request req, String id) => decide(req, id, accept: false),
  );
}

/// `collection/id` if the caller may see it: admins anything, customers
/// only their own. Anything else is 404, as if it did not exist.
Doc _owned(
  DocReader db,
  String collection,
  String id,
  AuthCtx ctx,
  String what,
) {
  final doc = db.get(collection, id);
  if (doc == null || (!ctx.isAdmin && doc['customerId'] != ctx.customerId)) {
    throw ApiError.notFound(what);
  }
  return doc;
}

/// The `{price, crewPay}` of a quote or a re-price.
({int price, int crewPay}) _offer(Map<String, dynamic> body) {
  final price = reqInt(body, 'price', min: 1, max: 10000);
  return (price: price, crewPay: reqInt(body, 'crewPay', min: 0, max: price));
}

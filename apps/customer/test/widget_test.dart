// Smoke tests: the real app widget tree, booted against a mocked HTTP API.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:redefine_customer/api.dart';
import 'package:redefine_customer/screens/add_property.dart';
import 'package:redefine_customer/screens/billing_screen.dart';
import 'package:redefine_customer/screens/home_screen.dart';
import 'package:redefine_customer/screens/job_detail.dart';
import 'package:redefine_customer/widgets.dart';
import 'package:redefine_ui/redefine_ui.dart';

import 'support/fake_api.dart';

/// Sarah's account much as the demo seed has it: an active property with a
/// finished job, and a second property still waiting for its quote.
FakeApi seeded({String mode = 'manual'}) {
  final server = FakeApi(mode: mode);
  final maple = server.addProperty(
    id: 'prop_maple',
    name: 'Maple Street home',
    address: '412 Maple St, Thunder Bay, ON',
    price: 45,
  );
  server.addProperty(
    id: 'prop_cabin',
    name: 'Cabin',
    address: '88 Lakeside Rd',
    illustration: 'cabin',
    status: 'quoteRequested',
    note: 'Long gravel driveway.',
  );
  server.addJob(
    maple,
    status: 'done',
    shovel: true,
    paymentStatus: 'paid',
    paymentMode: 'manual',
    crewNote: 'Cleared the steps too.',
    ago: const Duration(days: 9),
  );
  return server;
}

/// Replaces the external-link opener for the test and records what it is
/// asked to open.
List<Uri> captureOpenedLinks() {
  final opened = <Uri>[];
  final original = openExternal;
  openExternal = (uri) async {
    opened.add(uri);
    return true;
  };
  addTearDown(() => openExternal = original);
  return opened;
}

Future<void> tapText(WidgetTester tester, String text) async {
  await tester.tap(find.text(text));
  await settle(tester);
}

/// Lets [time] pass (a poll interval, say) and the resulting requests land.
Future<void> wait(WidgetTester tester, Duration time) async {
  await tester.pump(time);
  await settle(tester);
}

/// Takes the app's window off screen, as when the customer switches to
/// another browser tab. Undo with [showWindow], also when the test fails.
void hideWindow(WidgetTester tester) => tester.binding
  ..handleAppLifecycleStateChanged(AppLifecycleState.inactive)
  ..handleAppLifecycleStateChanged(AppLifecycleState.hidden);

void showWindow(WidgetTester tester) => tester.binding
  ..handleAppLifecycleStateChanged(AppLifecycleState.inactive)
  ..handleAppLifecycleStateChanged(AppLifecycleState.resumed);

void main() {
  group('signing in', () {
    testWidgets('signs in and shows the customer\'s properties, price and past ploughs', (
      tester,
    ) async {
      final server = seeded();
      final session = await pumpApp(tester, server, signedIn: false);

      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.text('HOMEOWNER'), findsOneWidget);
      expect(find.text('Request a plough when it snows.'), findsOneWidget);
      expect(server.requests, isEmpty);

      // The demo credentials are prefilled in debug builds.
      await tapText(tester, 'Log in');

      expect(session.status, SessionStatus.signedIn);
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.text('Hi Sarah!'), findsOneWidget);
      // Both properties are tabs; the first is selected and headed.
      expect(find.text('Maple Street home'), findsNWidgets(2));
      expect(find.text('Cabin'), findsOneWidget);
      expect(find.text('412 Maple St, Thunder Bay, ON'), findsOneWidget);
      // Its price, the shovelling extra from settings and the request button.
      expect(find.text('Your price per plough'), findsOneWidget);
      expect(find.text('\$45'), findsNWidgets(2));
      expect(find.text('Add shovelling +\$20'), findsOneWidget);
      expect(find.text('Billed after the job.'), findsOneWidget);
      expect(find.text('Request plough · \$45'), findsOneWidget);
      // The finished job from GET /jobs.
      expect(find.text('PAST PLOUGHS'), findsOneWidget);
      expect(find.text('Marcus Reid · 47 min · with shovelling'), findsOneWidget);
      expect(find.text('\$65'), findsOneWidget);
      expect(find.text('Paid'), findsOneWidget);

      expect(
        server.requests,
        containsAll([
          'POST /auth/login',
          'GET /properties',
          'GET /settings',
          'GET /billing',
          'GET /jobs',
        ]),
      );
      await unmount(tester);
    });

    testWidgets('signs up as a customer, with the optional phone number', (tester) async {
      final server = FakeApi();
      final session = await pumpApp(tester, server, signedIn: false);

      await tapText(tester, 'Sign up');
      expect(find.byType(SignupScreen), findsOneWidget);
      expect(find.text('PHONE (OPTIONAL)'), findsOneWidget);
      final fields = find.descendant(
        of: find.byType(SignupScreen),
        matching: find.byType(TextField),
      );
      await tester.enterText(fields.at(0), 'Noor Haddad');
      await tester.enterText(fields.at(1), '(807) 555-0199');
      await tester.enterText(fields.at(2), 'noor@example.com');
      await tester.enterText(fields.at(3), 'snowfall-24');
      await tapText(tester, 'Create account');

      expect(server.bodies['POST /auth/signup'], {
        'name': 'Noor Haddad',
        'email': 'noor@example.com',
        'password': 'snowfall-24',
        'role': 'customer',
        'phone': '(807) 555-0199',
      });
      expect(session.status, SessionStatus.signedIn);
      expect(find.byType(SignupScreen), findsNothing);
      expect(find.text('Hi Noor!'), findsOneWidget);
      expect(find.text('Snow cleared, on demand'), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('restores a stored session straight to the home screen', (tester) async {
      final server = seeded();
      await pumpApp(tester, server);

      expect(find.byType(LoginScreen), findsNothing);
      expect(find.text('Hi Sarah!'), findsOneWidget);
      expect(find.text('Request plough · \$45'), findsOneWidget);
      expect(server.requests.first, 'GET /auth/me');
      expect(server.count('POST /auth/login'), 0);
      await unmount(tester);
    });

    testWidgets('a failed first load offers Retry instead of spinning', (tester) async {
      final server = seeded();
      server.failOnce['GET /properties'] = errorResponse(
        503,
        'storage_unavailable',
        'The service is busy. Try again.',
      );
      await pumpApp(tester, server);

      expect(find.text('The service is busy. Try again.'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      await tapText(tester, 'Retry');
      expect(find.text('Request plough · \$45'), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('a customer without properties is invited to add one', (tester) async {
      final server = FakeApi();
      await pumpApp(tester, server);

      expect(find.text('Snow cleared, on demand'), findsOneWidget);
      await tapText(tester, 'Add your first property');
      expect(find.byType(AddPropertyScreen), findsOneWidget);
      await unmount(tester);
    });
  });

  group('refreshing', () {
    testWidgets('polling reloads the properties but not settings or billing', (tester) async {
      final server = seeded();
      await pumpApp(tester, server);
      expect(server.count('GET /properties'), 1);

      // A quote is awaited, so the properties are polled every 15 seconds.
      await wait(tester, const Duration(seconds: 15));
      await wait(tester, const Duration(seconds: 15));
      expect(server.count('GET /properties'), 3);
      expect(server.count('GET /settings'), 1);
      expect(server.count('GET /billing'), 1);
      await unmount(tester);
    });

    testWidgets('a pull to refresh also reloads settings, billing and past ploughs', (
      tester,
    ) async {
      final server = seeded();
      await pumpApp(tester, server);
      final historyLoads = server.count('GET /jobs');

      server.shovelPrice = 25;
      await tester.drag(find.text('Your price per plough'), const Offset(0, 300));
      await wait(tester, const Duration(seconds: 1));

      expect(server.count('GET /properties'), 2);
      expect(server.count('GET /settings'), 2);
      expect(server.count('GET /billing'), 2);
      expect(server.count('GET /jobs'), historyLoads + 1);
      expect(find.text('Add shovelling +\$25'), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('Refresh in the account menu reloads everything', (tester) async {
      final server = seeded();
      final due = server.addJob(
        server.properties.first,
        status: 'done',
        paymentStatus: 'due',
        ago: const Duration(days: 1),
      );
      await pumpApp(tester, server);
      expect(find.text('Due'), findsOneWidget);
      expect(find.text('Paid'), findsOneWidget);

      // The office changes both prices and marks the job paid.
      server.shovelPrice = 30;
      server.properties.first['price'] = 50;
      (due['payment']! as Json)['status'] = 'paid';
      await tester.tap(find.byType(RAvatar));
      await settle(tester);
      expect(find.text('sarah.m@gmail.com'), findsOneWidget);
      final settings = server.count('GET /settings');
      final billing = server.count('GET /billing');
      final history = server.count('GET /jobs');
      // Closing the menu reloads the properties by itself (RLive does that
      // whenever a popup closes). That reload is made to fail, so the new
      // price can only come from the one Refresh asks for.
      server.failOnce['GET /properties'] = errorResponse(503, 'storage_unavailable', 'Busy.');
      await tapText(tester, 'Refresh');

      expect(find.text('Request plough · \$50'), findsOneWidget);
      expect(server.count('GET /settings'), settings + 1);
      expect(server.count('GET /billing'), billing + 1);
      expect(server.count('GET /jobs'), history + 1);
      expect(find.text('Add shovelling +\$30'), findsOneWidget);
      expect(find.text('Due'), findsNothing);
      expect(find.text('Paid'), findsNWidgets(2));
      expect(find.byType(SnackBar), findsNothing);
      await unmount(tester);
    });

    testWidgets('a refresh that leaves old details on screen says so', (tester) async {
      final server = seeded();
      await pumpApp(tester, server);

      // Pulled: the properties reload, billing does not.
      server.shovelPrice = 25;
      server.failOnce['GET /billing'] = errorResponse(500, 'internal', 'Billing is down.');
      await tester.drag(find.text('Your price per plough'), const Offset(0, 300));
      await wait(tester, const Duration(seconds: 1));
      expect(find.text('Some details could not be refreshed. Billing is down.'), findsOneWidget);
      expect(find.text('Add shovelling +\$20'), findsOneWidget);

      // From the menu: this time the past ploughs do not reload.
      server.failOnce['GET /jobs'] = errorResponse(500, 'internal', 'History is down.');
      await tester.tap(find.byType(RAvatar));
      await settle(tester);
      await tapText(tester, 'Refresh');
      expect(find.text('Some details could not be refreshed. History is down.'), findsOneWidget);
      expect(find.text('Add shovelling +\$25'), findsOneWidget);
      expect(find.text('Marcus Reid · 47 min · with shovelling'), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('coming back from Billing says so when billing cannot be reloaded', (tester) async {
      final server = seeded(mode: 'stripe');
      await pumpApp(tester, server);
      await tapText(tester, 'Add a card');
      expect(find.byType(BillingScreen), findsOneWidget);

      server.saveCard();
      server.failOnce['GET /billing'] = errorResponse(500, 'internal', 'Billing is down.');
      await tapText(tester, 'Back');

      expect(find.text('Some details could not be refreshed. Billing is down.'), findsOneWidget);
      expect(find.text('Add a card to request ploughs'), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('coming back to the window reloads settings, billing and past ploughs', (
      tester,
    ) async {
      addTearDown(() => showWindow(tester));
      final server = seeded();
      final due = server.addJob(
        server.properties.first,
        status: 'done',
        paymentStatus: 'due',
        ago: const Duration(days: 1),
      );
      await pumpApp(tester, server);
      expect(find.text('Due'), findsOneWidget);

      hideWindow(tester);
      await tester.pump();
      // Meanwhile the office marks the job paid and changes the shovelling price.
      (due['payment']! as Json)['status'] = 'paid';
      server.shovelPrice = 25;
      showWindow(tester);
      await settle(tester);

      expect(find.text('Due'), findsNothing);
      expect(find.text('Paid'), findsNWidgets(2));
      expect(find.text('Add shovelling +\$25'), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('past ploughs that fail to load can be retried in place', (tester) async {
      final server = seeded();
      server.failOnce['GET /jobs'] = errorResponse(500, 'internal', 'Something broke.');
      await pumpApp(tester, server);

      expect(find.text('Request plough · \$45'), findsOneWidget);
      expect(find.text('Something broke.'), findsOneWidget);
      await tapText(tester, 'Retry');
      expect(find.text('Marcus Reid · 47 min · with shovelling'), findsOneWidget);
      await unmount(tester);
    });
  });

  group('requesting a plough', () {
    testWidgets('manual mode: confirm the total, follow the job, cancel it', (tester) async {
      final server = seeded();
      await pumpApp(tester, server);

      await tester.tap(find.byType(Switch));
      await tester.pump();
      expect(find.text('Request plough · \$65'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '  Car on the left  ');

      await tapText(tester, 'Request plough · \$65');
      expect(find.text("You'll be billed \$65 after the job."), findsOneWidget);
      expect(server.count('POST /jobs'), 0, reason: 'nothing is sent before confirming');

      await confirm(tester, 'Request plough');
      expect(server.bodies['POST /jobs'], {
        'propertyId': 'prop_maple',
        'shovel': true,
        'note': 'Car on the left',
      });
      expect(
        find.text('Plough requested. The crew that accepts it shows up here.'),
        findsOneWidget,
      );
      // The tracker has replaced the request card.
      expect(find.textContaining('Request plough ·'), findsNothing);
      expect(find.text('Waiting for crew'), findsOneWidget);
      expect(find.text('Open to the next available crew'), findsOneWidget);
      expect(find.text('PLOUGH + SHOVEL'), findsOneWidget);
      expect(find.text('Billed after the job'), findsOneWidget);
      expect(find.text('Car on the left'), findsOneWidget);
      expect(find.byType(RStepTracker), findsOneWidget);

      // A crew member accepts; the five-second poll picks it up.
      server.jobs.first
        ..['status'] = 'claimed'
        ..['crewName'] = 'Marcus Reid'
        ..['crewInitials'] = 'MR'
        ..['claimedAt'] = DateTime.now().toUtc().toIso8601String();
      await wait(tester, const Duration(seconds: 5));
      expect(find.text('Marcus Reid is your crew'), findsOneWidget);
      expect(find.text('Crew assigned'), findsNWidgets(2));

      await tapText(tester, 'Cancel request');
      expect(find.text("You won't be billed for it."), findsOneWidget);
      await confirm(tester, 'Cancel request');

      expect(server.jobs.first['status'], 'cancelled');
      expect(find.text('Request cancelled'), findsOneWidget);
      expect(find.text('Request plough · \$45'), findsOneWidget);
      expect(find.text('Cancelled by you'), findsOneWidget);
      // Cancelled here, so the poll has nothing more to announce.
      expect(server.count('GET /jobs/${server.jobs.first['id']}'), 0);
      await unmount(tester);
    });

    testWidgets('announces a job the crew finished, then offers the next request', (tester) async {
      final server = seeded();
      final job = server.addJob(server.properties.first, status: 'inProgress');
      await pumpApp(tester, server);

      expect(find.text('In progress'), findsNWidgets(2));
      expect(find.textContaining('Started '), findsOneWidget);
      expect(find.text('Cancel request'), findsNothing);
      expect(
        find.text("The crew is working, so this request can't be cancelled now."),
        findsOneWidget,
      );

      server.complete(job);
      await wait(tester, const Duration(seconds: 5));

      expect(server.count('GET /jobs/${job['id']}'), 1);
      expect(find.text('Plough complete · \$45 billed'), findsOneWidget);
      expect(find.text('Request plough · \$45'), findsOneWidget);
      expect(find.text('Due'), findsOneWidget);

      // Announced once, however often the properties are polled afterwards.
      await wait(tester, const Duration(minutes: 2));
      expect(server.count('GET /jobs/${job['id']}'), 1);
      await unmount(tester);
    });

    testWidgets('cancelling after the crew started says so and refreshes', (tester) async {
      final server = seeded();
      final job = server.addJob(server.properties.first, status: 'claimed');
      await pumpApp(tester, server);

      job['status'] = 'inProgress';
      job['startedAt'] = DateTime.now().toUtc().toIso8601String();
      await tapText(tester, 'Cancel request');
      // Closing the dialog reloads the properties by itself. That reload is
      // made to fail, so the screen can only catch up through the refresh
      // that the refusal asks for.
      final loads = server.count('GET /properties');
      server.failOnce['GET /properties'] = errorResponse(503, 'storage_unavailable', 'Busy.');
      await confirm(tester, 'Cancel request');

      expect(
        find.text("The crew has already started, so this can't be cancelled now."),
        findsOneWidget,
      );
      expect(server.count('GET /properties'), loads + 2);
      expect(find.text('In progress'), findsNWidgets(2));
      expect(find.text('Cancel request'), findsNothing);
      await unmount(tester);
    });

    testWidgets('the confirmation states the price as it is now, not as it was loaded', (
      tester,
    ) async {
      final server = seeded();
      await pumpApp(tester, server);
      await tester.tap(find.byType(Switch));
      await tester.pump();

      // The office re-prices the property and the shovelling while the
      // screen still shows the old total.
      server.properties.first['price'] = 50;
      server.shovelPrice = 30;
      await tapText(tester, 'Request plough · \$65');

      expect(
        find.text(
          'The price has changed, so the total is now \$80, not \$65. '
          "You'll be billed \$80 after the job.",
        ),
        findsOneWidget,
      );
      expect(server.count('POST /jobs'), 0);

      await confirm(tester, 'Request plough');
      expect(server.jobs.first['total'], 80);
      expect(
        find.text('Plough requested. The crew that accepts it shows up here.'),
        findsOneWidget,
      );
      expect(find.text('\$80'), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('a price that changes while the confirmation is open is reported', (tester) async {
      final server = seeded();
      await pumpApp(tester, server);
      await tester.tap(find.byType(Switch));
      await tester.pump();
      await tapText(tester, 'Request plough · \$65');
      expect(find.text("You'll be billed \$65 after the job."), findsOneWidget);

      server.shovelPrice = 30;
      await confirm(tester, 'Request plough');

      expect(
        find.text(
          'Plough requested, but the price changed as you confirmed: the total is \$75, '
          'not \$65. You can still cancel the request.',
        ),
        findsOneWidget,
      );
      expect(find.text('\$75'), findsOneWidget);
      expect(find.text('Cancel request'), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('a total that cannot be checked is not put up for confirmation', (tester) async {
      final server = seeded();
      await pumpApp(tester, server);

      server.failOnce['GET /settings'] = errorResponse(500, 'internal', 'Settings are down.');
      await tapText(tester, 'Request plough · \$45');
      expect(find.text("Couldn't check the current price. Settings are down."), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
      expect(server.count('POST /jobs'), 0);

      // Nothing is stuck: the next try goes through.
      await tapText(tester, 'Request plough · \$45');
      expect(find.text("You'll be billed \$45 after the job."), findsOneWidget);
      await confirm(tester, 'Request plough');
      expect(server.count('POST /jobs'), 1);
      expect(find.text('Waiting for crew'), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('a request made elsewhere is shown instead of asking to confirm another', (
      tester,
    ) async {
      final server = seeded();
      await pumpApp(tester, server);

      // Requested meanwhile from another device.
      server.addJob(server.properties.first);
      await tapText(tester, 'Request plough · \$45');

      expect(find.byType(AlertDialog), findsNothing);
      expect(server.count('POST /jobs'), 0);
      expect(find.text('Waiting for crew'), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
      await unmount(tester);
    });

    testWidgets('a request that already exists is shown without an error', (tester) async {
      final server = seeded();
      await pumpApp(tester, server);
      await tapText(tester, 'Request plough · \$45');

      // Requested from another device while the confirmation is open. The
      // reload that closing the dialog causes is made to fail, so the job can
      // only show through the refresh that the refusal asks for.
      server.addJob(server.properties.first);
      final loads = server.count('GET /properties');
      server.failOnce['GET /properties'] = errorResponse(503, 'storage_unavailable', 'Busy.');
      await confirm(tester, 'Request plough');

      expect(server.count('POST /jobs'), 1);
      expect(server.jobs, hasLength(2));
      expect(server.count('GET /properties'), loads + 2);
      expect(find.text('Waiting for crew'), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
      await unmount(tester);
    });
  });

  group('when the properties cannot be reloaded after an action', () {
    final unavailable = errorResponse(503, 'storage_unavailable', 'Busy.');

    testWidgets('a request is followed from its own response', (tester) async {
      final server = seeded();
      await pumpApp(tester, server);
      await tapText(tester, 'Request plough · \$45');
      server.failing['GET /properties'] = unavailable;
      await confirm(tester, 'Request plough');

      expect(server.count('POST /jobs'), 1);
      expect(
        find.text('Plough requested. The crew that accepts it shows up here.'),
        findsOneWidget,
      );
      // The properties still say there is no job; the response says there is.
      expect(find.text("Couldn't refresh"), findsOneWidget);
      expect(find.textContaining('Request plough ·'), findsNothing);
      expect(find.text('Waiting for crew'), findsOneWidget);
      expect(find.text('Cancel request'), findsOneWidget);

      // Reloading keeps failing, and keeps being retried at the pace of a job.
      final loads = server.count('GET /properties');
      await wait(tester, const Duration(seconds: 5));
      expect(server.count('GET /properties'), loads + 1);
      expect(find.text('Waiting for crew'), findsOneWidget);

      // Once it works again the properties take over.
      server.failing.clear();
      server.jobs.first
        ..['status'] = 'claimed'
        ..['crewName'] = 'Marcus Reid'
        ..['crewInitials'] = 'MR'
        ..['claimedAt'] = DateTime.now().toUtc().toIso8601String();
      await wait(tester, const Duration(seconds: 5));
      expect(find.text('Marcus Reid is your crew'), findsOneWidget);
      expect(find.text("Couldn't refresh"), findsNothing);
      await unmount(tester);
    });

    testWidgets('a job that ends before they reload is still announced', (tester) async {
      final server = seeded();
      await pumpApp(tester, server);
      await tapText(tester, 'Request plough · \$45');
      server.failing['GET /properties'] = unavailable;
      await confirm(tester, 'Request plough');
      expect(find.text('Waiting for crew'), findsOneWidget);

      server.complete(server.jobs.first);
      server.failing.clear();
      await wait(tester, const Duration(seconds: 5));

      expect(find.text('Plough complete · \$45 billed'), findsOneWidget);
      expect(find.text('Request plough · \$45'), findsOneWidget);
      expect(find.text('Due'), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('a cancellation shows from its own response', (tester) async {
      final server = seeded();
      final job = server.addJob(server.properties.first, status: 'claimed');
      await pumpApp(tester, server);
      await tapText(tester, 'Cancel request');
      server.failing['GET /properties'] = unavailable;
      server.failing['GET /jobs'] = unavailable;
      await confirm(tester, 'Cancel request');

      expect(job['status'], 'cancelled');
      expect(find.text('Request cancelled'), findsOneWidget);
      // The properties still carry the job; the response says it is over.
      expect(find.text("Couldn't refresh"), findsOneWidget);
      expect(find.text('Cancel request'), findsNothing);
      expect(find.text('Request plough · \$45'), findsOneWidget);
      expect(find.text('Cancelled by you'), findsOneWidget);

      await wait(tester, const Duration(seconds: 5));
      expect(find.text('Cancel request'), findsNothing);

      server.failing.clear();
      await wait(tester, const Duration(seconds: 5));
      expect(find.text("Couldn't refresh"), findsNothing);
      expect(find.text('Request plough · \$45'), findsOneWidget);
      // Cancelled here, so there is nothing more to announce.
      expect(server.count('GET /jobs/${job['id']}'), 0);
      await unmount(tester);
    });
  });

  group('paying by card', () {
    testWidgets('saves a card through Stripe, then requests with a hold', (tester) async {
      final server = seeded(mode: 'stripe');
      final opened = captureOpenedLinks();
      await pumpApp(tester, server);

      expect(find.text('Add a card to request ploughs'), findsOneWidget);
      expect(find.textContaining('Request plough ·'), findsNothing);

      await tapText(tester, 'Add a card');
      expect(find.byType(BillingScreen), findsOneWidget);
      expect(find.text('No card on file'), findsOneWidget);

      // First tap: the server prepares the Stripe page. Nothing opens yet.
      await tapText(tester, 'Add card');
      expect(server.count('POST /billing/setup-session'), 1);
      expect(opened, isEmpty);

      // Second tap: the page opens within the tap itself.
      await tester.tap(find.text('Continue to Stripe'));
      expect(opened, [Uri.parse(FakeApi.stripeUrl)]);
      await tester.pump();
      expect(find.text('Waiting for Stripe…'), findsOneWidget);

      await wait(tester, const Duration(seconds: 3));
      expect(server.count('POST /billing/refresh'), 1);
      expect(find.text('Waiting for Stripe…'), findsOneWidget);

      server.saveCard();
      await wait(tester, const Duration(seconds: 3));
      expect(find.text('Card saved · Visa ending 4242'), findsOneWidget);
      expect(find.text('Visa ending 4242'), findsOneWidget);
      expect(find.text('Expires 04/31'), findsOneWidget);
      expect(find.text('Replace card'), findsOneWidget);
      expect(find.text('Waiting for Stripe…'), findsNothing);

      // The watch is over.
      final checks = server.count('POST /billing/refresh');
      await wait(tester, const Duration(seconds: 30));
      expect(server.count('POST /billing/refresh'), checks);

      await tapText(tester, 'Back');
      expect(find.byType(BillingScreen), findsNothing);
      await tapText(tester, 'Request plough · \$45');
      expect(
        find.text(
          "We'll place a hold of \$45 on your Visa ending 4242. "
          "You're charged only when the job is done.",
        ),
        findsOneWidget,
      );
      await confirm(tester, 'Request plough');
      expect(find.text('Hold placed on your card'), findsOneWidget);

      await tapText(tester, 'Cancel request');
      expect(find.text('The hold of \$45 on your card will be released.'), findsOneWidget);
      await confirm(tester, 'Cancel request');
      expect(find.text('Request cancelled · hold released'), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('the watch for the card can be checked by hand, reopened and cancelled', (
      tester,
    ) async {
      final server = seeded(mode: 'stripe')..saveCard(last4: '1111');
      final opened = captureOpenedLinks();
      await pumpApp(tester, server);
      await tester.tap(find.byType(RAvatar));
      await settle(tester);
      await tapText(tester, 'Billing');
      expect(find.text('Visa ending 1111'), findsOneWidget);

      await tapText(tester, 'Replace card');
      await tester.tap(find.text('Continue to Stripe'));
      await tester.pump();

      await tapText(tester, "I've finished — check now");
      expect(
        find.text('No new card yet. Save it on the Stripe page, then check again.'),
        findsOneWidget,
      );
      expect(find.text('Waiting for Stripe…'), findsOneWidget);

      await tester.tap(find.text('Open Stripe again'));
      await tester.pump();
      expect(opened, hasLength(2));

      await tapText(tester, 'Cancel');
      expect(find.text('Waiting for Stripe…'), findsNothing);
      expect(find.text('Visa ending 1111'), findsOneWidget);
      final checks = server.count('POST /billing/refresh');
      await wait(tester, const Duration(seconds: 30));
      expect(server.count('POST /billing/refresh'), checks);

      // The unfinished setup can still be picked up later.
      expect(find.text('A card setup was started but not finished.'), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
      server.saveCard(brand: 'mastercard', last4: '4444');
      await tapText(tester, 'Check now');
      expect(find.text('Mastercard ending 4444'), findsOneWidget);
      expect(find.text('A card setup was started but not finished.'), findsNothing);
      await unmount(tester);
    });

    testWidgets('stops checking by itself after ten minutes', (tester) async {
      final server = seeded(mode: 'stripe');
      captureOpenedLinks();
      await pumpApp(tester, server);
      await tapText(tester, 'Add a card');
      await tapText(tester, 'Add card');
      await tester.tap(find.text('Continue to Stripe'));
      await tester.pump();

      await wait(tester, const Duration(minutes: 11));
      expect(server.count('POST /billing/refresh'), 200);
      expect(find.textContaining("We've stopped checking by ourselves."), findsOneWidget);
      await wait(tester, const Duration(minutes: 1));
      expect(server.count('POST /billing/refresh'), 200);

      server.saveCard();
      await tapText(tester, "I've finished — check now");
      expect(find.text('Visa ending 4242'), findsOneWidget);
      await unmount(tester);
    });

    const refusals = {
      'card_declined': 'Your card was declined.',
      'card_auth_required': 'Your bank wants you to approve this card again.',
    };
    for (final MapEntry(key: code, value: message) in refusals.entries) {
      testWidgets('a card refused with $code is explained with a way to update it', (tester) async {
        final server = seeded(mode: 'stripe')..saveCard();
        await pumpApp(tester, server);

        server.failOnce['POST /jobs'] = errorResponse(402, code, message);
        await tapText(tester, 'Request plough · \$45');
        await confirm(tester, 'Request plough');

        expect(find.text(message), findsOneWidget);
        expect(find.byType(SnackBar), findsNothing);
        expect(find.text('Request plough · \$45'), findsOneWidget);
        expect(server.jobs, hasLength(1));

        await tapText(tester, 'Update card');
        expect(find.byType(BillingScreen), findsOneWidget);
        expect(find.text('Replace card'), findsOneWidget);
        await unmount(tester);
      });
    }

    testWidgets('a card that is gone is asked for before anything is confirmed', (tester) async {
      final server = seeded(mode: 'stripe')..saveCard();
      await pumpApp(tester, server);

      // The card was removed after this screen loaded.
      server.card = null;
      await tapText(tester, 'Request plough · \$45');

      expect(find.byType(AlertDialog), findsNothing);
      expect(server.count('POST /jobs'), 0);
      expect(find.byType(BillingScreen), findsOneWidget);
      expect(find.text('Add a card to request a plough.'), findsOneWidget);
      expect(find.text('No card on file'), findsOneWidget);

      await tapText(tester, 'Back');
      expect(find.text('Add a card to request ploughs'), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('a request refused for want of a card opens Billing', (tester) async {
      final server = seeded(mode: 'stripe')..saveCard();
      await pumpApp(tester, server);
      await tapText(tester, 'Request plough · \$45');

      // The card is removed while the confirmation is open.
      server.card = null;
      await confirm(tester, 'Request plough');

      expect(server.count('POST /jobs'), 1);
      expect(find.byType(BillingScreen), findsOneWidget);
      expect(find.text('Add a card to request a plough.'), findsOneWidget);
      expect(find.text('No card on file'), findsOneWidget);

      await tapText(tester, 'Back');
      expect(find.text('Add a card to request ploughs'), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('coming back to the window checks for the card at once', (tester) async {
      addTearDown(() => showWindow(tester));
      final server = seeded(mode: 'stripe');
      captureOpenedLinks();
      await pumpApp(tester, server);
      await tapText(tester, 'Add a card');
      await tapText(tester, 'Add card');
      await tester.tap(find.text('Continue to Stripe'));
      await tester.pump();
      expect(find.text('Waiting for Stripe…'), findsOneWidget);
      expect(server.count('POST /billing/refresh'), 0);

      // Off to the Stripe tab, where the card is saved, and back within the
      // three seconds between two automatic checks.
      hideWindow(tester);
      await tester.pump(const Duration(seconds: 1));
      server.saveCard();
      showWindow(tester);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      expect(server.count('POST /billing/refresh'), 1);
      expect(find.text('Card saved · Visa ending 4242'), findsOneWidget);
      expect(find.text('Waiting for Stripe…'), findsNothing);
      await unmount(tester);
    });

    testWidgets('manual mode needs no card and lists what is due', (tester) async {
      final server = seeded();
      server.addJob(
        server.properties.first,
        status: 'done',
        paymentStatus: 'due',
        ago: const Duration(days: 1),
      );
      await pumpApp(tester, server);
      await tester.tap(find.byType(RAvatar));
      await settle(tester);
      await tapText(tester, 'Billing');

      expect(find.text("No card needed — you're billed after each job"), findsOneWidget);
      expect(find.text('Add card'), findsNothing);
      expect(find.text('Balance due'), findsOneWidget);
      expect(find.text('For finished jobs that are not paid yet.'), findsOneWidget);
      expect(find.text('Yesterday · Plough'), findsOneWidget);
      expect(find.text('Due'), findsOneWidget);
      expect(find.text('Paid'), findsOneWidget);

      await tapText(tester, 'Yesterday · Plough');
      expect(find.byType(JobDetailScreen), findsOneWidget);
      expect(find.text('\$45 is due for this job.'), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('adding a card after cards were switched off falls back to manual', (tester) async {
      final server = seeded(mode: 'stripe');
      await pumpApp(tester, server);
      await tapText(tester, 'Add a card');

      server.mode = 'manual';
      await tapText(tester, 'Add card');

      expect(find.text('Continue to Stripe'), findsNothing);
      expect(find.text("No card needed — you're billed after each job"), findsOneWidget);
      await unmount(tester);
    });
  });

  group('quotes', () {
    FakeApi quoted() {
      final server = seeded();
      server.addProperty(
        id: 'prop_birch',
        name: 'Birch Road home',
        address: '21 Birch Rd',
        status: 'quoted',
        price: 60,
      );
      return server;
    }

    testWidgets('a waiting property shows the steps and its note', (tester) async {
      final server = seeded();
      await pumpApp(tester, server);

      await tapText(tester, 'Cabin');
      expect(find.text('Your quote is on the way'), findsOneWidget);
      expect(find.text('We visit and price your driveway'), findsOneWidget);
      expect(find.text('This screen updates when your quote is ready.'), findsOneWidget);
      expect(find.text('Long gravel driveway.'), findsOneWidget);

      // The quote arrives; the quote-wait poll shows it.
      server.properties[1]
        ..['status'] = 'quoted'
        ..['price'] = 80;
      await wait(tester, const Duration(seconds: 15));
      expect(find.text('Your price is in'), findsOneWidget);
      expect(find.text('\$80'), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('a quote opens first and can be accepted', (tester) async {
      final server = quoted();
      await pumpApp(tester, server);

      expect(find.text('Your price is in'), findsOneWidget);
      expect(find.text('\$60'), findsOneWidget);
      expect(find.text('per plough'), findsOneWidget);
      expect(find.text('Shovelling walkways and steps: +\$20 when you want it'), findsOneWidget);
      expect(find.text("You're billed after each job."), findsOneWidget);

      await tapText(tester, 'Accept quote');
      expect(server.requests, contains('POST /quotes/quote_prop_birch/accept'));
      expect(find.text('Quote accepted. Request a plough whenever it snows.'), findsOneWidget);
      expect(find.text('Request plough · \$60'), findsOneWidget);
      expect(find.text('No ploughs yet.'), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('a quote can be declined, and a new one asked for', (tester) async {
      final server = quoted();
      await pumpApp(tester, server);

      await tapText(tester, 'Decline');
      expect(server.count('POST /quotes/quote_prop_birch/decline'), 0);
      await confirm(tester, 'Decline quote');
      expect(find.text('You declined this quote.'), findsOneWidget);

      await tapText(tester, 'Ask for a new quote');
      expect(server.requests, contains('POST /properties/prop_birch/request-quote'));
      expect(find.text('Your quote is on the way'), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('a quote that is no longer open is refreshed, not failed', (tester) async {
      final server = quoted();
      await pumpApp(tester, server);

      // Declined meanwhile from another device.
      server.properties.last['status'] = 'declined';
      await tapText(tester, 'Accept quote');

      expect(find.text('This quote has changed. Showing the latest.'), findsOneWidget);
      expect(find.text('You declined this quote.'), findsOneWidget);
      await unmount(tester);
    });
  });

  group('adding a property', () {
    testWidgets('picks an illustration, validates, creates and selects the property', (
      tester,
    ) async {
      final server = seeded();
      await pumpApp(tester, server);

      await tapText(tester, 'Add property');
      expect(find.text('Pick an illustration'), findsOneWidget);
      await tester.tap(find.byIcon(illustrationIcon('farmhouse')));
      await tapText(tester, 'Continue');

      expect(find.text('Tell us about your driveway'), findsOneWidget);
      // The contact details come from the session.
      expect(find.text('Sarah Mitchell'), findsOneWidget);
      expect(find.text('sarah.m@gmail.com'), findsOneWidget);
      expect(find.text('(807) 555-0142'), findsOneWidget);

      await tapText(tester, 'Request a quote');
      expect(find.text('Give this property a name.'), findsOneWidget);
      expect(find.text('Enter the address to plough.'), findsOneWidget);
      expect(server.count('POST /properties'), 0);

      // Back from the details returns to the illustrations, not home.
      await tapText(tester, 'Back to illustrations');
      expect(find.text('Pick an illustration'), findsOneWidget);
      await tapText(tester, 'Continue');

      final fields = find.descendant(
        of: find.byType(AddPropertyScreen),
        matching: find.byType(TextField),
      );
      await tester.enterText(fields.at(0), 'Farm');
      await tester.enterText(fields.at(1), '9 Concession Rd');
      await tester.enterText(fields.at(2), 'Mind the hedge');
      await tapText(tester, 'Request a quote');

      expect(server.bodies['POST /properties'], {
        'name': 'Farm',
        'address': '9 Concession Rd',
        'illustration': 'farmhouse',
        'note': 'Mind the hedge',
      });
      expect(find.byType(AddPropertyScreen), findsNothing);
      // The new property is the selected tab.
      expect(find.text('Farm'), findsNWidgets(2));
      expect(find.text('9 Concession Rd'), findsOneWidget);
      expect(find.text('Your quote is on the way'), findsOneWidget);
      await unmount(tester);
    });
  });

  group('job detail', () {
    testWidgets('shows the timeline, crew, notes, price breakdown and payment', (tester) async {
      final server = seeded();
      await pumpApp(tester, server);

      await tapText(tester, 'Marcus Reid · 47 min · with shovelling');
      expect(find.byType(JobDetailScreen), findsOneWidget);
      final detail = find.byType(JobDetailScreen);
      Finder within(String text) => find.descendant(of: detail, matching: find.text(text));

      expect(within('Maple Street home'), findsOneWidget);
      expect(within('PLOUGH + SHOVEL'), findsOneWidget);
      expect(within('Done'), findsNWidgets(2));
      expect(within('Marcus Reid'), findsOneWidget);
      expect(within('47 min'), findsOneWidget);
      expect(within('Cleared the steps too.'), findsOneWidget);
      expect(within('\$45'), findsOneWidget);
      expect(within('\$20'), findsOneWidget);
      expect(within('\$65'), findsOneWidget);
      expect(within('Paid. Thank you.'), findsOneWidget);
      expect(server.count('GET /jobs/${server.jobs.first['id']}'), 1);

      await tapText(tester, 'Back');
      expect(find.byType(JobDetailScreen), findsNothing);
      await unmount(tester);
    });

    testWidgets('a failed charge shows the reason', (tester) async {
      final server = seeded(mode: 'stripe')..saveCard();
      server.addJob(
        server.properties.first,
        status: 'done',
        paymentStatus: 'failed',
        paymentError: 'Your card has insufficient funds.',
        ago: const Duration(hours: 2),
      );
      await pumpApp(tester, server);

      await tapText(tester, 'Marcus Reid · 47 min');
      expect(find.text("We couldn't charge your card for this job."), findsOneWidget);
      expect(find.text('Your card has insufficient funds.'), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('a cancelled request whose hold is not released yet says so', (tester) async {
      const reason = 'The card hold could not be released yet. It will be retried automatically.';
      final server = seeded(mode: 'stripe')..saveCard();
      server.addJob(
        server.properties.first,
        status: 'cancelled',
        paymentStatus: 'authorized',
        paymentError: reason,
        ago: const Duration(hours: 2),
      );
      await pumpApp(tester, server);

      // Not "Hold placed", as if the request were still on.
      expect(find.text('Releasing hold'), findsOneWidget);
      expect(find.text('Hold placed'), findsNothing);

      await tapText(tester, 'Cancelled by you');
      expect(find.byType(JobDetailScreen), findsOneWidget);
      expect(find.text('PRICE · NOT CHARGED'), findsOneWidget);
      expect(
        find.text('The hold of \$45 on your card is being released. You will not be charged.'),
        findsOneWidget,
      );
      expect(find.text(reason), findsOneWidget);
      expect(find.textContaining("You're charged only when the job is done"), findsNothing);
      expect(find.text('Hold placed'), findsNothing);
      await unmount(tester);
    });

    testWidgets('follows a job that is under way and stops once it is done', (tester) async {
      final server = seeded(mode: 'stripe')..saveCard();
      final job = server.addJob(server.properties.first, paymentStatus: 'authorized');
      final route = 'GET /jobs/${job['id']}';
      await pumpApp(tester, server);
      await tester.tap(find.byType(RAvatar));
      await settle(tester);
      await tapText(tester, 'Billing');
      // The charge whose hold is still only placed.
      await tapText(tester, 'Hold placed');

      final detail = find.byType(JobDetailScreen);
      Finder within(String text) => find.descendant(of: detail, matching: find.text(text));
      expect(detail, findsOneWidget);
      expect(within('Waiting for crew'), findsOneWidget);
      expect(
        within("A hold of \$45 is on your card. You're charged only when the job is done."),
        findsOneWidget,
      );
      expect(server.count(route), 1);

      // A crew member accepts; the ten-second poll shows it.
      job
        ..['status'] = 'claimed'
        ..['crewName'] = 'Marcus Reid'
        ..['crewInitials'] = 'MR'
        ..['claimedAt'] = DateTime.now().toUtc().toIso8601String();
      await wait(tester, const Duration(seconds: 10));
      expect(server.count(route), 2);
      expect(within('Marcus Reid'), findsOneWidget);

      server.complete(job);
      await wait(tester, const Duration(seconds: 10));
      expect(server.count(route), 3);
      expect(within('Done'), findsNWidgets(2));
      expect(within('Paid'), findsOneWidget);

      // Finished jobs do not change any more, so the polling ends.
      await wait(tester, const Duration(minutes: 1));
      expect(server.count(route), 3);
      await unmount(tester);
    });
  });

  group('property strip', () {
    testWidgets('opens with the selected tab in view, however many come before it', (tester) async {
      final server = FakeApi();
      for (var i = 1; i <= 7; i++) {
        server.addProperty(id: 'prop_$i', name: 'Driveway $i', price: 40 + i);
      }
      // The last one has a job under way, so it is the one to open on.
      server.addJob(server.properties.last);
      await pumpApp(tester, server);

      final frame = tester.getRect(find.byType(HomeScreen));
      Rect tab(String name) => tester.getRect(find.widgetWithText(PropertyTab, name));
      expect(find.text('Waiting for crew'), findsOneWidget);
      expect(tab('Driveway 7').left, greaterThanOrEqualTo(frame.left));
      expect(tab('Driveway 7').right, lessThanOrEqualTo(frame.right));
      expect(tab('Add property').right, lessThanOrEqualTo(frame.right));
      expect(tab('Driveway 1').right, lessThan(frame.left));
      await unmount(tester);
    });

    testWidgets('brings a newly selected tab into view and shows there is more to scroll', (
      tester,
    ) async {
      final properties = [
        for (var i = 1; i <= 7; i++)
          Property.fromJson({'id': 'prop_$i', 'name': 'Driveway $i', 'status': 'active'}),
      ];
      final selected = ValueNotifier('prop_1');
      addTearDown(selected.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 400,
                child: ValueListenableBuilder<String>(
                  valueListenable: selected,
                  builder: (_, id, _) => PropertyTabStrip(
                    properties: properties,
                    selectedId: id,
                    attention: (p) => p.id == 'prop_3',
                    onSelect: (id) => selected.value = id,
                    onAdd: () {},
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final strip = tester.getRect(find.byType(PropertyTabStrip));
      Rect tab(String name) => tester.getRect(find.widgetWithText(PropertyTab, name));
      bool inView(String name) => tab(name).left >= strip.left && tab(name).right <= strip.right;

      expect(inView('Driveway 1'), isTrue);
      expect(inView('Driveway 6'), isFalse);
      // The scrollbar is there because the tabs do not all fit.
      expect(find.byType(Scrollbar), findsOneWidget);
      expect(
        tester.state<ScrollableState>(find.byType(Scrollable)).position.maxScrollExtent,
        greaterThan(0),
      );

      // Selected from outside the strip, as after adding a property.
      selected.value = 'prop_6';
      await tester.pumpAndSettle();
      expect(inView('Driveway 6'), isTrue);
      expect(inView('Driveway 1'), isFalse);

      // A tab that is only partly in view is brought in when it is tapped.
      await tester.tapAt(tab('Driveway 4').centerRight - const Offset(4, 0));
      await tester.pumpAndSettle();
      expect(selected.value, 'prop_4');
      expect(inView('Driveway 4'), isTrue);
    });
  });
}

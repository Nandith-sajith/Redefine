// Smoke tests: the real app widget tree against a mocked HTTP API.
//
// The app polls, so nothing here uses pumpAndSettle(); every test unmounts
// the app at the end to cancel its timers.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:redefine_admin/api.dart';
import 'package:redefine_admin/main.dart';
import 'package:redefine_admin/screens/crew_member.dart';
import 'package:redefine_admin/screens/customer_detail.dart';
import 'package:redefine_admin/screens/customers.dart';
import 'package:redefine_admin/screens/job_detail.dart';
import 'package:redefine_admin/screens/new_job.dart';
import 'package:redefine_admin/screens/quote_detail.dart';
import 'package:redefine_admin/screens/settings.dart';
import 'package:redefine_admin/widgets/job_widgets.dart';
import 'package:redefine_ui/redefine_ui.dart';

import 'fake_api.dart';

/// Lets in-flight requests land and route transitions finish.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Boots the app against a [FakeApi], runs [body], then unmounts.
void adminTest(
  String description,
  Future<void> Function(WidgetTester tester, FakeApi server) body, {
  bool signedIn = true,
  // Wide enough for the phone frame, tall enough to keep most pages in view.
  Size window = const Size(1000, 1800),
}) {
  testWidgets(description, (tester) async {
    tester.view.physicalSize = window;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final server = FakeApi();
    useApi(
      ApiClient(
        baseUrl: 'http://api.test',
        httpClient: server.client,
        tokenStore: MemoryTokenStore(signedIn ? server.issueToken() : null),
      ),
    );
    await tester.pumpWidget(const AdminApp());
    await settle(tester);
    try {
      await body(tester, server);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
      session.dispose();
    }
  });
}

Future<void> tapOn(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
  await settle(tester);
}

Finder navItem(String label) =>
    find.descendant(of: find.byType(RBottomNav), matching: find.text(label));

Finder field(String label) => find.descendant(
  of: find.widgetWithText(RTextField, label.toUpperCase()),
  matching: find.byType(TextField),
);

Finder confirmButton(String label) => find.widgetWithText(FilledButton, label);

Future<void> goBack(WidgetTester tester) => tapOn(tester, find.byType(RBackRow).last);

void main() {
  adminTest('signs in and shows the live dashboard', signedIn: false, (tester, server) async {
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.text('ADMIN'), findsOneWidget);
    expect(server.requests, isEmpty);

    // Debug builds prefill the demo account.
    expect(find.text(FakeApi.adminEmail), findsOneWidget);
    await tester.tap(find.text('Log in'));
    await settle(tester);

    expect(find.byType(LoginScreen), findsNothing);
    expect(find.text('Hi Lia!'), findsOneWidget);
    expect(find.text('0 ploughs done today · \$0 billed'), findsOneWidget);

    // Needs attention: the pending quote, the applicant, the unpaid job.
    expect(find.text('Quote request · Sarah Mitchell'), findsOneWidget);
    expect(find.textContaining('Cabin · 88 Lakeside Rd · requested'), findsOneWidget);
    expect(find.text('Tasha Rivera applied to join the crew'), findsOneWidget);
    expect(find.text('Payment issues · 1'), findsOneWidget);
    expect(find.text('\$55 still to collect'), findsOneWidget);

    // Live now: the open request, with its running status line.
    expect(find.text('LIVE NOW · 1'), findsOneWidget);
    expect(find.text('Cedar Ave home'), findsOneWidget);
    expect(find.textContaining('Waiting for crew · 10 min'), findsOneWidget);
    expect(find.text('OPEN'), findsOneWidget);

    // Badges: Home = 1 quote + 1 payment issue, Jobs = 1 open, Crew = 1 applicant.
    expect(find.descendant(of: find.byType(RBottomNav), matching: find.text('2')), findsOneWidget);
    expect(
      find.descendant(of: find.byType(RBottomNav), matching: find.text('1')),
      findsNWidgets(2),
    );
  });

  adminTest('restores a session; every tab shows the mocked data', (tester, server) async {
    expect(server.requests.first, 'GET /auth/me');
    expect(find.text('Hi Lia!'), findsOneWidget);

    // Jobs · Active
    await tester.tap(navItem('Jobs'));
    await settle(tester);
    expect(find.text('WAITING FOR CREW · 1'), findsOneWidget);
    expect(find.byType(JobRow), findsOneWidget);
    expect(server.requests, contains('GET /jobs?status=open%2Cclaimed%2CinProgress'));

    // Jobs · History, then narrowed on the client
    await tester.tap(find.text('History'));
    await settle(tester);
    expect(find.text('3 jobs requested in the last 7 days'), findsOneWidget);
    expect(find.byType(JobRow), findsNWidgets(3));
    await tester.tap(find.text('Done'));
    await settle(tester);
    expect(find.byType(JobRow), findsNWidgets(2));
    await tester.tap(find.text('Last 30 days'));
    await settle(tester);
    expect(find.text('2 jobs requested in the last 30 days'), findsOneWidget);

    // Customers, with a real search
    await tester.tap(navItem('Customers'));
    await settle(tester);
    expect(find.text('3 customers · 2 with an active property'), findsOneWidget);
    expect(find.text('Sarah Mitchell'), findsOneWidget);
    // The day of the newest request, whatever became of it: Sarah's last job
    // is done, Anna's was requested ten minutes ago and is still open.
    final sarahs = dayInSentence(_ago(const Duration(days: 2, hours: 1)));
    final annas = dayInSentence(_ago(const Duration(minutes: 10)));
    expect(find.text('2 properties · last request $sarahs'), findsOneWidget);
    expect(find.text('1 property · last request $annas'), findsOneWidget);
    expect(find.text('1 property · no requests yet'), findsOneWidget);
    expect(find.textContaining('last plough'), findsNothing);
    // Manual payments: "No card" would be every customer, so it is not offered.
    expect(find.textContaining('No card'), findsNothing);
    await tester.enterText(find.byType(TextField), 'cedar');
    await settle(tester);
    expect(find.text('Anna Tomlinson'), findsOneWidget);
    expect(find.text('Sarah Mitchell'), findsNothing);
    await tester.enterText(find.byType(TextField), 'nobody at all');
    await settle(tester);
    expect(find.text('No matches'), findsOneWidget);
    await tester.tap(find.text('Show everyone'));
    await settle(tester);
    expect(find.text('Paul Larson'), findsOneWidget);

    // Crew
    await tester.tap(navItem('Crew'));
    await settle(tester);
    expect(find.text('2 active · 1 pending · \$55 unpaid'), findsOneWidget);
    expect(find.text('NEW APPLICATION'), findsOneWidget);
    expect(find.text('Tasha Rivera'), findsOneWidget);
    expect(find.text('1 job this week · \$25'), findsOneWidget);
    expect(find.text('\$30 UNPAID'), findsOneWidget);
  });

  adminTest('Jobs: Today and History ask the server for their own dates', (tester, server) async {
    // Only jobs whose day is certain. The seed's open request is ten minutes
    // old, which is yesterday for the first minutes of a day.
    server.jobs.removeWhere((job) => job['id'] == 'job_open');
    server.addJob(
      'job_today',
      'prop_maple',
      status: 'done',
      crewId: 'crew_marcus',
      requested: Duration.zero,
      completed: Duration.zero,
      payment: 'due',
    );
    server.addJob('job_called_off', 'prop_cedar', status: 'cancelled', requested: Duration.zero);
    server.addJob(
      'job_weeks_ago',
      'prop_cedar',
      status: 'done',
      crewId: 'crew_jordan',
      requested: const Duration(days: 20, hours: 1),
      completed: const Duration(days: 20),
      payment: 'paid',
    );
    // The dated job lists asked for so far: Today's has both ends, History's
    // is open ended.
    List<Map<String, String>> dated({required bool closed}) => [
      for (final query in server.queriesOf('GET /jobs'))
        if (query.containsKey('from') && query.containsKey('to') == closed) query,
    ];
    Duration reach(Map<String, String> query) =>
        DateTime.now().difference(DateTime.parse(query['from']!));

    await tester.tap(navItem('Jobs'));
    await settle(tester);

    // Today: from local midnight to the next one, sent as instants.
    await tester.tap(find.text('Today'));
    await settle(tester);
    final now = DateTime.now();
    final today = dated(closed: true).single;
    expect(DateTime.parse(today['from']!).toLocal(), DateTime(now.year, now.month, now.day));
    expect(DateTime.parse(today['to']!).toLocal(), DateTime(now.year, now.month, now.day + 1));
    // The jobs of two, three and twenty days ago are not today's.
    expect(find.text('2 requested · 1 done · 1 cancelled · \$45 billed'), findsOneWidget);
    expect(find.byType(JobRow), findsNWidgets(2));

    // History: everything since seven days ago.
    await tester.tap(find.text('History'));
    await settle(tester);
    expect(dated(closed: false), hasLength(1));
    expect(reach(dated(closed: false).last).inMinutes, 7 * 24 * 60);
    expect(find.text('4 jobs requested in the last 7 days'), findsOneWidget);

    // A longer range is a new question to the server, not a new label.
    await tester.tap(find.text('Last 30 days'));
    await settle(tester);
    expect(dated(closed: false), hasLength(2));
    expect(reach(dated(closed: false).last).inMinutes, 30 * 24 * 60);
    expect(find.text('5 jobs requested in the last 30 days'), findsOneWidget);
    expect(find.byType(JobRow), findsNWidgets(5));
  });

  adminTest('prices a pending quote and sends it', (tester, server) async {
    await tester.tap(find.text('Quote request · Sarah Mitchell'));
    await settle(tester);
    expect(find.byType(QuoteDetailScreen), findsOneWidget);
    expect(find.text('Quote for Sarah Mitchell'), findsOneWidget);
    expect(find.text('NEEDS A PRICE'), findsOneWidget);
    expect(find.text('Long gravel driveway, about 60 m.'), findsOneWidget);
    expect(find.text('sarah.m@gmail.com'), findsOneWidget);
    expect(find.textContaining('adds \$20 for the customer and \$10 for the crew'), findsOneWidget);

    ElevatedButton send() => tester.widget(find.widgetWithText(ElevatedButton, 'Send quote'));
    expect(send().onPressed, isNull);

    await tester.enterText(field('Price per plough'), '70');
    await tester.enterText(field('Crew pay per plough'), '80');
    await tester.pump();
    expect(find.text("Crew pay can't be more than the price."), findsOneWidget);
    expect(send().onPressed, isNull);

    await tester.enterText(field('Crew pay per plough'), '40');
    await tester.pump();
    expect(find.text('Margin: \$30 per plough'), findsOneWidget);
    expect(send().onPressed, isNotNull);

    await tapOn(tester, find.text('Send quote'));
    expect(server.bodies['POST /quotes/quote_cabin/send'], {'price': 70, 'crewPay': 40});
    expect(find.byType(QuoteDetailScreen), findsNothing);
    expect(find.text('Quote sent to Sarah'), findsOneWidget);
    // Back on Home the dashboard was reloaded: the request is gone.
    expect(find.text('Quote request · Sarah Mitchell'), findsNothing);
  });

  adminTest('Enter in the price field moves on to the crew pay; only the last field sends', (
    tester,
    server,
  ) async {
    await tester.tap(find.text('Quote request · Sarah Mitchell'));
    await settle(tester);

    // A crew pay is already in place, so the pair is valid the moment the
    // price is typed and Enter could send it as it stands.
    await tester.enterText(field('Crew pay per plough'), '40');
    await tester.enterText(field('Price per plough'), '70');
    await tester.testTextInput.receiveAction(TextInputAction.next);
    await settle(tester);
    // Nothing went to the customer: the crew pay has not been looked at yet.
    expect(server.count('POST /quotes/quote_cabin/send'), 0);
    expect(find.byType(QuoteDetailScreen), findsOneWidget);
    expect(tester.widget<TextField>(field('Crew pay per plough')).focusNode!.hasFocus, isTrue);

    await tester.enterText(field('Crew pay per plough'), '45');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await settle(tester);
    expect(server.bodies['POST /quotes/quote_cabin/send'], {'price': 70, 'crewPay': 45});
    expect(find.byType(QuoteDetailScreen), findsNothing);
    expect(find.text('Quote sent to Sarah'), findsOneWidget);
  });

  adminTest('opens a live job and cancels it', (tester, server) async {
    await tester.tap(find.text('Cedar Ave home'));
    await settle(tester);
    expect(find.byType(AdminJobDetailScreen), findsOneWidget);
    expect(find.text('Waiting for crew'), findsOneWidget);
    expect(find.text('PLOUGH + SHOVEL'), findsOneWidget);
    expect(find.text('Open to all approved crew. The first to accept takes it.'), findsOneWidget);
    expect(find.text('Anna Tomlinson'), findsOneWidget);
    expect(find.text('Please clear the side door too.'), findsOneWidget);
    // Plough 55 + shovelling 20; crew 30 + 10 bonus.
    expect(find.text('\$75'), findsOneWidget);
    expect(find.text('\$40'), findsOneWidget);
    expect(find.text('\$35'), findsOneWidget);
    expect(find.text('Complete job'), findsNothing);
    expect(find.text('Nothing is billed until the job is done.'), findsOneWidget);

    await tapOn(tester, find.text('Cancel job'));
    expect(find.text('Cancel this job?'), findsOneWidget);
    expect(find.text('The customer is not billed.'), findsOneWidget);
    await tester.tap(confirmButton('Cancel job'));
    await settle(tester);

    expect(server.requests, contains('POST /jobs/job_open/cancel'));
    expect(find.text('Cancelled'), findsWidgets);
    expect(find.text('Job cancelled'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Cancel job'), findsNothing);
    // The payment card follows the job: a cancelled job is not billed later.
    expect(find.text('The job was cancelled. Nothing was billed.'), findsOneWidget);
    expect(find.text('Nothing is billed until the job is done.'), findsNothing);

    await goBack(tester);
    expect(find.text('All clear'), findsOneWidget);
    expect(find.descendant(of: find.byType(RBottomNav), matching: find.text('1')), findsOneWidget);
  });

  adminTest('a card hold that cannot be released yet is explained and watched', (
    tester,
    server,
  ) async {
    server.addOpenJob('job_held', 'prop_maple');
    server.jobs.first['payment'] = {
      'mode': 'stripe',
      'status': 'authorized',
      'error': null,
      'holdExpiresAt': DateTime.now().toUtc().add(const Duration(days: 6)).toIso8601String(),
      'capturedAt': null,
    };
    server.releaseFails = true;
    await tester.pump(const Duration(seconds: 10));
    await settle(tester);

    await tapOn(tester, find.text('Maple Street home'));
    expect(
      find.text("A hold of \$45 is on the customer's card. It is charged when the job is done."),
      findsOneWidget,
    );
    expect(find.textContaining('The hold expires'), findsOneWidget);

    await tapOn(tester, find.text('Cancel job'));
    await tester.tap(confirmButton('Cancel job'));
    await settle(tester);

    // Cancelled, but the hold is still on the card: the page says so and
    // passes on the server's reason, instead of promising a charge.
    expect(find.text('Job cancelled'), findsOneWidget);
    expect(
      find.text(
        "The job was cancelled. The hold of \$45 on the customer's card is being released.",
      ),
      findsOneWidget,
    );
    expect(
      find.text('The card hold could not be released yet. It will be retried automatically.'),
      findsOneWidget,
    );
    expect(find.textContaining('It is charged when the job is done.'), findsNothing);
    expect(find.textContaining('The hold expires'), findsNothing);

    // The job is over but not settled, so the page keeps asking.
    server
      ..releaseFails = false
      ..retryReleases();
    await tester.pump(const Duration(seconds: 10));
    await settle(tester);
    expect(find.text('The hold was released. Nothing was charged.'), findsOneWidget);
    expect(find.textContaining('could not be released'), findsNothing);

    // Settled: nothing left to wait for.
    final loads = server.count('GET /jobs/job_held');
    await tester.pump(const Duration(seconds: 30));
    expect(server.count('GET /jobs/job_held'), loads);
  });

  adminTest('follows a payment issue to the job and marks it paid', (tester, server) async {
    await tester.tap(find.text('Payment issues · 1'));
    await settle(tester);
    // Jobs · History · Needs payment, loaded by payment status, not by date.
    expect(server.requests, contains('GET /jobs?payment=due%2Cfailed'));
    expect(find.text('1 job · \$55 to collect · any date'), findsOneWidget);
    expect(find.text('Due'), findsOneWidget);

    await tester.tap(find.byType(JobRow));
    await settle(tester);
    expect(find.text('\$55 is due from the customer.'), findsOneWidget);
    expect(find.text('Jordan Park'), findsWidgets);
    expect(find.text('Salted the steps.'), findsOneWidget);

    await tapOn(tester, find.text('Mark paid · \$55'));
    expect(find.text('Mark as paid?'), findsOneWidget);
    await tester.tap(confirmButton('Mark paid'));
    await settle(tester);
    expect(server.requests, contains('POST /jobs/job_due/mark-paid'));
    expect(find.text('Marked as paid by the office.'), findsOneWidget);
    expect(find.textContaining('Mark paid ·'), findsNothing);

    await goBack(tester);
    expect(find.text('Nothing to collect'), findsOneWidget);
  });

  adminTest('approves an applicant and records a payout', (tester, server) async {
    await tester.tap(navItem('Crew'));
    await settle(tester);
    await tester.tap(find.text('Approve'));
    await settle(tester);
    expect(
      server.requests.where((r) => r.startsWith('POST /crew/crew_tasha/approve?tz=')),
      isNotEmpty,
    );
    expect(find.text('Tasha Rivera is approved and can accept jobs'), findsOneWidget);
    expect(find.text('NEW APPLICATION'), findsNothing);
    expect(find.text('3 active · 0 pending · \$55 unpaid'), findsOneWidget);
    // The shell's badge for applicants is gone too.
    expect(find.descendant(of: find.byType(RBottomNav), matching: find.text('1')), findsOneWidget);

    await tester.tap(find.text('Jordan Park'));
    await settle(tester);
    expect(find.byType(CrewMemberScreen), findsOneWidget);
    expect(server.requests.where((r) => r.startsWith('GET /crew/crew_jordan/pay?tz=')), isNotEmpty);
    expect(find.text('For 1 finished job'), findsOneWidget);
    expect(find.text('jordan@redefine.co'), findsOneWidget);
    expect(find.text('No payouts yet.'), findsOneWidget);

    await tapOn(tester, find.text('Record payout'));
    expect(
      find.text(
        'Record \$30 paid to Jordan Park for 1 job? This only keeps the books: '
        'pay them yourself first.',
      ),
      findsOneWidget,
    );
    await tester.tap(confirmButton('Record payout'));
    await settle(tester);
    expect(
      server.requests.where((r) => r.startsWith('POST /crew/crew_jordan/payouts?tz=')),
      isNotEmpty,
    );
    expect(find.text('Recorded \$30 paid to Jordan Park'), findsOneWidget);
    expect(find.text('Nothing unpaid.'), findsOneWidget);
    expect(find.text('No payouts yet.'), findsNothing);
    final payout = tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, 'Record payout'),
    );
    expect(payout.onPressed, isNull);
  });

  adminTest('re-prices a property and creates a job for it', (tester, server) async {
    await tester.tap(navItem('Customers'));
    await settle(tester);
    await tester.tap(find.text('Sarah Mitchell'));
    await settle(tester);
    expect(find.byType(CustomerDetailScreen), findsOneWidget);
    expect(find.text('No card on file'), findsOneWidget);
    expect(find.text('(807) 555-0142'), findsOneWidget);

    // Contact rows copy to the clipboard.
    final copied = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (
      call,
    ) async {
      if (call.method == 'Clipboard.setData') {
        copied.add((call.arguments as Map)['text'] as String);
      }
      return null;
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await tester.tap(find.text('(807) 555-0142'));
    await settle(tester);
    expect(copied, ['(807) 555-0142']);
    expect(find.text('Phone copied'), findsOneWidget);
    expect(find.text('Customer pays \$45 · crew earns \$25'), findsOneWidget);
    expect(find.text('Waiting for your price'), findsOneWidget);
    expect(find.text('Open quote'), findsOneWidget);

    await tapOn(tester, find.text('Edit price'));
    expect(find.text('Price for Maple Street home'), findsOneWidget);
    await tester.enterText(field('Price per plough'), '50');
    // Enter here moves on to the crew pay; it does not save half of the pair.
    await tester.testTextInput.receiveAction(TextInputAction.next);
    await settle(tester);
    expect(find.text('Price for Maple Street home'), findsOneWidget);
    expect(server.count('POST /properties/prop_maple/price'), 0);
    await tester.tap(confirmButton('Save'));
    await settle(tester);
    expect(server.bodies['POST /properties/prop_maple/price'], {'price': 50, 'crewPay': 25});
    expect(find.text('Customer pays \$50 · crew earns \$25'), findsOneWidget);

    await tapOn(tester, find.text('New job'));
    expect(find.byType(NewJobScreen), findsOneWidget);
    // Opened from the property: customer and property are already chosen.
    expect(find.text('Customer pays'), findsOneWidget);
    expect(find.text('Plough'), findsOneWidget);
    expect(find.textContaining('Billed manually: card payments are not set up.'), findsOneWidget);
    await tapOn(tester, find.byType(Switch));
    expect(find.text('Plough + shovel'), findsOneWidget);
    expect(find.text('\$70'), findsOneWidget);
    expect(find.text('\$35'), findsOneWidget);

    await tapOn(tester, find.text('Create job'));
    expect(server.bodies['POST /jobs'], {
      'propertyId': 'prop_maple',
      'shovel': true,
      'payment': 'manual',
    });
    // The new job's page opens in place of the form.
    expect(find.byType(NewJobScreen), findsNothing);
    expect(find.byType(AdminJobDetailScreen), findsOneWidget);
    expect(find.text('Job created by the office'), findsOneWidget);
  });

  adminTest('new job: picks a customer; a clash is explained with a way to the job', (
    tester,
    server,
  ) async {
    await tapOn(tester, find.text('New job'));
    expect(find.text('Who is the plough for?'), findsOneWidget);
    expect(find.text('No active property yet'), findsOneWidget);

    // A customer without an active property cannot be chosen.
    await tester.tap(find.text('Paul Larson'));
    await settle(tester);
    expect(find.text('Who is the plough for?'), findsOneWidget);

    // Anna's only active property already has a job: nothing to create.
    await tester.tap(find.text('Anna Tomlinson'));
    await settle(tester);
    expect(find.text('A job is already under way here'), findsOneWidget);
    expect(find.text('Create job'), findsNothing);
    await tapOn(tester, find.text('Change'));
    expect(find.text('Who is the plough for?'), findsOneWidget);

    await tester.tap(find.text('Sarah Mitchell'));
    await settle(tester);
    expect(server.requests, contains('GET /customers/cust_sarah'));
    expect(find.text('Maple Street home'), findsOneWidget);
    expect(find.text('Customer pays \$45 · crew earns \$25'), findsOneWidget);

    server.blockNewJobsWith = 'job_open';
    await tapOn(tester, find.text('Create job'));
    expect(find.text('This property already has a plough on the way.'), findsOneWidget);
    expect(find.byType(NewJobScreen), findsOneWidget);

    await tapOn(tester, find.text('Open job'));
    expect(find.byType(AdminJobDetailScreen), findsOneWidget);
    expect(find.text('Cedar Ave home'), findsOneWidget);
  });

  adminTest('new job: the form stays up until the server has answered', (tester, server) async {
    await tapOn(tester, find.text('New job'));
    await tester.tap(find.text('Sarah Mitchell'));
    await settle(tester);

    // The server takes its time, as it can while it places a card hold.
    final answer = Completer<void>();
    server.holdNewJobs = answer;
    await tapOn(tester, find.text('Create job'));
    expect(server.count('POST /jobs'), 1);

    // Neither the back row nor the system's back leaves the form meanwhile.
    expect(tester.widget<RBackRow>(find.byType(RBackRow).last).onTap, isNull);
    await tester.tap(find.byType(RBackRow).last, warnIfMissed: false);
    await tester.binding.handlePopRoute();
    await settle(tester);
    expect(find.byType(NewJobScreen), findsOneWidget);

    // So the job that was created is handed over: its page opens.
    answer.complete();
    await settle(tester);
    expect(find.byType(NewJobScreen), findsNothing);
    expect(find.byType(AdminJobDetailScreen), findsOneWidget);
    expect(find.text('Job created by the office'), findsOneWidget);
    await goBack(tester);
    expect(find.text('Hi Lia!'), findsOneWidget);
  });

  adminTest('new job: a refusal that arrives after the session ended is dropped', (
    tester,
    server,
  ) async {
    await tapOn(tester, find.text('New job'));
    await tester.tap(find.text('Sarah Mitchell'));
    await settle(tester);

    final answer = Completer<void>();
    server
      ..holdNewJobs = answer
      ..blockNewJobsWith = 'job_open';
    await tapOn(tester, find.text('Create job'));

    // Signing out takes every page down, the form included.
    await session.signOut();
    await settle(tester);
    expect(find.byType(LoginScreen), findsOneWidget);

    // The refusal the form would have explained has no form to land on.
    answer.complete();
    await settle(tester);
    expect(tester.takeException(), isNull);
    expect(find.byType(LoginScreen), findsOneWidget);
  });

  adminTest('new job on a saved card: asks before the hold; a decline offers manual billing', (
    tester,
    server,
  ) async {
    server.settings['paymentsMode'] = 'stripe';
    server.customers['cust_sarah']!['card'] = {
      'brand': 'visa',
      'last4': '4242',
      'expMonth': 8,
      'expYear': 2031,
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
    };
    server.declineCards = true;

    await tapOn(tester, find.text('New job'));
    await tester.tap(find.text('Sarah Mitchell'));
    await settle(tester);
    expect(find.text('Hold on card'), findsOneWidget);
    expect(find.textContaining('A hold is placed on Visa ending 4242 now'), findsOneWidget);

    // Money on the customer's card: nothing is sent until it is confirmed.
    await tapOn(tester, find.text('Create job'));
    expect(find.text('Hold \$45 on the card?'), findsOneWidget);
    expect(server.count('POST /jobs'), 0);
    await tester.tap(confirmButton('Create job'));
    await settle(tester);
    expect(server.bodies['POST /jobs'], containsPair('payment', 'card'));
    expect(
      find.text('The card was declined. You can bill this job manually instead.'),
      findsOneWidget,
    );
    expect(find.byType(NewJobScreen), findsOneWidget);

    // The banner's action switches the form to manual billing.
    await tapOn(tester, find.widgetWithText(TextButton, 'Bill manually'));
    expect(find.textContaining('No card is touched.'), findsOneWidget);
    expect(find.textContaining('The card was declined.'), findsNothing);
    await tapOn(tester, find.text('Create job'));
    expect(server.bodies['POST /jobs'], containsPair('payment', 'manual'));
    expect(find.byType(AdminJobDetailScreen), findsOneWidget);
    expect(find.text('Billed manually'), findsOneWidget);
  });

  adminTest('settings: validates, saves and shows the payments mode', (tester, server) async {
    await tester.tap(find.byType(RAvatar).first);
    await settle(tester);
    expect(find.text('Lia Robinson'), findsOneWidget);
    await tester.tap(find.text('Settings'));
    await settle(tester);
    expect(find.byType(SettingsScreen), findsOneWidget);
    expect(find.text('Manual — no Stripe key configured'), findsOneWidget);

    ElevatedButton save() => tester.widget(find.widgetWithText(ElevatedButton, 'Save settings'));
    expect(save().onPressed, isNull, reason: 'nothing changed yet');

    await tester.enterText(field('Crew shovelling bonus'), '30');
    await tester.pump();
    expect(find.text("The bonus can't be more than the shovelling price."), findsOneWidget);
    expect(save().onPressed, isNull);

    await tester.enterText(field('Crew shovelling bonus'), '15');
    await tester.pump();
    await tapOn(tester, find.text('Save settings'));
    expect(server.bodies['POST /settings'], {
      'shovelPrice': 20,
      'crewShovelBonus': 15,
      'openJobExpiryHours': 48,
    });
    expect(find.text('Settings saved'), findsOneWidget);
    expect(save().onPressed, isNull, reason: 'saved, so clean again');
  });

  adminTest('the dashboard is polled on every tab and drives the badges', (tester, server) async {
    await tester.tap(navItem('Customers'));
    await settle(tester);
    final before = server.requests.where((r) => r.startsWith('GET /dashboard/admin')).length;

    server.addOpenJob('job_second', 'prop_maple');
    await tester.pump(const Duration(seconds: 10));
    await settle(tester);

    final after = server.requests.where((r) => r.startsWith('GET /dashboard/admin')).length;
    expect(after, greaterThan(before));
    // Jobs badge: two open requests now.
    expect(
      find.descendant(of: find.byType(RBottomNav), matching: find.text('2')),
      findsNWidgets(2),
    );
  });

  // A layout overflow anywhere on the way fails the test.
  adminTest('every screen fits a small phone', window: const Size(340, 640), (
    tester,
    server,
  ) async {
    // A job in each live stage, so every kind of row and action is on screen.
    final jordan = server.crew['crew_jordan']!;
    server.addOpenJob('job_claimed', 'prop_maple');
    server.jobs.first.addAll({
      'status': 'claimed',
      'shovel': true,
      'crewId': jordan['id'],
      'crewName': jordan['name'],
      'crewInitials': jordan['initials'],
      'crewColor': jordan['color'],
      'claimedAt': DateTime.now().toUtc().toIso8601String(),
      'payment': {
        'mode': 'stripe',
        'status': 'authorized',
        'error': null,
        'holdExpiresAt': DateTime.now().toUtc().add(const Duration(days: 6)).toIso8601String(),
        'capturedAt': null,
      },
    });
    server.customers['cust_sarah']!['card'] = {
      'brand': 'visa',
      'last4': '4242',
      'expMonth': 8,
      'expYear': 2031,
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
    };
    server.settings['paymentsMode'] = 'stripe';
    server.crew['crew_marcus']!['status'] = 'rejected';
    await tester.pump(const Duration(seconds: 10));
    await settle(tester);

    // Home, then the claimed job with all its actions.
    expect(find.text('LIVE NOW · 2'), findsOneWidget);
    await tapOn(tester, find.text('Maple Street home'));
    expect(find.text('Complete job'), findsOneWidget);
    expect(find.text('Return to open'), findsOneWidget);
    expect(find.textContaining('The hold expires'), findsOneWidget);
    await goBack(tester);

    await tapOn(tester, find.text('Quote request · Sarah Mitchell'));
    expect(find.byType(QuoteDetailScreen), findsOneWidget);
    await goBack(tester);

    await tester.tap(navItem('Jobs'));
    await settle(tester);
    expect(find.text('CREW ASSIGNED · 1'), findsOneWidget);
    for (final view in ['Today', 'History']) {
      await tester.tap(find.text(view));
      await settle(tester);
    }
    await tester.tap(find.text('Needs payment'));
    await settle(tester);

    await tester.tap(navItem('Customers'));
    await settle(tester);
    expect(find.text('NO CARD'), findsNWidgets(2));
    await tapOn(tester, find.text('Sarah Mitchell'));
    expect(find.text('Visa ending 4242 · expires 08/31'), findsOneWidget);
    expect(find.text('Open live job'), findsOneWidget);
    await goBack(tester);

    await tester.tap(navItem('Crew'));
    await settle(tester);
    await tapOn(tester, find.text('Rejected (1)'));
    expect(find.text('Marcus Reid'), findsOneWidget);
    await tapOn(tester, find.text('Jordan Park'));
    expect(find.byType(CrewMemberScreen), findsOneWidget);
    await goBack(tester);

    // The new-job form with the card / manual choice.
    await tester.tap(navItem('Home'));
    await settle(tester);
    await tapOn(tester, find.text('New job'));
    await tapOn(tester, find.text('Sarah Mitchell'));
    expect(find.text('A job is already under way here'), findsOneWidget);
    await goBack(tester);

    await tester.tap(find.byType(RAvatar).first);
    await settle(tester);
    await tester.tap(find.text('Settings'));
    await settle(tester);
    expect(find.text('Stripe'), findsOneWidget);
  });

  adminTest('a server that cannot be reached shows Retry, then recovers', (tester, server) async {
    server.down = true;
    await tester.tap(navItem('Crew'));
    await settle(tester);
    expect(find.textContaining("Couldn't reach the server"), findsOneWidget);

    server.down = false;
    await tester.tap(find.text('Retry'));
    await settle(tester);
    expect(find.text('Marcus Reid'), findsOneWidget);
  });
}

DateTime _ago(Duration duration) => DateTime.now().subtract(duration);

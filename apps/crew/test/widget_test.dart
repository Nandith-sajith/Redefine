// Smoke tests: the real app widget tree against a mocked HTTP API.
//
// The app polls, so nothing here uses pumpAndSettle(); every test unmounts
// the app at the end to cancel its timers.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:redefine_crew/api.dart';
import 'package:redefine_crew/gate.dart';
import 'package:redefine_crew/launch.dart';
import 'package:redefine_crew/logic.dart';
import 'package:redefine_crew/main.dart';
import 'package:redefine_crew/screens/job_detail.dart';
import 'package:redefine_crew/shell.dart';
import 'package:redefine_ui/redefine_ui.dart';

import 'fake_api.dart';

/// Lets in-flight requests land and route transitions finish.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Runs the app for [time] one display frame at a time. Against a server
/// with latency it matters which frames are drawn while a request is on its
/// way, and [settle] skips most of them.
Future<void> frames(WidgetTester tester, Duration time) async {
  const frame = Duration(milliseconds: 16);
  await tester.pump();
  for (var elapsed = Duration.zero; elapsed < time; elapsed += frame) {
    await tester.pump(frame);
  }
}

/// Boots the app against a [FakeApi], runs [body], then unmounts.
void crewTest(
  String description,
  Future<void> Function(WidgetTester tester, FakeApi server) body, {
  bool signedIn = true,
  String crewStatus = 'active',
  Duration latency = Duration.zero,
  void Function(FakeApi server)? arrange,
}) {
  testWidgets(description, (tester) async {
    // Wide enough for the phone frame, tall enough to keep most pages in view.
    tester.view.physicalSize = const Size(1000, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final server = FakeApi()
      ..crewStatus = crewStatus
      ..latency = latency;
    arrange?.call(server);
    useApi(
      ApiClient(
        baseUrl: 'http://api.test',
        httpClient: server.client,
        tokenStore: MemoryTokenStore(signedIn ? server.issueToken() : null),
      ),
    );
    await tester.pumpWidget(const CrewApp());
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

Finder navBadge(String count) => navItem(count);

Finder confirmButton(String label) => find.widgetWithText(FilledButton, label);

/// Whether the screen's button labelled [label] can be pressed: not busy, not
/// disabled. A dialog's button of the same name does not count.
bool canPress(WidgetTester tester, String label) => tester
    .widget<ButtonStyleButton>(
      find.ancestor(
        of: find.text(label),
        matching: find.byWidgetPredicate((w) => w is ElevatedButton || w is OutlinedButton),
      ),
    )
    .enabled;

/// Hands `job_cedar` to the signed-in crew member, as accepted or as started.
void giveCedar(FakeApi server, {bool started = false}) {
  final job = server.jobs['job_cedar']!
    ..status = started ? 'inProgress' : 'claimed'
    ..crewId = FakeApi.crewId
    ..claimedAt = DateTime.now().subtract(const Duration(minutes: 8));
  if (started) job.startedAt = DateTime.now().subtract(const Duration(minutes: 3));
}

/// The requests the app made to job and pay routes, i.e. not the auth ones.
Iterable<String> crewCalls(FakeApi server) => server.requests.where((r) => !r.contains('/auth/'));

void main() {
  crewTest('signs in and shows the crew member\'s real jobs', signedIn: false, (
    tester,
    server,
  ) async {
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.text('CREW'), findsOneWidget);
    expect(server.requests, isEmpty);

    // Debug builds prefill the demo account.
    expect(find.text(FakeApi.crewEmail), findsOneWidget);
    await tester.tap(find.text('Log in'));
    await settle(tester);

    expect(find.byType(LoginScreen), findsNothing);
    expect(find.byType(CrewShell), findsOneWidget);
    expect(find.text('Hi Marcus!'), findsOneWidget);
    expect(find.text(longDate(DateTime.now())), findsOneWidget);
    expect(find.text('Nothing to do · \$0 earned today'), findsOneWidget);

    // Nothing accepted yet, one request waiting: the way to it, and the badge.
    expect(find.text("You're all caught up"), findsOneWidget);
    expect(find.text('See 1 open request'), findsOneWidget);
    expect(navBadge('1'), findsOneWidget);

    // Recent: three finished ploughs and one the customer cancelled.
    expect(find.text('RECENT'), findsOneWidget);
    expect(find.text('Maple Street home'), findsNWidgets(3));
    expect(find.text('Unpaid'), findsNWidgets(2));
    expect(find.text('Paid out'), findsOneWidget);
    expect(find.text('\$35'), findsOneWidget);
    expect(find.text('Birch Road home'), findsOneWidget);
    final cancelledOn = fmtDay(server.jobs['job_birch']!.cancelledAt!);
    expect(find.text('Cancelled by the customer · $cancelledOn'), findsOneWidget);

    expect(crewCalls(server), containsAll(['GET /jobs?scope=mine', 'GET /jobs?scope=open']));
    expect(crewCalls(server).where((r) => r.startsWith('GET /crew/me/pay?tz=')), isNotEmpty);
  });

  crewTest('restores a session; accept, start and complete add the job to the pay', (
    tester,
    server,
  ) async {
    expect(server.requests.first, 'GET /auth/me');
    expect(find.text('Hi Marcus!'), findsOneWidget);

    await tapOn(tester, find.text('See 1 open request'));
    expect(find.text('Open requests'), findsOneWidget);
    expect(find.text('1 request waiting · the first to accept takes it'), findsOneWidget);
    expect(find.text('Cedar Ave home'), findsOneWidget);
    expect(find.text('78 Cedar Ave, Thunder Bay, ON'), findsOneWidget);
    expect(find.text('You earn \$40'), findsOneWidget);
    expect(find.text('PLOUGH + SHOVEL'), findsOneWidget);
    expect(find.text('requested 10 min ago'), findsOneWidget);
    expect(find.text('Please mind the hedge by the gate.'), findsOneWidget);
    // Who the customer is stays hidden until the job is accepted.
    expect(find.text('Anna Tomlinson'), findsNothing);

    // Accept: the job moves to the Jobs tab and its page opens on top.
    await tapOn(tester, find.text('Accept'));
    expect(server.requests, contains('POST /jobs/job_cedar/claim'));
    expect(find.byType(CrewJobDetailScreen), findsOneWidget);
    expect(find.text('Job accepted'), findsOneWidget);
    expect(find.text('Accepted'), findsOneWidget);
    expect(find.text('You earn \$40'), findsOneWidget);
    expect(find.text('Anna Tomlinson'), findsOneWidget);
    expect(find.text('Call customer'), findsOneWidget);
    expect(find.text('Release job'), findsOneWidget);

    // Start: the same page turns into the running job.
    await tapOn(tester, find.text('Start work'));
    expect(server.requests, contains('POST /jobs/job_cedar/start'));
    expect(find.text('In progress · 0 min'), findsOneWidget);
    expect(find.text('Start work'), findsNothing);
    expect(find.text('Release job'), findsNothing);

    // Complete, with a note for the customer, after confirming.
    await tester.enterText(find.byType(TextField), 'Salted the steps too.');
    await tapOn(tester, find.text('Mark complete'));
    expect(find.text('Mark this job complete?'), findsOneWidget);
    expect(find.textContaining('\$40 is added to your pay'), findsOneWidget);
    await tapOn(tester, confirmButton('Mark complete'));

    expect(server.bodies['POST /jobs/job_cedar/complete'], {'crewNote': 'Salted the steps too.'});
    expect(find.byType(CrewJobDetailScreen), findsNothing);
    expect(find.text('Job complete · \$40 added to your pay'), findsOneWidget);

    // Back on the Jobs tab, with today's earnings and the job under Recent.
    expect(find.text('Nothing to do · \$40 earned today'), findsOneWidget);
    expect(find.text('Cedar Ave home'), findsOneWidget);
    expect(navBadge('1'), findsNothing);

    await tapOn(tester, navItem('Pay'));
    expect(find.text('UNPAID BALANCE'), findsOneWidget);
    expect(find.text('\$100'), findsOneWidget);
    expect(find.text('3 jobs waiting for the next payout'), findsOneWidget);
    expect(find.text('UNPAID JOBS · 3'), findsOneWidget);
  });

  crewTest('the Pay tab shows balance, earnings and payouts from the API', (tester, server) async {
    await tapOn(tester, navItem('Pay'));
    final pay = server.pay();

    expect(find.text('UNPAID BALANCE'), findsOneWidget);
    expect(find.text('\$60'), findsOneWidget);
    expect(find.text('2 jobs waiting for the next payout'), findsOneWidget);

    // Today / this week / all time, whatever day of the week the test runs.
    Finder stat(String label) => find.ancestor(of: find.text(label), matching: find.byType(RCard));
    Finder inStat(String label, String text) =>
        find.descendant(of: stat(label), matching: find.text(text));
    expect(inStat('TODAY', '\$0'), findsOneWidget);
    expect(inStat('TODAY', '0 jobs'), findsOneWidget);
    expect(inStat('THIS WEEK', money(pay['earnedThisWeek'] as int)), findsOneWidget);
    expect(inStat('THIS WEEK', countLabel(pay['jobsThisWeek'] as int, 'job')), findsOneWidget);
    expect(inStat('ALL TIME', '\$85'), findsOneWidget);

    expect(find.text('UNPAID JOBS · 2'), findsOneWidget);
    expect(find.text('Maple Street home'), findsNWidgets(2));
    expect(find.text('PAYOUT HISTORY'), findsOneWidget);
    expect(find.text('1 job · E-transfer'), findsOneWidget);

    // An unpaid job opens its read-only page.
    await tapOn(tester, find.text('Maple Street home').first);
    expect(find.byType(CrewJobDetailScreen), findsOneWidget);
    expect(find.text('You earned \$25'), findsOneWidget);
    expect(find.text('Time on site'), findsOneWidget);
    expect(find.text('47 min'), findsOneWidget);
    expect(find.text('\$25 · in your unpaid balance'), findsOneWidget);
    expect(find.text('Cleared right up to the garage door.'), findsOneWidget);
    expect(find.text('Sarah Mitchell'), findsOneWidget);
    for (final action in ['Accept job', 'Start work', 'Release job', 'Mark complete']) {
      expect(find.text(action), findsNothing);
    }
    // The job is over: nothing to call the customer about.
    expect(find.text('Call customer'), findsNothing);

    await tapOn(tester, find.byType(RBackRow));
    expect(find.byType(CrewJobDetailScreen), findsNothing);
    expect(find.text('UNPAID BALANCE'), findsOneWidget);
  });

  crewTest(
    'a crew member with no jobs yet sees designed empty states',
    arrange: (server) {
      server.jobs.removeWhere((_, job) => job.crewId == FakeApi.crewId);
      server.payouts.clear();
    },
    (tester, server) async {
      expect(find.text('No jobs yet'), findsOneWidget);
      expect(find.text('Accept an open request and it shows up here.'), findsOneWidget);
      expect(find.text('RECENT'), findsNothing);

      await tapOn(tester, navItem('Pay'));
      expect(find.text('\$0'), findsNWidgets(4));
      expect(find.text('Your first completed job starts the balance'), findsOneWidget);
      expect(find.text('Nothing unpaid'), findsOneWidget);
      expect(find.text('No payouts yet'), findsOneWidget);

      // With nothing open either, there is no button that leads nowhere.
      server.jobs.clear();
      await tapOn(tester, navItem('Open'));
      expect(find.text('No open requests right now'), findsOneWidget);
      await tapOn(tester, navItem('Jobs'));
      expect(find.text('No jobs yet'), findsOneWidget);
      expect(find.textContaining('open request'), findsNothing);
      expect(
        find.text('When a customer requests a plough it appears in the Open tab.'),
        findsOneWidget,
      );
    },
  );

  crewTest('losing the race for a job says so and drops it from the list', (tester, server) async {
    await tapOn(tester, navItem('Open'));
    expect(find.text('Cedar Ave home'), findsOneWidget);

    server.raced.add('job_cedar');
    await tapOn(tester, find.text('Accept'));

    expect(find.text('Another crew member took that one'), findsOneWidget);
    // Neutral, not an error; and the server's own sentence is not repeated.
    expect(tester.widget<SnackBar>(find.byType(SnackBar)).backgroundColor, RColors.ink);
    expect(find.text('Another crew member already took this job.'), findsNothing);
    expect(find.text('Job accepted'), findsNothing);
    expect(find.byType(CrewJobDetailScreen), findsNothing);
    expect(find.text('Cedar Ave home'), findsNothing);
    expect(find.text('No open requests right now'), findsOneWidget);
    expect(find.text('New requests appear here automatically.'), findsOneWidget);
    expect(navBadge('1'), findsNothing);
  });

  crewTest('a job that changed under the crew member refreshes instead of failing', (
    tester,
    server,
  ) async {
    await tapOn(tester, navItem('Open'));
    await tapOn(tester, find.text('Cedar Ave home'));
    expect(find.byType(CrewJobDetailScreen), findsOneWidget);
    expect(find.text('Accept job'), findsOneWidget);

    // The customer cancels while the page is open.
    server.jobs['job_cedar']!
      ..status = 'cancelled'
      ..cancelledBy = 'customer'
      ..cancelledAt = DateTime.now();
    await tapOn(tester, find.text('Accept job'));

    expect(find.text('This job changed — refreshing'), findsOneWidget);
    expect(find.text('This job was cancelled.'), findsNothing);
    // A cancelled request nobody accepted is no longer visible to crew.
    expect(find.text('This job is no longer available'), findsOneWidget);
    expect(find.text('Another crew member took it, or the request was cancelled.'), findsOneWidget);
    expect(find.text('Accept job'), findsNothing);

    await tapOn(tester, find.widgetWithText(OutlinedButton, 'Back'));
    expect(find.byType(CrewJobDetailScreen), findsNothing);
    expect(find.text('No open requests right now'), findsOneWidget);
  });

  crewTest('accepting from the job page, then releasing, puts the job back', (
    tester,
    server,
  ) async {
    await tapOn(tester, navItem('Open'));
    await tapOn(tester, find.text('Cedar Ave home'));
    expect(find.text('Open'), findsOneWidget);
    expect(find.text('Requested 10 min ago'), findsOneWidget);
    expect(find.text('Call customer'), findsNothing);

    await tapOn(tester, find.text('Accept job'));
    expect(find.text('Accepted'), findsOneWidget);
    expect(find.text('Start work'), findsOneWidget);

    await tapOn(tester, find.text('Release job'));
    expect(find.text('Release this job?'), findsOneWidget);
    await tapOn(tester, find.text('Keep it'));
    expect(server.requests, isNot(contains('POST /jobs/job_cedar/unclaim')));
    expect(find.text('Start work'), findsOneWidget);

    await tapOn(tester, find.text('Release job'));
    await tapOn(tester, confirmButton('Release job'));
    expect(server.requests, contains('POST /jobs/job_cedar/unclaim'));
    expect(find.byType(CrewJobDetailScreen), findsNothing);
    expect(find.text('Job released'), findsOneWidget);

    // Accepting switched to the Jobs tab; the request is open again.
    expect(find.text('See 1 open request'), findsOneWidget);
    expect(navBadge('1'), findsOneWidget);
    expect(server.jobs['job_cedar']!.status, 'open');
  });

  crewTest('an open job page notices when someone else takes the job', (tester, server) async {
    await tapOn(tester, navItem('Open'));
    await tapOn(tester, find.text('Cedar Ave home'));
    expect(find.text('Accept job'), findsOneWidget);

    server.jobs['job_cedar']!
      ..status = 'claimed'
      ..crewId = 'crew_jordan';
    await tester.pump(const Duration(seconds: 10));
    await settle(tester);

    expect(find.text('This job is no longer available'), findsOneWidget);
    expect(find.text('Accept job'), findsNothing);
    // It is gone for good: the page stops asking.
    final asked = server.requests.where((r) => r == 'GET /jobs/job_cedar').length;
    await tester.pump(const Duration(seconds: 30));
    expect(server.requests.where((r) => r == 'GET /jobs/job_cedar').length, asked);
  });

  crewTest('Start on an accepted job moves it to In progress on the Jobs tab', (
    tester,
    server,
  ) async {
    server.jobs['job_cedar']!
      ..status = 'claimed'
      ..crewId = FakeApi.crewId
      ..claimedAt = DateTime.now().subtract(const Duration(minutes: 3));
    await tapOn(tester, navItem('Pay'));
    await tapOn(tester, navItem('Jobs'));

    expect(find.text('1 to do · \$0 earned today'), findsOneWidget);
    expect(find.text('ACCEPTED · 1'), findsOneWidget);
    expect(find.text('Accepted 3 min ago'), findsOneWidget);
    expect(find.text("You're all caught up"), findsNothing);

    await tapOn(tester, find.text('Start'));
    expect(server.requests, contains('POST /jobs/job_cedar/start'));
    expect(find.text('IN PROGRESS'), findsOneWidget);
    expect(find.text('In progress · 0 min'), findsOneWidget);
    expect(find.text('ACCEPTED · 1'), findsNothing);
    expect(find.byType(CrewJobDetailScreen), findsNothing);

    // The card opens the job, ready to be completed.
    await tapOn(tester, find.text('Cedar Ave home'));
    expect(find.byType(CrewJobDetailScreen), findsOneWidget);
    expect(find.text('Mark complete'), findsOneWidget);
  });

  crewTest(
    'a pending crew member waits at the gate and gets in on approval',
    crewStatus: 'pending',
    (tester, server) async {
      expect(find.byType(AwaitingApprovalScreen), findsOneWidget);
      expect(find.text('AWAITING APPROVAL'), findsOneWidget);
      expect(find.text('Your application is with the office'), findsOneWidget);
      expect(find.text('Marcus Reid'), findsOneWidget);
      expect(find.byType(CrewShell), findsNothing);
      expect(find.byType(RBottomNav), findsNothing);
      // No job or pay request is made for someone who is not approved.
      expect(crewCalls(server), isEmpty);

      await tapOn(tester, find.text('Check again'));
      expect(find.text('Not approved yet. This page keeps checking for you.'), findsOneWidget);
      expect(find.byType(AwaitingApprovalScreen), findsOneWidget);

      // The office approves; the next automatic check opens the app.
      server.crewStatus = 'active';
      await tester.pump(const Duration(seconds: 20));
      await settle(tester);

      expect(find.byType(AwaitingApprovalScreen), findsNothing);
      expect(find.byType(CrewShell), findsOneWidget);
      expect(find.text('Hi Marcus!'), findsOneWidget);
      expect(find.text('See 1 open request'), findsOneWidget);
    },
  );

  crewTest('a rejected crew member is told so and can sign out', crewStatus: 'rejected', (
    tester,
    server,
  ) async {
    expect(find.byType(NotApprovedScreen), findsOneWidget);
    expect(find.text('NOT APPROVED'), findsOneWidget);
    expect(find.byType(CrewShell), findsNothing);
    expect(crewCalls(server), isEmpty);

    await tapOn(tester, find.text('Check again'));
    expect(find.text('Nothing has changed: this account is still not approved.'), findsOneWidget);

    await tapOn(tester, find.text('Sign out'));
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(server.tokens, isEmpty);
  });

  crewTest('losing approval in the middle of an action hands over to the gate', (
    tester,
    server,
  ) async {
    await tapOn(tester, navItem('Open'));
    await tapOn(tester, find.text('Cedar Ave home'));
    expect(find.byType(CrewJobDetailScreen), findsOneWidget);

    server.crewStatus = 'rejected';
    await tapOn(tester, find.text('Accept job'));

    expect(find.byType(NotApprovedScreen), findsOneWidget);
    expect(find.byType(CrewJobDetailScreen), findsNothing);
    expect(find.byType(CrewShell), findsNothing);
    expect(find.text('Your crew application was not approved.'), findsOneWidget);
    expect(server.jobs['job_cedar']!.status, 'open');
  });

  crewTest('a refused poll is enough to send an unapproved crew member to the gate', (
    tester,
    server,
  ) async {
    expect(find.byType(CrewShell), findsOneWidget);
    server.crewStatus = 'pending';
    await tester.pump(const Duration(seconds: 15));
    await settle(tester);
    expect(find.byType(AwaitingApprovalScreen), findsOneWidget);
    expect(find.byType(CrewShell), findsNothing);
  });

  crewTest(
    'a failed first load offers Retry and recovers',
    arrange: (server) => server.jobsUnavailable = true,
    (tester, server) async {
      // The header stays, so the account menu is reachable while nothing loads.
      expect(find.text('Hi Marcus!'), findsOneWidget);
      expect(find.text('The server is having trouble. Try again.'), findsOneWidget);
      expect(find.text('RECENT'), findsNothing);

      server.jobsUnavailable = false;
      await tapOn(tester, find.text('Retry'));
      expect(find.text('RECENT'), findsOneWidget);
      expect(find.text('The server is having trouble. Try again.'), findsNothing);
    },
  );

  crewTest('the Open badge keeps counting while another tab is shown', (tester, server) async {
    expect(navBadge('1'), findsOneWidget);
    await tapOn(tester, navItem('Pay'));

    server.jobs['job_pine'] = FakeJob(
      id: 'job_pine',
      propertyName: 'Pine Court home',
      address: '9 Pine Ct, Thunder Bay, ON',
      customerName: 'Paul Larson',
      customerInitials: 'PL',
      crewPay: 30,
      customerTotal: 50,
      requestedAt: DateTime.now(),
    );
    await tester.pump(const Duration(seconds: 10));
    await settle(tester);
    expect(navBadge('2'), findsOneWidget);

    // Oldest request first.
    await tapOn(tester, navItem('Open'));
    expect(find.text('2 requests waiting · the first to accept takes it'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Cedar Ave home')).dy,
      lessThan(tester.getTopLeft(find.text('Pine Court home')).dy),
    );
    expect(find.text('You earn \$30'), findsOneWidget);
    expect(find.text('requested just now'), findsOneWidget);
  });

  crewTest(
    'two requests accepted in a row open one job page, not a stack of them',
    arrange: (server) => server.jobs['job_pine'] = FakeJob(
      id: 'job_pine',
      propertyName: 'Pine Court home',
      address: '9 Pine Ct, Thunder Bay, ON',
      customerName: 'Paul Larson',
      customerInitials: 'PL',
      crewPay: 30,
      customerTotal: 50,
      requestedAt: DateTime.now(),
    ),
    (tester, server) async {
      await tapOn(tester, navItem('Open'));
      await tester.tap(find.text('Accept').first);
      await tester.tap(find.text('Accept').last);
      await settle(tester);

      expect(
        server.jobs.values.where((job) => job.crewId == FakeApi.crewId && job.status == 'claimed'),
        hasLength(2),
      );
      expect(find.byType(CrewJobDetailScreen), findsOneWidget);
      await tapOn(tester, find.byType(RBackRow));
      expect(find.byType(CrewJobDetailScreen), findsNothing);
      expect(find.text('ACCEPTED · 2'), findsOneWidget);
      expect(find.text('2 to do · \$0 earned today'), findsOneWidget);
    },
  );

  crewTest('a job the office takes back shows up as open again on its page', (
    tester,
    server,
  ) async {
    await tapOn(tester, navItem('Open'));
    await tapOn(tester, find.text('Accept'));
    expect(find.text('Start work'), findsOneWidget);

    // The office returns the job to the open list.
    server.jobs['job_cedar']!
      ..status = 'open'
      ..crewId = null
      ..claimedAt = null;
    await tester.pump(const Duration(seconds: 10));
    await settle(tester);

    expect(find.text('The office put this job back on the open list.'), findsOneWidget);
    expect(find.text('Start work'), findsNothing);
    expect(find.text('Accept job'), findsOneWidget);
    expect(find.text('Anna Tomlinson'), findsNothing);
  });

  crewTest(
    'a long history is cut short until asked for',
    arrange: (server) {
      for (var i = 0; i < 5; i++) {
        final finished = DateTime.now().subtract(Duration(days: 20 + i));
        server.jobs['job_old_$i'] = FakeJob(
          id: 'job_old_$i',
          propertyName: 'Elm Street home',
          address: '3 Elm St, Thunder Bay, ON',
          customerName: 'Paul Larson',
          customerInitials: 'PL',
          crewPay: 20,
          customerTotal: 50,
          status: 'done',
          crewId: FakeApi.crewId,
          paidOut: true,
          requestedAt: finished.subtract(const Duration(hours: 2)),
          startedAt: finished.subtract(const Duration(hours: 1)),
          completedAt: finished,
        );
      }
    },
    (tester, server) async {
      // Nine finished jobs: the latest six, and a way to the rest.
      expect(find.text('Maple Street home'), findsNWidgets(3));
      expect(find.text('Elm Street home'), findsNWidgets(2));
      await tapOn(tester, find.text('Show 3 more'));
      expect(find.text('Elm Street home'), findsNWidgets(5));
      expect(find.textContaining('more'), findsNothing);
    },
  );

  crewTest('an expired session returns to the login screen with a notice', (tester, server) async {
    expect(find.byType(CrewShell), findsOneWidget);
    server.tokens.clear();
    await tester.pump(const Duration(seconds: 15));
    await settle(tester);

    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.byType(CrewShell), findsNothing);
    expect(find.text('Your session expired. Please sign in again.'), findsOneWidget);
  });

  crewTest('signing out from the account menu ends the session', (tester, server) async {
    await tapOn(tester, find.byType(RAvatar));
    expect(find.text('Marcus Reid'), findsOneWidget);
    expect(find.text(FakeApi.crewEmail), findsOneWidget);

    await tapOn(tester, find.text('Sign out'));
    await tapOn(tester, confirmButton('Sign out'));

    expect(find.byType(LoginScreen), findsOneWidget);
    expect(server.requests.last, 'POST /auth/logout');
    expect(server.tokens, isEmpty);
  });

  // ---- A server that takes its time, or cannot be reached ------------------

  for (final ms in [60, 200]) {
    crewTest(
      'over a slow connection ($ms ms), releasing a job ends on "Job released"',
      latency: Duration(milliseconds: ms),
      arrange: giveCedar,
      (tester, server) async {
        await tapOn(tester, find.text('Cedar Ave home'));
        await tapOn(tester, find.text('Release job'));
        expect(find.text('Release this job?'), findsOneWidget);

        // Closing the dialog makes the page reload its job, one frame after
        // the release was sent; that answer arrives second, with the page on
        // its way out.
        await tester.tap(confirmButton('Release job'));
        await frames(tester, const Duration(milliseconds: 1000));
        final sent = server.requests.indexOf('POST /jobs/job_cedar/unclaim');
        expect(server.requests.sublist(sent), contains('GET /jobs/job_cedar'));

        expect(find.byType(CrewJobDetailScreen), findsNothing);
        expect(find.text('Job released'), findsOneWidget);
        expect(find.text('The office put this job back on the open list.'), findsNothing);
        expect(find.text('See 1 open request'), findsOneWidget);
      },
    );
  }

  crewTest('a release whose answer got lost is not blamed on the office', arrange: giveCedar, (
    tester,
    server,
  ) async {
    await tapOn(tester, find.text('Cedar Ave home'));
    await tapOn(tester, find.text('Release job'));

    // The server releases the job, but the connection drops before it says so.
    server.jobs['job_cedar']!
      ..status = 'open'
      ..crewId = null
      ..claimedAt = null;
    server.down = true;
    await tapOn(tester, confirmButton('Release job'));
    expect(find.textContaining("Couldn't reach the server"), findsOneWidget);
    expect(find.text('Job released'), findsNothing);

    // Back online, the page finds the job open, as the crew member asked.
    server.down = false;
    await tester.pump(const Duration(seconds: 10));
    await settle(tester);
    expect(find.text('Accept job'), findsOneWidget);
    expect(find.text('The office put this job back on the open list.'), findsNothing);
  });

  crewTest(
    'over a slow connection, completing a job adds it to the pay',
    latency: const Duration(milliseconds: 60),
    arrange: (server) => giveCedar(server, started: true),
    (tester, server) async {
      expect(find.text('1 to do · \$0 earned today'), findsOneWidget);
      await tapOn(tester, find.text('Cedar Ave home'));
      await tapOn(tester, find.text('Mark complete'));

      await tester.tap(confirmButton('Mark complete'));
      await frames(tester, const Duration(milliseconds: 32));
      // On its way: the button is busy and cannot be pressed twice.
      expect(canPress(tester, 'Mark complete'), isFalse);
      await frames(tester, const Duration(milliseconds: 800));

      expect(server.requests.where((r) => r == 'POST /jobs/job_cedar/complete'), hasLength(1));
      expect(find.byType(CrewJobDetailScreen), findsNothing);
      expect(find.text('Job complete · \$40 added to your pay'), findsOneWidget);
      expect(find.text('Nothing to do · \$40 earned today'), findsOneWidget);
      expect(find.text('IN PROGRESS'), findsNothing);
      // One request for the pay summary is enough to show the new total.
      final completed = server.requests.indexOf('POST /jobs/job_cedar/complete');
      expect(
        server.requests.sublist(completed).where((r) => r.startsWith('GET /crew/me/pay')),
        hasLength(1),
      );
    },
  );

  crewTest(
    'signing out while an accept is on its way leaves no error behind',
    latency: const Duration(milliseconds: 300),
    (tester, server) async {
      await tapOn(tester, navItem('Open'));
      await tester.tap(find.text('Accept'));
      await tester.pump();
      expect(server.requests.last, 'POST /jobs/job_cedar/claim');

      // Not awaited yet: the server needs the frames below to answer.
      final signedOut = session.signOut();
      await frames(tester, const Duration(milliseconds: 800));
      await signedOut;

      // The claim went through all the same; nobody is left to show it to.
      expect(server.jobs['job_cedar']!.crewId, FakeApi.crewId);
      expect(tester.takeException(), isNull);
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.byType(CrewJobDetailScreen), findsNothing);
    },
  );

  crewTest(
    'Start on an accepted card shows the job in progress as soon as the server says so',
    latency: const Duration(milliseconds: 200),
    arrange: giveCedar,
    (tester, server) async {
      expect(find.text('ACCEPTED · 1'), findsOneWidget);
      await tester.tap(find.text('Start'));
      await frames(tester, const Duration(milliseconds: 100));
      expect(canPress(tester, 'Start'), isFalse);

      // Answered. The list's own reload is still under way, and it fails.
      await frames(tester, const Duration(milliseconds: 130));
      expect(server.requests.last, 'GET /jobs?scope=mine');
      expect(find.text('IN PROGRESS'), findsOneWidget);
      expect(find.text('ACCEPTED · 1'), findsNothing);
      expect(find.text('Start'), findsNothing);
      server.down = true;
      await frames(tester, const Duration(milliseconds: 400));
      server.down = false;

      expect(find.text('IN PROGRESS'), findsOneWidget);
      expect(find.text('In progress · 0 min'), findsOneWidget);
      expect(find.text('Start'), findsNothing);
      expect(server.requests.where((r) => r == 'POST /jobs/job_cedar/start'), hasLength(1));
    },
  );

  crewTest('accept, start, release and complete each say when the server cannot be reached', (
    tester,
    server,
  ) async {
    const unreachable = "Couldn't reach the server. Check your connection and try again.";

    // Taps [label] (and [confirm] in its dialog) while the server is down: the
    // error is shown, [success] is not, and the button can be pressed again,
    // which it then is with the server back.
    Future<void> failsThenWorks(String label, {String? confirm, required String success}) async {
      final before = server.requests.length;
      server.down = true;
      await tapOn(tester, find.text(label));
      if (confirm != null) await tapOn(tester, confirmButton(confirm));
      expect(
        server.requests.sublist(before).where((r) => r.startsWith('POST ')),
        hasLength(1),
        reason: label,
      );
      expect(find.text(unreachable), findsOneWidget, reason: label);
      expect(tester.widget<SnackBar>(find.byType(SnackBar)).backgroundColor, RColors.danger);
      expect(find.text(success), findsNothing, reason: label);
      expect(canPress(tester, label), isTrue, reason: label);

      server.down = false;
      await tapOn(tester, find.text(label));
      if (confirm != null) await tapOn(tester, confirmButton(confirm));
    }

    // Accept, on the card in the Open tab.
    await tapOn(tester, navItem('Open'));
    await failsThenWorks('Accept', success: 'Job accepted');
    expect(find.text('Job accepted'), findsOneWidget);
    expect(find.byType(CrewJobDetailScreen), findsOneWidget);

    // Release, then accept again from the job's own page.
    await failsThenWorks('Release job', confirm: 'Release job', success: 'Job released');
    expect(find.text('Job released'), findsOneWidget);
    expect(find.byType(CrewJobDetailScreen), findsNothing);
    await tapOn(tester, navItem('Open'));
    await tapOn(tester, find.text('Cedar Ave home'));
    await failsThenWorks('Accept job', success: 'Job accepted');
    expect(find.text('Job accepted'), findsOneWidget);

    await failsThenWorks('Start work', success: 'In progress · 0 min');
    expect(find.text('In progress · 0 min'), findsOneWidget);

    const complete = 'Job complete · \$40 added to your pay';
    await failsThenWorks('Mark complete', confirm: 'Mark complete', success: complete);
    expect(find.text(complete), findsOneWidget);
    expect(server.jobs['job_cedar']!.status, 'done');
  });

  crewTest(
    'Start on an accepted card shows the server\'s refusal and can be tried again',
    arrange: giveCedar,
    (tester, server) async {
      server.jobsUnavailable = true;
      await tapOn(tester, find.text('Start'));
      expect(server.requests, contains('POST /jobs/job_cedar/start'));
      expect(find.text('The server is having trouble. Try again.'), findsOneWidget);
      expect(tester.widget<SnackBar>(find.byType(SnackBar)).backgroundColor, RColors.danger);
      expect(find.text('ACCEPTED · 1'), findsOneWidget);
      expect(find.text('IN PROGRESS'), findsNothing);
      expect(canPress(tester, 'Start'), isTrue);

      server.jobsUnavailable = false;
      await tapOn(tester, find.text('Start'));
      expect(find.text('IN PROGRESS'), findsOneWidget);
      expect(find.text('ACCEPTED · 1'), findsNothing);
    },
  );

  // ---- "Earned today" on the Jobs tab --------------------------------------

  crewTest(
    '"earned today" counts a job the office completes for the crew member',
    arrange: (server) => giveCedar(server, started: true),
    (tester, server) async {
      expect(find.text('1 to do · \$0 earned today'), findsOneWidget);

      server.jobs['job_cedar']!
        ..status = 'done'
        ..completedAt = DateTime.now();
      await tester.pump(const Duration(seconds: 15));
      await settle(tester);

      expect(find.text('IN PROGRESS'), findsNothing);
      expect(find.text('Nothing to do · \$40 earned today'), findsOneWidget);

      // Nothing finished since: the list keeps polling, the pay summary rests.
      final asked = server.requests.where((r) => r.startsWith('GET /crew/me/pay')).length;
      await tester.pump(const Duration(seconds: 15));
      await settle(tester);
      expect(server.requests.where((r) => r.startsWith('GET /crew/me/pay')).length, asked);
    },
  );

  crewTest(
    '"earned today" is asked for again after its first load failed',
    arrange: (server) => server.payUnavailable = true,
    (tester, server) async {
      expect(find.text('RECENT'), findsOneWidget);
      expect(find.text('Nothing to do'), findsOneWidget);
      expect(find.textContaining('earned today'), findsNothing);

      server.payUnavailable = false;
      await tester.pump(const Duration(seconds: 15));
      await settle(tester);
      expect(find.text('Nothing to do · \$0 earned today'), findsOneWidget);
    },
  );

  crewTest('directions open Google Maps; a call falls back to copying the number', (
    tester,
    server,
  ) async {
    final opened = <Uri>[];
    final original = openExternal;
    addTearDown(() => openExternal = original);
    // The desktop app: web links open, and it knows nothing can place a call.
    openExternal = (uri) async {
      opened.add(uri);
      return uri.isScheme('https');
    };
    final copied = <String>[];
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied.add((call.arguments as Map)['text'] as String);
      }
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(SystemChannels.platform, null));

    await tapOn(tester, navItem('Open'));
    await tapOn(tester, find.text('Accept'));
    expect(find.byType(CrewJobDetailScreen), findsOneWidget);

    await tapOn(tester, find.text('Get directions'));
    expect(opened.single, directionsUri('78 Cedar Ave, Thunder Bay, ON'));

    await tapOn(tester, find.text('Call customer'));
    expect(opened.last, Uri.parse('tel:8075550177'));
    expect(copied, ['(807) 555-0177']);
    expect(find.text('No phone app here. (807) 555-0177 copied to the clipboard.'), findsOneWidget);
  });

  crewTest(
    'in a browser a call always copies the number too, as nothing says whether a dialler opened',
    arrange: giveCedar,
    (tester, server) async {
      final opened = <Uri>[];
      final original = openExternal;
      final originalUnconfirmed = callsUnconfirmed;
      addTearDown(() {
        openExternal = original;
        callsUnconfirmed = originalUnconfirmed;
      });
      // What the web build gets: every link "opens", with or without a dialler.
      callsUnconfirmed = true;
      openExternal = (uri) async {
        opened.add(uri);
        return true;
      };
      final copied = <String>[];
      var clipboardWorks = true;
      final messenger = tester.binding.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          if (!clipboardWorks) throw PlatformException(code: 'copy_fail');
          copied.add((call.arguments as Map)['text'] as String);
        }
        return null;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(SystemChannels.platform, null));

      await tapOn(tester, find.text('Cedar Ave home'));
      await tapOn(tester, find.text('Call customer'));
      expect(opened.single, Uri.parse('tel:8075550177'));
      expect(copied, ['(807) 555-0177']);
      expect(
        find.text('(807) 555-0177 copied to the clipboard, in case no phone app opens.'),
        findsOneWidget,
      );
      expect(tester.widget<SnackBar>(find.byType(SnackBar)).backgroundColor, RColors.ink);

      // Even when the clipboard refuses, the tap does not come to nothing.
      clipboardWorks = false;
      await tapOn(tester, find.text('Call customer'));
      expect(opened, hasLength(2));
      expect(find.text('If no phone app opens, dial (807) 555-0177.'), findsOneWidget);
    },
  );

  crewTest('never shows what the customer pays, even if the server sent it', (
    tester,
    server,
  ) async {
    server.leakPrices = true;
    Finder customerMoney() => find.byWidgetPredicate((widget) {
      if (widget is! Text) return false;
      final text = widget.data ?? widget.textSpan?.toPlainText() ?? '';
      return RegExp(r'\$(45|65|70|75)\b').hasMatch(text) ||
          RegExp('payment|charged|billed|hold', caseSensitive: false).hasMatch(text);
    });

    await tapOn(tester, navItem('Jobs'));
    await tester.pump(const Duration(seconds: 15));
    await settle(tester);
    expect(find.text('RECENT'), findsOneWidget);
    expect(customerMoney(), findsNothing);

    await tapOn(tester, navItem('Pay'));
    expect(customerMoney(), findsNothing);
    await tapOn(tester, find.text('Maple Street home').first);
    expect(find.byType(CrewJobDetailScreen), findsOneWidget);
    expect(customerMoney(), findsNothing);
    await tapOn(tester, find.byType(RBackRow));

    await tapOn(tester, navItem('Open'));
    expect(find.text('You earn \$40'), findsOneWidget);
    expect(customerMoney(), findsNothing);
    await tapOn(tester, find.text('Cedar Ave home'));
    expect(find.byType(CrewJobDetailScreen), findsOneWidget);
    expect(customerMoney(), findsNothing);
  });
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:redefine_ui/redefine_ui.dart';

Widget _host(Widget child) => MaterialApp(
  home: Scaffold(
    body: Padding(padding: const EdgeInsets.all(16), child: child),
  ),
);

class _Actions extends StatefulWidget {
  const _Actions();

  @override
  State<_Actions> createState() => _ActionsState();
}

class _ActionsState extends State<_Actions> with BusyState<_Actions> {
  @override
  Widget build(BuildContext context) => Text(busy ? 'busy' : 'idle');
}

void main() {
  group('status pills', () {
    testWidgets('RServiceTag names the service', (tester) async {
      await tester.pumpWidget(
        _host(const Column(children: [RServiceTag(shovel: false), RServiceTag(shovel: true)])),
      );
      expect(find.text('PLOUGH'), findsOneWidget);
      expect(find.text('PLOUGH + SHOVEL'), findsOneWidget);
    });

    testWidgets('RJobStatusPill labels every status', (tester) async {
      await tester.pumpWidget(
        _host(Column(children: [for (final s in JobStatus.values) RJobStatusPill(s)])),
      );
      for (final label in [
        'Waiting for crew',
        'Crew assigned',
        'In progress',
        'Done',
        'Cancelled',
        'Unknown',
      ]) {
        expect(find.text(label), findsOneWidget);
      }
    });

    testWidgets('RPaymentPill labels each status and shows nothing for none or unknown', (
      tester,
    ) async {
      PaymentInfo info(String status) => PaymentInfo.fromJson({'mode': 'stripe', 'status': status});
      await tester.pumpWidget(
        _host(
          Column(
            children: [
              RPaymentPill(info('authorized')),
              RPaymentPill(info('captured')),
              RPaymentPill(info('released')),
              RPaymentPill(info('failed')),
              const RPaymentPill.status(PaymentStatus.due),
              const RPaymentPill.status(PaymentStatus.paid),
            ],
          ),
        ),
      );
      expect(find.text('Hold placed'), findsOneWidget);
      expect(find.text('Paid'), findsNWidgets(2));
      expect(find.text('Hold released'), findsOneWidget);
      expect(find.text('Payment failed'), findsOneWidget);
      expect(find.text('Due'), findsOneWidget);

      await tester.pumpWidget(
        _host(
          Column(
            children: [
              RPaymentPill(info('none')),
              // The crew view of a job carries no payment at all.
              RPaymentPill(PaymentInfo.fromJson(const {})),
            ],
          ),
        ),
      );
      expect(find.byType(RPill), findsNothing);
      expect(tester.getSize(find.byType(RPaymentPill).first), Size.zero);
    });
  });

  group('buttons', () {
    testWidgets('RPrimaryButton: busy shows a spinner and ignores presses', (tester) async {
      var presses = 0;
      await tester.pumpWidget(_host(RPrimaryButton('Request plough', onPressed: () => presses++)));
      await tester.tap(find.text('Request plough'));
      expect(presses, 1);
      expect(find.byType(CircularProgressIndicator), findsNothing);

      await tester.pumpWidget(
        _host(RPrimaryButton('Request plough', busy: true, onPressed: () => presses++)),
      );
      await tester.tap(find.text('Request plough'));
      expect(presses, 1);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('ROutlineButton: busy shows a spinner and ignores presses', (tester) async {
      var presses = 0;
      await tester.pumpWidget(_host(ROutlineButton('Cancel request', onPressed: () => presses++)));
      await tester.tap(find.text('Cancel request'));
      expect(presses, 1);

      await tester.pumpWidget(
        _host(ROutlineButton('Cancel request', busy: true, onPressed: () => presses++)),
      );
      await tester.tap(find.text('Cancel request'));
      expect(presses, 1);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('a long label is cut short instead of overflowing', (tester) async {
      await tester.pumpWidget(
        _host(
          SizedBox(
            width: 160,
            child: RPrimaryButton(
              'Request a plough with shovelling for the whole driveway',
              icon: Icons.ac_unit_rounded,
              onPressed: () {},
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('RCard', () {
    testWidgets('a tappable card reacts and draws its ink on its own Material', (tester) async {
      var taps = 0;
      await tester.pumpWidget(_host(RCard(onTap: () => taps++, child: const Text('Maple Street'))));
      await tester.tap(find.text('Maple Street'));
      await tester.pump(const Duration(seconds: 1));
      expect(taps, 1);

      // Nothing opaque may sit between the InkWell and the Material it paints on.
      final ink = find.descendant(of: find.byType(RCard), matching: find.byType(InkWell));
      final material = tester.widget<Material>(
        find.ancestor(of: ink, matching: find.byType(Material)).first,
      );
      expect(material.color, RColors.white);
      final box = tester.widget<Container>(
        find.descendant(of: ink, matching: find.byType(Container)),
      );
      expect((box.decoration! as BoxDecoration).color, isNull);
    });

    testWidgets('a plain card has no ink', (tester) async {
      await tester.pumpWidget(_host(const RCard(child: Text('Quote'))));
      expect(find.descendant(of: find.byType(RCard), matching: find.byType(InkWell)), findsNothing);
    });
  });

  group('RBottomNav', () {
    const items = [
      RNavItem('Home', Icons.home_outlined),
      RNavItem('Jobs', Icons.ac_unit_rounded, badge: 3),
      RNavItem('Pay', Icons.payments_outlined, badge: 0),
    ];

    testWidgets('reports taps and hides empty badges', (tester) async {
      final tapped = <int>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            bottomNavigationBar: RBottomNav(items: items, currentIndex: 0, onTap: tapped.add),
          ),
        ),
      );
      expect(find.text('3'), findsOneWidget);
      expect(find.text('0'), findsNothing);

      await tester.tap(find.text('Jobs'));
      await tester.tap(find.text('Pay'));
      expect(tapped, [1, 2]);
    });

    testWidgets('the fill is on the Material so item ink is visible', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(bottomNavigationBar: RBottomNav(items: items, currentIndex: 1)),
        ),
      );
      final ink = find.descendant(of: find.byType(RBottomNav), matching: find.byType(InkWell));
      expect(ink, findsNWidgets(3));
      final material = tester.widget<Material>(
        find.ancestor(of: ink.first, matching: find.byType(Material)).first,
      );
      expect(material.color, RColors.surface);
    });
  });

  group('RTextField', () {
    testWidgets('Enter submits, the label is an eyebrow and errors show underneath', (
      tester,
    ) async {
      final submitted = <String>[];
      final changed = <String>[];
      await tester.pumpWidget(
        _host(
          RTextField(
            label: 'Price per plough',
            hint: '45',
            prefixText: r'$',
            errorText: 'Enter a price.',
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onChanged: changed.add,
            onSubmitted: submitted.add,
          ),
        ),
      );
      expect(find.text('PRICE PER PLOUGH'), findsOneWidget);
      expect(find.text(r'$'), findsOneWidget);
      expect(find.text('Enter a price.'), findsOneWidget);

      await tester.enterText(find.byType(TextField), '4a5');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      expect(changed, ['45']);
      expect(submitted, ['45']);
    });

    testWidgets('clicking anywhere in the box focuses the field', (tester) async {
      final focus = FocusNode();
      addTearDown(focus.dispose);
      await tester.pumpWidget(
        _host(RTextField(label: 'Address', icon: Icons.place_outlined, focusNode: focus)),
      );
      expect(focus.hasFocus, isFalse);
      await tester.tap(find.byIcon(Icons.place_outlined));
      await tester.pump();
      expect(focus.hasFocus, isTrue);
    });

    testWidgets('obscure hides the text behind a toggle that Tab skips', (tester) async {
      await tester.pumpWidget(
        _host(
          Column(
            children: [
              const RTextField(label: 'Password', obscure: true),
              RPrimaryButton('Log in', onPressed: () {}),
            ],
          ),
        ),
      );
      TextField field() => tester.widget<TextField>(find.byType(TextField));
      expect(field().obscureText, isTrue);

      await tester.tap(find.byIcon(Icons.visibility_outlined));
      await tester.pump();
      expect(field().obscureText, isFalse);
      await tester.tap(find.byIcon(Icons.visibility_off_outlined));
      await tester.pump();
      expect(field().obscureText, isTrue);

      await tester.tap(find.byType(TextField));
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      final focused = FocusManager.instance.primaryFocus!.context!;
      expect(
        find.ancestor(
          of: find.byElementPredicate((e) => e == focused),
          matching: find.byType(ElevatedButton),
        ),
        findsOneWidget,
      );
    });

    testWidgets('disabled fields take no input or focus', (tester) async {
      final focus = FocusNode();
      addTearDown(focus.dispose);
      await tester.pumpWidget(_host(RTextField(label: 'Email', focusNode: focus, enabled: false)));
      await tester.tap(find.byType(RTextField));
      await tester.pump();
      expect(focus.hasFocus, isFalse);
      expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
    });

    testWidgets('a multi-line field enforces maxLength and shows a counter', (tester) async {
      await tester.pumpWidget(
        _host(const RTextField(label: 'Note for the crew', maxLines: 3, maxLength: 10)),
      );
      await tester.enterText(find.byType(TextField), 'Gate code is 4321');
      await tester.pump();
      expect(find.text('Gate code '), findsOneWidget);
      expect(find.text('10/10'), findsOneWidget);
    });

    testWidgets('a single-line field enforces maxLength without a counter', (tester) async {
      await tester.pumpWidget(_host(const RTextField(label: 'Name', maxLength: 5)));
      await tester.enterText(find.byType(TextField), 'Maple Street');
      await tester.pump();
      expect(find.text('Maple'), findsOneWidget);
      expect(find.text('5/5'), findsNothing);
    });
  });

  testWidgets('RStepTracker lists its steps in order', (tester) async {
    await tester.pumpWidget(
      _host(
        const RStepTracker(
          steps: [
            RStep('Requested', subtitle: '9:42 am', state: RStepState.done),
            RStep('Crew assigned', subtitle: 'Marcus Reid', state: RStepState.current),
            RStep('In progress', state: RStepState.upcoming),
            RStep('Done', state: RStepState.upcoming),
          ],
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Marcus Reid'), findsOneWidget);
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    final tops = [
      for (final title in ['Requested', 'Crew assigned', 'In progress', 'Done'])
        tester.getTopLeft(find.text(title)).dy,
    ];
    expect(tops, orderedEquals([...tops]..sort()));
    expect(tops.toSet(), hasLength(4));
  });

  group('RElapsed', () {
    testWidgets('ticks every second', (tester) async {
      final builds = <Duration>[];
      await tester.pumpWidget(
        _host(
          RElapsed(
            since: DateTime.now().subtract(const Duration(minutes: 18)),
            builder: (_, elapsed) {
              builds.add(elapsed);
              return Text(fmtElapsed(elapsed));
            },
          ),
        ),
      );
      expect(find.text('18 min'), findsOneWidget);
      final before = builds.length;
      await tester.pump(const Duration(seconds: 3));
      expect(builds.length, greaterThan(before));
    });

    testWidgets('never goes negative when the server clock is ahead', (tester) async {
      await tester.pumpWidget(
        _host(
          RElapsed(
            since: DateTime.now().add(const Duration(minutes: 5)),
            builder: (_, elapsed) => Text('${elapsed.inSeconds}'),
          ),
        ),
      );
      expect(find.text('0'), findsOneWidget);
    });
  });

  group('BusyState.run', () {
    Future<_ActionsState> pump(WidgetTester tester) async {
      await tester.pumpWidget(_host(const _Actions()));
      return tester.state<_ActionsState>(find.byType(_Actions));
    }

    testWidgets('tracks busy, returns the result and announces success', (tester) async {
      final state = await pump(tester);
      final gate = Completer<int>();
      final result = state.run(() => gate.future, success: 'Plough requested.');
      await tester.pump();
      expect(state.busy, isTrue);
      expect(find.text('busy'), findsOneWidget);

      gate.complete(7);
      expect(await result, 7);
      await tester.pump();
      expect(state.busy, isFalse);
      expect(find.text('idle'), findsOneWidget);
      expect(find.text('Plough requested.'), findsOneWidget);
    });

    testWidgets('ignores a second action while one is running', (tester) async {
      final state = await pump(tester);
      final gate = Completer<int>();
      var ran = 0;
      final first = state.run(() {
        ran++;
        return gate.future;
      });
      final second = state.run(() async => ran++);
      expect(await second, isNull);
      expect(ran, 1);
      gate.complete(1);
      expect(await first, 1);
    });

    testWidgets('shows the API error and returns null', (tester) async {
      final state = await pump(tester);
      final result = await state.run<int>(
        () async => throw const ApiException(409, 'job_active', 'A plough is already on its way.'),
        success: 'Plough requested.',
      );
      await tester.pump();
      expect(result, isNull);
      expect(state.busy, isFalse);
      expect(find.text('A plough is already on its way.'), findsOneWidget);
      expect(find.text('Plough requested.'), findsNothing);
    });

    testWidgets('onError returning true keeps the error off the SnackBar', (tester) async {
      final state = await pump(tester);
      final seen = <String>[];
      Future<int> declined() async =>
          throw const ApiException(402, 'card_declined', 'Your card was declined.');

      expect(
        await state.run<int>(
          declined,
          onError: (e) {
            seen.add(e.code);
            return true;
          },
        ),
        isNull,
      );
      await tester.pump();
      expect(seen, ['card_declined']);
      expect(find.text('Your card was declined.'), findsNothing);

      expect(await state.run<int>(declined, onError: (e) => false), isNull);
      await tester.pump();
      expect(find.text('Your card was declined.'), findsOneWidget);
    });

    testWidgets('a bug in the action is logged, shown generically and leaves the screen usable', (
      tester,
    ) async {
      final state = await pump(tester);
      final result = await state.run<int>(() async => throw StateError('boom'));
      await tester.pump();
      expect(result, isNull);
      expect(state.busy, isFalse);
      expect(tester.takeException(), isStateError);
      expect(find.text('Something went wrong. Please try again.'), findsOneWidget);
    });
  });

  group('confirmDialog', () {
    Future<void> closed(WidgetTester tester) async {
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
    }

    Future<Future<bool>> open(WidgetTester tester, {bool destructive = false}) async {
      await tester.pumpWidget(_host(const Text('screen')));
      final result = confirmDialog(
        tester.element(find.text('screen')),
        title: 'Cancel this plough?',
        message: 'The hold on your card will be released.',
        confirmLabel: 'Cancel plough',
        cancelLabel: 'Keep it',
        destructive: destructive,
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Cancel this plough?'), findsOneWidget);
      return result;
    }

    testWidgets('resolves true when confirmed', (tester) async {
      final result = await open(tester);
      await tester.tap(find.text('Cancel plough'));
      await closed(tester);
      expect(await result, isTrue);
      expect(find.text('Cancel this plough?'), findsNothing);
    });

    testWidgets('resolves false when cancelled or dismissed', (tester) async {
      var result = await open(tester);
      await tester.tap(find.text('Keep it'));
      await closed(tester);
      expect(await result, isFalse);

      result = await open(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await closed(tester);
      expect(await result, isFalse);
    });

    testWidgets('Enter confirms, but never a destructive action', (tester) async {
      var result = await open(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await closed(tester);
      expect(await result, isTrue);

      result = await open(tester, destructive: true);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await closed(tester);
      expect(await result, isFalse);
    });
  });

  group('RAppHeader', () {
    testWidgets('without a session it shows what it is given and the screen actions', (
      tester,
    ) async {
      var opened = 0;
      await tester.pumpWidget(
        _host(
          RAppHeader(
            greeting: 'Schedule',
            initials: 'LR',
            actions: [RMenuAction('Settings', Icons.settings_outlined, () => opened++)],
          ),
        ),
      );
      expect(find.text('Schedule'), findsOneWidget);
      expect(find.text('LR'), findsOneWidget);

      await tester.tap(find.byType(RAvatar));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Sign out'), findsNothing);

      await tester.tap(find.text('Settings'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(opened, 1);
    });

    testWidgets('with nothing to offer the avatar is not a button', (tester) async {
      await tester.pumpWidget(_host(const RAppHeader(greeting: 'Hi!', initials: 'SM')));
      expect(find.byType(PopupMenuButton<int>), findsNothing);
    });
  });

  testWidgets('RSegmented reports the tapped option', (tester) async {
    final picked = <int>[];
    await tester.pumpWidget(
      _host(
        Align(
          alignment: Alignment.topLeft,
          child: RSegmented(options: const ['Open', 'Mine'], index: 0, onChanged: picked.add),
        ),
      ),
    );
    await tester.tap(find.text('Mine'));
    expect(picked, [1]);
  });

  testWidgets('REmptyState and RErrorView show their actions', (tester) async {
    var retried = 0, secondary = 0;
    await tester.pumpWidget(
      _host(
        Column(
          children: [
            REmptyState(
              icon: Icons.ac_unit_rounded,
              title: 'No ploughs yet',
              message: 'Request one when the snow falls.',
              action: ROutlineButton('Request plough', onPressed: () {}),
            ),
            Expanded(
              child: RErrorView(
                message: 'The server is temporarily unavailable.',
                onRetry: () => retried++,
                secondaryLabel: 'Sign out',
                onSecondary: () => secondary++,
              ),
            ),
          ],
        ),
      ),
    );
    expect(find.text('No ploughs yet'), findsOneWidget);
    expect(find.text('Request one when the snow falls.'), findsOneWidget);
    expect(find.text('Request plough'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await tester.tap(find.text('Sign out'));
    expect((retried, secondary), (1, 1));
  });

  testWidgets('RBanner shows its message and optional action', (tester) async {
    var acted = 0;
    await tester.pumpWidget(
      _host(
        RBanner(
          'Add a card before requesting a plough.',
          actionLabel: 'Add card',
          onAction: () => acted++,
        ),
      ),
    );
    expect(find.text('Add a card before requesting a plough.'), findsOneWidget);
    await tester.tap(find.text('Add card'));
    expect(acted, 1);
  });

  testWidgets('RAvatar falls back to a glyph when there are no initials', (tester) async {
    await tester.pumpWidget(_host(const Row(children: [RAvatar('MR'), RAvatar('')])));
    expect(find.text('MR'), findsOneWidget);
    expect(find.byIcon(Icons.person_rounded), findsOneWidget);
  });

  testWidgets('RPhoneFrame leaves narrow windows alone', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      const MaterialApp(
        home: RPhoneFrame(child: Scaffold(body: Text('app'))),
      ),
    );
    expect(tester.getSize(find.byType(Scaffold)), const Size(400, 800));
  });

  testWidgets('showRSnack replaces the message on screen', (tester) async {
    await tester.pumpWidget(_host(const Text('screen')));
    final context = tester.element(find.text('screen'));
    showRSnack(context, 'Quote sent.');
    await tester.pump(const Duration(milliseconds: 800));
    expect(find.text('Quote sent.'), findsOneWidget);

    showRSnack(context, 'That quote is no longer open.', error: true);
    await tester.pump(const Duration(milliseconds: 800));
    await tester.pump(const Duration(milliseconds: 800));
    expect(find.text('That quote is no longer open.'), findsOneWidget);
    expect(find.text('Quote sent.'), findsNothing);
    expect(tester.widget<SnackBar>(find.byType(SnackBar)).backgroundColor, RColors.danger);
  });
}

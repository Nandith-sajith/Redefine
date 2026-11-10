import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:redefine_ui/redefine_ui.dart';

/// A load function whose calls stay in flight until the test settles them.
class Loader {
  final _pending = <Completer<String>>[];
  int calls = 0;

  Future<String> call() {
    calls++;
    final completer = Completer<String>();
    _pending.add(completer);
    return completer.future;
  }

  int get inFlight => _pending.length;

  void finish(String value) => _pending.removeAt(0).complete(value);

  void fail([String message = 'No connection.']) =>
      _pending.removeAt(0).completeError(ApiException(0, 'network', message));
}

const _every = Duration(seconds: 10);

Widget _live(
  RLiveController<String> controller, {
  Duration? pollEvery = _every,
  bool active = true,
  bool showRefreshStrip = true,
}) => RLive<String>(
  controller: controller,
  pollEvery: pollEvery,
  active: active,
  showRefreshStrip: showRefreshStrip,
  padding: const EdgeInsets.all(16),
  builder: (_, data) => Column(children: [Text(data)]),
);

Widget _host(Widget body) => MaterialApp(home: Scaffold(body: body));

/// Lets settled loads reach the controller, then builds the frame they asked for.
Future<void> _land(WidgetTester tester) async {
  await tester.idle();
  await tester.pump();
}

void main() {
  late Loader loader;
  late RLiveController<String> controller;

  setUp(() {
    loader = Loader();
    controller = RLiveController<String>(loader.call);
    addTearDown(controller.dispose);
  });

  group('RLive', () {
    testWidgets('first load: spinner, error with Retry, spinner again, then data', (tester) async {
      await tester.pumpWidget(_host(_live(controller, pollEvery: null)));
      expect(loader.calls, 1);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      loader.fail('No connection.');
      await _land(tester);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byType(RErrorView), findsOneWidget);
      expect(find.text('No connection.'), findsOneWidget);

      await tester.tap(find.text('Retry'));
      await tester.pump();
      expect(loader.calls, 2);
      expect(find.byType(RErrorView), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      loader.finish('fresh snow');
      await _land(tester);
      expect(find.text('fresh snow'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byType(RefreshIndicator), findsOneWidget);
    });

    testWidgets('polls on the interval and never overlaps a load in flight', (tester) async {
      await tester.pumpWidget(_host(_live(controller)));
      loader.finish('one');
      await _land(tester);
      expect(find.text('one'), findsOneWidget);

      await tester.pump(_every);
      expect(loader.calls, 2);

      // The poll is still in flight: later ticks must wait for it.
      await tester.pump(_every * 3);
      expect(loader.calls, 2);
      expect(loader.inFlight, 1);

      loader.finish('two');
      await _land(tester);
      expect(find.text('two'), findsOneWidget);

      await tester.pump(_every);
      expect(loader.calls, 3);
    });

    testWidgets('without pollEvery it loads once and never again', (tester) async {
      await tester.pumpWidget(_host(_live(controller, pollEvery: null)));
      loader.finish('one');
      await tester.pump(const Duration(minutes: 10));
      expect(loader.calls, 1);
      expect(find.text('one'), findsOneWidget);
    });

    testWidgets('active: false neither loads nor polls; becoming active refreshes at once', (
      tester,
    ) async {
      final active = ValueNotifier(false);
      addTearDown(active.dispose);
      await tester.pumpWidget(
        _host(
          ValueListenableBuilder<bool>(
            valueListenable: active,
            builder: (_, value, _) => _live(controller, active: value),
          ),
        ),
      );
      await tester.pump(const Duration(minutes: 1));
      expect(loader.calls, 0);

      active.value = true;
      await tester.pump();
      expect(loader.calls, 1);
      loader.finish('one');
      await _land(tester);
      expect(find.text('one'), findsOneWidget);

      active.value = false;
      await tester.pump();
      await tester.pump(const Duration(minutes: 1));
      expect(loader.calls, 1);

      active.value = true;
      await tester.pump();
      expect(loader.calls, 2);
      loader.finish('two');
      await _land(tester);

      // The interval restarts from the moment it became active.
      await tester.pump(_every - const Duration(seconds: 1));
      expect(loader.calls, 2);
      await tester.pump(const Duration(seconds: 1));
      expect(loader.calls, 3);
    });

    testWidgets('a failed background refresh keeps the data and offers Retry', (tester) async {
      await tester.pumpWidget(_host(_live(controller)));
      loader.finish('one');
      await _land(tester);

      await tester.pump(_every);
      loader.fail();
      await _land(tester);
      expect(find.text('one'), findsOneWidget);
      expect(find.byType(RErrorView), findsNothing);
      expect(find.text("Couldn't refresh"), findsOneWidget);

      await tester.tap(find.text('Retry'));
      await tester.pump();
      expect(loader.calls, 3);
      expect(find.text('one'), findsOneWidget);
      expect(find.text("Couldn't refresh"), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);

      loader.finish('two');
      await _land(tester);
      expect(find.text('two'), findsOneWidget);
      expect(find.text("Couldn't refresh"), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsNothing);
    });

    testWidgets('showRefreshStrip: false keeps a failed refresh quiet', (tester) async {
      await tester.pumpWidget(_host(_live(controller, showRefreshStrip: false)));
      loader.finish('one');
      await _land(tester);
      await tester.pump(_every);
      loader.fail();
      await _land(tester);
      expect(find.text('one'), findsOneWidget);
      expect(find.text("Couldn't refresh"), findsNothing);
    });

    testWidgets('pauses while another route is on top and refreshes on return', (tester) async {
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigator,
          home: Scaffold(body: _live(controller)),
        ),
      );
      loader.finish('one');
      await _land(tester);

      navigator.currentState!.push(
        MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('detail'))),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('detail'), findsOneWidget);
      await tester.pump(const Duration(minutes: 1));
      expect(loader.calls, 1);

      navigator.currentState!.pop();
      await tester.pump();
      expect(loader.calls, 2);
      loader.finish('two');
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('two'), findsOneWidget);

      await tester.pump(_every);
      expect(loader.calls, 3);
    });

    testWidgets('pauses while the app is in the background and refreshes on resume', (
      tester,
    ) async {
      addTearDown(() => tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed));
      await tester.pumpWidget(_host(_live(controller)));
      loader.finish('one');
      await _land(tester);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump(const Duration(minutes: 1));
      expect(loader.calls, 1);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      expect(loader.calls, 2);
      loader.finish('two');
      await _land(tester);
      expect(find.text('two'), findsOneWidget);

      await tester.pump(_every);
      expect(loader.calls, 3);
    });

    testWidgets('keeps polling while the window is on screen without focus', (tester) async {
      addTearDown(() => tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed));
      await tester.pumpWidget(_host(_live(controller)));
      loader.finish('one');
      await _land(tester);

      // Another window takes the focus; this one stays visible beside it.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      expect(loader.calls, 1);
      await tester.pump(_every);
      expect(loader.calls, 2);
      loader.finish('two');
      await _land(tester);
      expect(find.text('two'), findsOneWidget);
      await tester.pump(_every);
      expect(loader.calls, 3);
      loader.finish('three');
      await _land(tester);

      // Clicking back into it refreshes at once and restarts the interval.
      await tester.pump(const Duration(seconds: 4));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      expect(loader.calls, 4);
      loader.finish('four');
      await _land(tester);
      await tester.pump(_every - const Duration(seconds: 1));
      expect(loader.calls, 4);
      await tester.pump(const Duration(seconds: 1));
      expect(loader.calls, 5);
    });

    testWidgets('a window mounted without focus loads and polls', (tester) async {
      addTearDown(() => tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);

      await tester.pumpWidget(_host(_live(controller)));
      expect(loader.calls, 1);
      loader.finish('one');
      await _land(tester);
      expect(find.text('one'), findsOneWidget);

      await tester.pump(_every);
      expect(loader.calls, 2);
    });

    testWidgets('a hidden window pauses and refreshes once when it is shown again', (tester) async {
      addTearDown(() => tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed));
      await tester.pumpWidget(_host(_live(controller)));
      loader.finish('one');
      await _land(tester);

      // Minimising passes through inactive, and so does restoring.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      await tester.pump(const Duration(minutes: 1));
      expect(loader.calls, 1);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      expect(loader.calls, 2);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      loader.finish('two');
      await _land(tester);
      expect(find.text('two'), findsOneWidget);
      expect(loader.calls, 2, reason: 'the focus that follows must not queue a second load');

      await tester.pump(_every);
      expect(loader.calls, 3);
    });

    testWidgets('the first load does not wait for the window to be on screen', (tester) async {
      addTearDown(() => tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);

      // Started minimised: only the frame Flutter forces at start-up is built.
      await tester.pumpWidget(_host(_live(controller)));
      tester.binding.scheduleForcedFrame();
      await tester.pump();
      expect(loader.calls, 1);
      loader.finish('one');
      await tester.idle();

      await tester.pump(const Duration(minutes: 1));
      expect(loader.calls, 1);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      expect(loader.calls, 2);
    });

    testWidgets('returning to the route while a load is in flight queues a fresh one', (
      tester,
    ) async {
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigator,
          home: Scaffold(body: _live(controller, pollEvery: null)),
        ),
      );
      loader.finish('one');
      await _land(tester);

      // A slow refresh is still out when the user opens a detail page,
      // changes something there and comes back.
      controller.refresh(silent: true);
      navigator.currentState!.push(
        MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('detail'))),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      navigator.currentState!.pop();
      await tester.pump();
      expect(loader.calls, 2);
      expect(loader.inFlight, 1);

      loader.finish('before the change');
      await tester.idle();
      expect(loader.calls, 3);
      loader.finish('after the change');
      await tester.idle();
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('after the change'), findsOneWidget);
      expect(loader.calls, 3);
    });

    testWidgets('becoming active while a load is in flight queues a fresh one', (tester) async {
      final active = ValueNotifier(true);
      addTearDown(active.dispose);
      await tester.pumpWidget(
        _host(
          ValueListenableBuilder<bool>(
            valueListenable: active,
            builder: (_, value, _) => _live(controller, active: value),
          ),
        ),
      );
      loader.finish('one');
      await _land(tester);

      // The poll is still out while the user visits another tab and returns.
      await tester.pump(_every);
      expect(loader.calls, 2);
      active.value = false;
      await tester.pump();
      active.value = true;
      await tester.pump();
      expect(loader.calls, 2);

      loader.finish('before the change');
      await _land(tester);
      expect(loader.calls, 3);
      loader.finish('after the change');
      await _land(tester);
      expect(find.text('after the change'), findsOneWidget);
      expect(loader.calls, 3);
    });

    testWidgets('showing the window while a load is in flight queues a fresh one', (tester) async {
      addTearDown(() => tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed));
      await tester.pumpWidget(_host(_live(controller)));
      loader.finish('one');
      await _land(tester);

      await tester.pump(_every);
      expect(loader.calls, 2);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      expect(loader.calls, 2);

      loader.finish('before the change');
      await _land(tester);
      expect(loader.calls, 3);
      loader.finish('after the change');
      await _land(tester);
      expect(find.text('after the change'), findsOneWidget);
    });

    testWidgets('a load the owner already started is not repeated on mount', (tester) async {
      controller.setData('cached');
      controller.refresh();
      await tester.pumpWidget(_host(_live(controller)));
      expect(loader.calls, 1);

      loader.finish('one');
      await _land(tester);
      expect(find.text('one'), findsOneWidget);
      expect(loader.calls, 1);
    });

    testWidgets('a new pollEvery restarts the timer', (tester) async {
      final every = ValueNotifier(_every);
      addTearDown(every.dispose);
      await tester.pumpWidget(
        _host(
          ValueListenableBuilder<Duration>(
            valueListenable: every,
            builder: (_, value, _) => _live(controller, pollEvery: value),
          ),
        ),
      );
      loader.finish('one');
      await _land(tester);

      every.value = const Duration(minutes: 1);
      await tester.pump();
      await tester.pump(const Duration(seconds: 59));
      expect(loader.calls, 1);
      await tester.pump(const Duration(seconds: 1));
      expect(loader.calls, 2);
    });

    testWidgets('stops polling once removed from the tree', (tester) async {
      await tester.pumpWidget(_host(_live(controller)));
      loader.finish('one');
      await _land(tester);

      await tester.pumpWidget(_host(const Text('gone')));
      await tester.pump(const Duration(minutes: 5));
      expect(loader.calls, 1);
    });

    testWidgets('shows data pushed through the controller', (tester) async {
      await tester.pumpWidget(_host(_live(controller, pollEvery: null)));
      controller.setData('from an action');
      await tester.pump();
      expect(find.text('from an action'), findsOneWidget);

      // The load that was in flight is older than that and is ignored.
      loader.finish('stale');
      await _land(tester);
      expect(find.text('from an action'), findsOneWidget);
      expect(find.text('stale'), findsNothing);
    });
  });

  group('RLiveController', () {
    test('starts empty', () {
      expect(controller.hasData, isFalse);
      expect(controller.data, isNull);
      expect(controller.error, isNull);
      expect(controller.loading, isFalse);
    });

    test('loads, and keeps the data when a later refresh fails', () async {
      final first = controller.refresh();
      expect(controller.loading, isTrue);
      loader.finish('one');
      await first;
      expect(controller.data, 'one');
      expect(controller.hasData, isTrue);
      expect(controller.loading, isFalse);

      final second = controller.refresh(silent: true);
      expect(controller.loading, isFalse);
      loader.fail('Down.');
      await second;
      expect(controller.data, 'one');
      expect(friendlyError(controller.error!), 'Down.');

      final third = controller.refresh();
      loader.finish('two');
      await third;
      expect(controller.data, 'two');
      expect(controller.error, isNull);
    });

    test('calls made during a load share one follow-up load', () async {
      final first = controller.refresh();
      final second = controller.refresh();
      final third = controller.refresh();
      expect(loader.calls, 1);

      loader.finish('before');
      await pumpEventQueue();
      expect(loader.calls, 2);
      expect(loader.inFlight, 1);

      loader.finish('after');
      await Future.wait([first, second, third]);
      expect(loader.calls, 2);
      expect(controller.data, 'after');
      expect(controller.loading, isFalse);
    });

    test('a response older than setData is discarded', () async {
      final refresh = controller.refresh();
      controller.setData('set');
      loader.finish('stale');
      await refresh;
      expect(controller.data, 'set');

      final failing = controller.refresh();
      controller.setData('set again');
      loader.fail();
      await failing;
      expect(controller.data, 'set again');
      expect(controller.error, isNull);
    });

    test('a load that throws synchronously is reported as an error', () async {
      final throwing = RLiveController<String>(() => throw StateError('boom'));
      addTearDown(throwing.dispose);
      await throwing.refresh();
      expect(throwing.hasData, isFalse);
      expect(friendlyError(throwing.error!), 'Something went wrong. Please try again.');

      // The controller is idle again, not stuck in flight.
      var notified = 0;
      throwing.addListener(() => notified++);
      await throwing.refresh();
      expect(notified, greaterThan(0));
    });

    test('notifies when a load starts and when it lands', () async {
      var notified = 0;
      controller.addListener(() => notified++);
      final refresh = controller.refresh();
      expect(notified, 0, reason: 'must not notify synchronously: callers may be building');
      await pumpEventQueue();
      expect(notified, 1);
      loader.finish('one');
      await refresh;
      expect(notified, 2);

      // A silent refresh only notifies when it lands.
      final silent = controller.refresh(silent: true);
      await pumpEventQueue();
      expect(notified, 2);
      loader.finish('two');
      await silent;
      expect(notified, 3);
    });

    test('refresh after dispose does nothing', () async {
      final disposed = RLiveController<String>(loader.call)..dispose();
      await disposed.refresh();
      expect(loader.calls, 0);
    });
  });
}

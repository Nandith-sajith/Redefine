import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:redefine_core/redefine_core.dart';

import 'theme.dart';
import 'widgets.dart';

/// The message to show for a failed call: the API's own sentence, or a
/// generic one for anything unexpected.
String friendlyError(Object e) =>
    e is ApiException ? e.message : 'Something went wrong. Please try again.';

/// Holds the latest result of [load] for a screen, with at most one load in
/// flight at a time.
class RLiveController<T> extends ChangeNotifier {
  RLiveController(Future<T> Function() load) : _load = load;

  final Future<T> Function() _load;

  T? _data;
  bool _hasData = false;
  Object? _error;
  bool _loading = false;
  Future<void>? _inFlight;
  bool _reloadQueued = false;
  int _version = 0;
  bool _disposed = false;

  /// The last value loaded or set; kept when a later refresh fails.
  T? get data => _data;

  /// Why the most recent load failed; null once one succeeds.
  Object? get error => _error;

  /// Whether a refresh the user should see (not a silent one) is in flight.
  bool get loading => _loading;

  bool get hasData => _hasData;

  bool get _busy => _inFlight != null;

  /// Reloads. Loads never overlap: a call made while one is in flight shares
  /// one follow-up load that starts when it lands, so the result always
  /// reflects the server after this call. A [silent] refresh does not raise
  /// [loading]. Never throws; failures are reported through [error].
  Future<void> refresh({bool silent = false}) {
    if (_disposed) return Future<void>.value();
    if (!silent && !_loading) {
      _loading = true;
      // Deferred: callers may be in the middle of a build.
      scheduleMicrotask(_notify);
    }
    final running = _inFlight;
    if (running != null) {
      _reloadQueued = true;
      return running;
    }
    return _inFlight = _run();
  }

  Future<void> _run() async {
    while (true) {
      _reloadQueued = false;
      final version = _version;
      try {
        // Future.sync: a load that throws synchronously must still fail
        // asynchronously, after refresh() has recorded this run as in flight.
        final value = await Future<T>.sync(_load);
        // Stale when setData ran while this was in flight.
        if (version == _version) {
          _data = value;
          _hasData = true;
          _error = null;
        }
      } catch (e) {
        if (version == _version) _error = e;
      }
      if (!_reloadQueued || _disposed) break;
      // Show this result while the follow-up load runs.
      _notify();
    }
    _inFlight = null;
    _loading = false;
    _notify();
  }

  /// Replaces the data, e.g. with the resource an action just returned. A
  /// load already in flight is older than [value] and its result is dropped.
  void setData(T value) {
    _version++;
    _data = value;
    _hasData = true;
    _error = null;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// Shows a [RLiveController]'s data and keeps it fresh.
///
/// The first load shows a spinner, or an error with Retry when it fails. Once
/// there is data it stays on screen: a failed refresh only adds a thin strip.
/// The [builder]'s result becomes the child of a pull-to-refresh scroll view,
/// so return a `Column`, not a scrollable, and give this widget a bounded
/// height (a `Scaffold` body or an `Expanded`).
///
/// With [pollEvery] the data is reloaded on that interval, but only while
/// [active] is true, the enclosing route is on top, the app's window is on
/// screen (focused or not) and no load is in flight. Coming back from any of
/// those, or back into the window, refreshes at once. Set [active] to false
/// for tabs kept alive off screen.
class RLive<T> extends StatefulWidget {
  const RLive({
    super.key,
    required this.controller,
    required this.builder,
    this.pollEvery,
    this.active = true,
    this.padding,
    this.showRefreshStrip = true,
  });

  final RLiveController<T> controller;
  final Widget Function(BuildContext, T) builder;
  final Duration? pollEvery;
  final bool active;
  final EdgeInsetsGeometry? padding;
  final bool showRefreshStrip;

  @override
  State<RLive<T>> createState() => _RLiveState<T>();
}

class _RLiveState<T> extends State<RLive<T>> with WidgetsBindingObserver {
  Timer? _timer;
  bool _routeCurrent = true;
  bool _appVisible = true;
  bool _started = false;

  RLiveController<T> get _controller => widget.controller;

  // On web and desktop an `inactive` app has only lost input focus: its
  // window is still on screen, and a board left open beside other work must
  // keep updating.
  static bool _visibleIn(AppLifecycleState? state) =>
      state == null || state == AppLifecycleState.resumed || state == AppLifecycleState.inactive;

  bool get _live => widget.active && _routeCurrent && _appVisible;

  @override
  void initState() {
    super.initState();
    _appVisible = _visibleIn(WidgetsBinding.instance.lifecycleState);
    WidgetsBinding.instance.addObserver(this);
    _controller.addListener(_onChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final wasCurrent = _routeCurrent;
    _routeCurrent = ModalRoute.isCurrentOf(context) ?? true;
    final returned = _started && _routeCurrent && !wasCurrent;
    if (!_started || returned) {
      _started = true;
      _wake(afterAway: returned);
    } else if (_routeCurrent != wasCurrent) {
      _restartTimer();
    }
  }

  @override
  void didUpdateWidget(RLive<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    final swapped = oldWidget.controller != widget.controller;
    if (swapped) {
      oldWidget.controller.removeListener(_onChanged);
      _controller.addListener(_onChanged);
    }
    final activated = widget.active && !oldWidget.active;
    if (swapped || activated) {
      _wake(afterAway: activated);
    } else if (widget.active != oldWidget.active || widget.pollEvery != oldWidget.pollEvery) {
      _restartTimer();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final wasVisible = _appVisible;
    _appVisible = _visibleIn(state);
    if (_appVisible && !wasVisible) {
      _wake(afterAway: true);
    } else if (state == AppLifecycleState.resumed) {
      // Only focus came back: the view never stopped updating.
      _wake(afterAway: false);
    } else if (_appVisible != wasVisible) {
      _restartTimer();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _controller.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  /// Refreshes now if the view is live, and counts the next poll interval
  /// from this moment. [afterAway] says the view is back from being off
  /// screen (another route or tab on top, the window hidden).
  void _wake({required bool afterAway}) {
    _restartTimer();
    if (_controller._busy) {
      // A load that began before the view went away predates whatever was
      // done meanwhile, so one more is queued behind it.
      if (afterAway && _live) _controller.refresh(silent: true);
    } else if (_controller.hasData) {
      if (_live) _controller.refresh(silent: true);
    } else if (widget.active) {
      // The first load does not wait for the window to be on screen: an app
      // started minimised or in a background tab must not open on a spinner.
      _controller.refresh();
    }
  }

  void _restartTimer() {
    _timer?.cancel();
    _timer = null;
    final every = widget.pollEvery;
    if (!_live || every == null || every <= Duration.zero) return;
    _timer = Timer.periodic(every, (_) => _poll());
  }

  void _poll() {
    if (!mounted || !_live || _controller._busy) return;
    _controller.refresh(silent: true);
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (!controller.hasData) {
      final error = controller.error;
      if (error != null && !controller.loading) {
        return RErrorView(message: friendlyError(error), onRetry: controller.refresh);
      }
      return const Center(
        child: SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(strokeWidth: 2.6, color: RColors.teal),
        ),
      );
    }
    final failed = controller.error != null && !controller.loading && widget.showRefreshStrip;
    return Column(
      children: [
        if (failed) _RefreshStrip(onRetry: controller.refresh),
        Expanded(
          child: Stack(
            children: [
              Positioned.fill(
                child: RefreshIndicator(
                  color: RColors.teal,
                  backgroundColor: RColors.white,
                  onRefresh: () => controller.refresh(silent: true),
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: widget.padding,
                    child: widget.builder(context, controller.data as T),
                  ),
                ),
              ),
              if (controller.loading)
                const Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: LinearProgressIndicator(
                    minHeight: 2,
                    color: RColors.teal,
                    backgroundColor: RColors.tealTint,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _RefreshStrip extends StatelessWidget {
  const _RefreshStrip({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final text = GoogleFonts.plusJakartaSans(
      fontSize: 12,
      fontWeight: FontWeight.w600,
      color: const Color(0xFF7A5514),
    );
    return Material(
      color: RColors.amberTint,
      child: InkWell(
        onTap: onRetry,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.cloud_off_rounded, size: 14, color: Color(0xFF7A5514)),
              const SizedBox(width: 8),
              Flexible(
                child: Text("Couldn't refresh", style: text, overflow: TextOverflow.ellipsis),
              ),
              Text('  ·  ', style: text),
              Text('Retry', style: text.copyWith(decoration: TextDecoration.underline)),
            ],
          ),
        ),
      ),
    );
  }
}

/// A centred failure message with an optional Retry and secondary action.
class RErrorView extends StatelessWidget {
  const RErrorView({
    super.key,
    required this.message,
    this.onRetry,
    this.secondaryLabel,
    this.onSecondary,
  });

  final String message;
  final VoidCallback? onRetry;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  @override
  Widget build(BuildContext context) {
    final secondary = secondaryLabel;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const _IconDisc(Icons.cloud_off_rounded),
            const SizedBox(height: 14),
            Text(
              message,
              textAlign: TextAlign.center,
              style: RText.body.copyWith(color: RColors.inkMuted, height: 1.45),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              ROutlineButton('Retry', icon: Icons.refresh_rounded, onPressed: onRetry),
            ],
            if (secondary != null && onSecondary != null) ...[
              const SizedBox(height: 6),
              TextButton(
                onPressed: onSecondary,
                style: TextButton.styleFrom(
                  foregroundColor: RColors.inkMuted,
                  textStyle: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.w600),
                ),
                child: Text(secondary),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Placeholder for a list or section with nothing in it yet.
class REmptyState extends StatelessWidget {
  const REmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final message = this.message;
    final action = this.action;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 36),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _IconDisc(icon),
          const SizedBox(height: 14),
          Text(title, textAlign: TextAlign.center, style: RText.title),
          if (message != null) ...[
            const SizedBox(height: 6),
            Text(message, textAlign: TextAlign.center, style: RText.muted.copyWith(height: 1.45)),
          ],
          if (action != null) ...[const SizedBox(height: 16), action],
        ],
      ),
    );
  }
}

class _IconDisc extends StatelessWidget {
  const _IconDisc(this.icon);
  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
    width: 56,
    height: 56,
    decoration: const BoxDecoration(color: RColors.paper2, shape: BoxShape.circle),
    child: Icon(icon, size: 26, color: RColors.inkMuted),
  );
}

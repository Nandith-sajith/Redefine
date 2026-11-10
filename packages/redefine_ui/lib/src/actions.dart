import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:redefine_core/redefine_core.dart';

import 'async.dart';
import 'report.dart';
import 'theme.dart';

/// Runs one server action at a time for a screen: tracks [busy], reports the
/// outcome in a SnackBar and never lets a failure escape.
mixin BusyState<W extends StatefulWidget> on State<W> {
  bool _busy = false;

  /// Whether an action started with [run] is still in flight.
  bool get busy => _busy;

  /// Runs [action] unless one is already running (then returns null at once).
  ///
  /// Shows [success] when it completes. On failure returns null and shows the
  /// error, unless [onError] handles it by returning true.
  Future<T?> run<T>(
    Future<T> Function() action, {
    String? success,
    bool Function(ApiException e)? onError,
  }) async {
    if (_busy || !mounted) return null;
    setState(() => _busy = true);
    try {
      final result = await action();
      if (mounted && success != null) showRSnack(context, success);
      return result;
    } on ApiException catch (e) {
      // The screen is gone: its handler would touch a disposed State.
      if (!mounted) return null;
      final handled = onError?.call(e) ?? false;
      if (mounted && !handled) showRSnack(context, e.message, error: true);
      return null;
    } catch (error, stack) {
      // Not an API failure, so a bug in the action: log it, keep the UI alive.
      reportBug(error, stack, 'while running a screen action');
      if (mounted) showRSnack(context, friendlyError(error), error: true);
      return null;
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      } else {
        _busy = false;
      }
    }
  }
}

/// Shows [message] in a SnackBar, replacing the one on screen.
void showRSnack(BuildContext context, String message, {bool error = false}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: error ? RColors.danger : RColors.ink,
        duration: Duration(seconds: error ? 6 : 3),
        content: Text(
          message,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: RColors.white,
          ),
        ),
      ),
    );
}

/// Asks the user to confirm; resolves to false when dismissed.
Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Confirm',
  String cancelLabel = 'Cancel',
  bool destructive = false,
}) async {
  final label = GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w600);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title, style: RText.h2),
      content: Text(message, style: RText.body.copyWith(color: RColors.inkMuted, height: 1.45)),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      actions: [
        TextButton(
          // Enter must not trigger something that cannot be undone.
          autofocus: destructive,
          onPressed: () => Navigator.of(context).pop(false),
          style: TextButton.styleFrom(foregroundColor: RColors.ink, textStyle: label),
          child: Text(cancelLabel),
        ),
        FilledButton(
          autofocus: !destructive,
          onPressed: () => Navigator.of(context).pop(true),
          style: FilledButton.styleFrom(
            backgroundColor: destructive ? RColors.danger : RColors.teal,
            foregroundColor: RColors.white,
            textStyle: label,
          ),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}

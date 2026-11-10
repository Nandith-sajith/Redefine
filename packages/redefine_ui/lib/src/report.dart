import 'package:flutter/foundation.dart';

/// Logs a failure that is not an API error, and so a bug, through Flutter's
/// error reporting. The caller still tells the user something went wrong and
/// keeps the screen usable. [doing] reads like "while signing in".
void reportBug(Object error, StackTrace stack, String doing) => FlutterError.reportError(
  FlutterErrorDetails(
    exception: error,
    stack: stack,
    library: 'redefine_ui',
    context: ErrorDescription(doing),
  ),
);

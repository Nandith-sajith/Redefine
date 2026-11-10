import 'package:redefine_ui/redefine_ui.dart';
import 'package:url_launcher/url_launcher.dart';

/// The app-wide API client. Not final so that tests can swap in a mocked one
/// with [useApi].
ApiClient api = ApiClient(tokenStore: SharedPrefsTokenStore('customer'));

/// The customer's session; the signed-in user always comes from here.
SessionController session = SessionController(api: api, requiredRole: 'customer');

/// Points the whole app at [client] with a fresh session.
SessionController useApi(ApiClient client) {
  api = client;
  return session = SessionController(api: client, requiredRole: 'customer');
}

/// Opens [uri] outside the app: a new browser tab on web, the default browser
/// on Windows. Resolves to whether it could be opened.
///
/// Call it directly from a tap handler, with no `await` before it, or the
/// browser blocks the new tab as a pop-up. Replaceable in tests.
Future<bool> Function(Uri uri) openExternal = _launch;

Future<bool> _launch(Uri uri) =>
    launchUrl(uri, webOnlyWindowName: '_blank', mode: LaunchMode.externalApplication);

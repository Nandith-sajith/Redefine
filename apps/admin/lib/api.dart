import 'package:flutter/foundation.dart';
import 'package:redefine_ui/redefine_ui.dart';

/// The app's API client. The token is kept per app, so the admin, crew and
/// customer apps never share a session.
ApiClient api = ApiClient(tokenStore: SharedPrefsTokenStore('admin'));

/// The signed-in admin. Every screen reads the user from here (through
/// `SessionScope`), never from constants.
SessionController session = SessionController(api: api, requiredRole: 'admin');

/// Points the whole app at [client], with a fresh signed-out session.
@visibleForTesting
void useApi(ApiClient client) {
  api = client;
  session = SessionController(api: client, requiredRole: 'admin');
}

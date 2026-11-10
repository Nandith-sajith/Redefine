import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

/// Hands [uri] to the device: a new browser tab for web pages, the dialler
/// for `tel:` links. Resolves to whether something opened it. Replaceable in
/// tests.
Future<bool> Function(Uri uri) openExternal = _launch;

/// Whether [openExternal]'s answer says nothing about a `tel:` link. That is
/// so in a browser: it takes the link and reports success, with or without an
/// app that can dial. Replaceable in tests.
bool callsUnconfirmed = kIsWeb;

Future<bool> _launch(Uri uri) => launchUrl(
  uri,
  mode: LaunchMode.externalApplication,
  // A `tel:` link must not leave an empty tab behind.
  webOnlyWindowName: uri.isScheme('tel') ? '_self' : '_blank',
);

/// Google Maps directions from wherever the crew member is to [address].
Uri directionsUri(String address) => Uri.parse(
  'https://www.google.com/maps/dir/?api=1&destination=${Uri.encodeComponent(address.trim())}',
);

/// The `tel:` link for [phone] (digits and a leading `+` only), or null when
/// it holds no digit at all.
Uri? telUri(String phone) {
  final digits = phone.replaceAll(RegExp('[^0-9]'), '');
  if (digits.isEmpty) return null;
  final plus = phone.trimLeft().startsWith('+') ? '+' : '';
  return Uri(scheme: 'tel', path: '$plus$digits');
}

/// Opens directions to [address]; resolves to whether a maps page opened.
///
/// Call it straight from a tap handler: the link is launched before anything
/// is awaited, or browsers block the new tab as a pop-up.
Future<bool> openDirections(String address) => _open(directionsUri(address));

enum CallResult {
  /// The device's dialler took the number.
  dialling,

  /// The number went to a browser, which does not say whether an app took
  /// it; it is on the clipboard as well, in case none did.
  unconfirmedCopied,

  /// The number went to a browser, and the clipboard refused it.
  unconfirmed,

  /// Nothing here can place a call; the number is on the clipboard instead.
  copied,

  /// Neither worked.
  failed,
}

/// Starts a call to [phone], falling back to copying the number where no app
/// can place one (a desktop without a phone link, say). Where the device
/// cannot tell ([callsUnconfirmed]) it does both, so the tap never comes to
/// nothing. Like [openDirections], everything is started before the first
/// await.
Future<CallResult> callPhone(String phone) async {
  final uri = telUri(phone);
  if (uri != null && callsUnconfirmed) {
    // The copy goes first: it needs the page to still have the tap's focus.
    final copying = _copy(phone);
    final opening = _open(uri);
    final copied = await copying;
    if (await opening) return copied ? CallResult.unconfirmedCopied : CallResult.unconfirmed;
    return copied ? CallResult.copied : CallResult.failed;
  }
  if (uri != null && await _open(uri)) return CallResult.dialling;
  return await _copy(phone) ? CallResult.copied : CallResult.failed;
}

Future<bool> _copy(String text) async {
  try {
    await Clipboard.setData(ClipboardData(text: text));
    return true;
  } catch (_) {
    return false;
  }
}

// A platform without a handler answers false or throws; both mean "not opened".
Future<bool> _open(Uri uri) async {
  try {
    return await openExternal(uri);
  } catch (_) {
    return false;
  }
}

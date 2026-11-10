import 'dart:async';

import 'package:redefine_ui/redefine_ui.dart';

import 'api.dart';
import 'logic.dart';

/// The shell's tabs, in bottom-navigation order.
abstract final class CrewTab {
  static const jobs = 0;
  static const open = 1;
  static const pay = 2;
}

/// The live data the tabs and the job page share, owned by the shell.
class CrewData {
  CrewData({required this.goTo}) {
    mine.addListener(_keepPayCurrent);
  }

  /// Switches the shell to one of the [CrewTab]s.
  final void Function(int tab) goTo;

  /// Requests nobody has accepted yet, oldest first.
  final open = RLiveController<List<Job>>(() => guardCrew(() => api.jobs(scope: 'open')));

  /// Every job the crew member accepted, in any status.
  final mine = RLiveController<List<Job>>(() => guardCrew(() => api.jobs(scope: 'mine')));

  /// The pay summary. The Pay tab polls it; the Jobs tab shows its "earned
  /// today", so it is also re-read whenever [mine] shows that a job was
  /// finished (by anyone) or that a new day began.
  final pay = RLiveController<CrewPay>(() => guardCrew(() => api.crewPay('me')));

  /// The [earningsKey] the pay summary was last asked for.
  String? _payKey;

  void _keepPayCurrent() {
    final jobs = mine.data;
    // Only a list that has just arrived is news: a reload the user asked for
    // reports once more when it lands, a failed one kept the old list.
    if (jobs == null || mine.loading || mine.error != null) return;
    final key = earningsKey(jobs, DateTime.now());
    // A failed load is asked for again too: on the Jobs tab nothing else does.
    if (key == _payKey && pay.error == null) return;
    _payKey = key;
    pay.refresh(silent: true);
  }

  void dispose() {
    open.dispose();
    mine.dispose();
    pay.dispose();
  }
}

/// Whether the server refused [e] because the crew member is not (or no
/// longer) approved.
bool isApprovalError(ApiException e) => e.code == 'crew_pending' || e.code == 'crew_rejected';

/// Runs a crew-only call. When the server answers that the account is not
/// approved, the user is re-read so the approval gate replaces the app.
Future<T> guardCrew<T>(Future<T> Function() call) async {
  try {
    return await call();
  } on ApiException catch (e) {
    if (isApprovalError(e)) recheckApproval();
    rethrow;
  }
}

/// Re-reads the signed-in user in the background; the gate reacts to the
/// session. A failure changes nothing: the next refused call asks again.
void recheckApproval() =>
    unawaited(session.refreshUser().then<void>((_) {}, onError: (Object _) {}));

import 'package:flutter/widgets.dart';
import 'package:redefine_ui/redefine_ui.dart';

import 'api.dart';
import 'crew_data.dart';
import 'logic.dart';

/// Why a job action was refused, as far as the screens treat it differently.
enum JobFailure {
  /// 409 `already_claimed`: another crew member accepted it first.
  taken,

  /// 403 `crew_pending` / `crew_rejected`: the account is not approved.
  notApproved,

  /// 409 `invalid_state`: the job moved on (cancelled, started, finished).
  changed,

  /// 404: the job is no longer visible to this crew member.
  gone,

  /// Anything else; the server's own message is shown.
  other,
}

JobFailure classifyJobFailure(ApiException e) => switch (e.code) {
  'already_claimed' => JobFailure.taken,
  'crew_pending' || 'crew_rejected' => JobFailure.notApproved,
  'invalid_state' => JobFailure.changed,
  'not_found' => JobFailure.gone,
  _ => JobFailure.other,
};

/// The crew's job actions for a screen: each one runs through [BusyState.run],
/// updates the lists it affects and explains a refusal. They resolve to the
/// updated job, or null when the action did not go through.
mixin JobActions<W extends StatefulWidget> on BusyState<W> {
  CrewData get crewData;

  Future<Job?> acceptJob(String jobId) =>
      _act(() => api.claimJob(jobId), success: 'Job accepted', open: true, mine: true);

  Future<Job?> releaseJob(String jobId) =>
      _act(() => api.unclaimJob(jobId), open: true, mine: true);

  Future<Job?> startJob(String jobId) => _act(() => api.startJob(jobId), mine: true);

  /// The pay summary needs no refresh of its own: it follows [CrewData.mine].
  Future<Job?> completeJob(String jobId, {String note = ''}) =>
      _act(() => api.completeJob(jobId, crewNote: note), mine: true);

  Future<Job?> _act(
    Future<Job> Function() call, {
    String? success,
    bool open = false,
    bool mine = false,
  }) async {
    final job = await run(call, success: success, onError: _explain);
    if (job != null) {
      _show(job);
      _refresh(open: open, mine: mine);
    }
    return job;
  }

  /// Puts [job], as the server just returned it, into the shared lists right
  /// away: no screen shows the old state (a card with its button enabled
  /// again) while the reloads are under way, or after one of them failed.
  void _show(Job job) {
    final open = crewData.open.data;
    final stillOpen = open == null ? null : openAfter(open, job);
    if (stillOpen != null) crewData.open.setData(stillOpen);
    final mine = crewData.mine.data;
    if (mine != null) crewData.mine.setData(mineAfter(mine, job));
  }

  /// Handles the refusals that are no fault of the crew member; returns
  /// whether the error has been dealt with.
  bool _explain(ApiException e) {
    switch (classifyJobFailure(e)) {
      case JobFailure.taken:
        _say('Another crew member took that one');
        _refresh(open: true);
        return true;
      case JobFailure.changed:
        _say('This job changed — refreshing');
        _refresh(open: true, mine: true);
        return true;
      case JobFailure.gone:
        _say('That job is no longer available');
        _refresh(open: true, mine: true);
        return true;
      case JobFailure.notApproved:
        // The server's message is shown; the gate takes over from here.
        recheckApproval();
        return false;
      case JobFailure.other:
        return false;
    }
  }

  void _say(String message) {
    if (mounted) showRSnack(context, message);
  }

  void _refresh({bool open = false, bool mine = false}) {
    if (open) crewData.open.refresh(silent: true);
    if (mine) crewData.mine.refresh(silent: true);
  }
}

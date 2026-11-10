// Unit tests for the app's pure helpers: grouping and wording, error
// classification, and the links handed to the device.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:redefine_crew/crew_data.dart';
import 'package:redefine_crew/job_actions.dart';
import 'package:redefine_crew/launch.dart';
import 'package:redefine_crew/logic.dart';
import 'package:redefine_ui/redefine_ui.dart';

final _now = DateTime(2026, 1, 14, 9, 30);

String? _at(Duration? ago) => ago == null ? null : _now.subtract(ago).toUtc().toIso8601String();

Job _job(
  String id,
  String status, {
  Duration? requested = const Duration(hours: 5),
  Duration? claimed,
  Duration? started,
  Duration? completed,
  Duration? cancelled,
  String? cancelledBy,
}) => Job.fromJson({
  'id': id,
  'status': status,
  'crewPay': 25,
  'requestedAt': _at(requested),
  'claimedAt': _at(claimed),
  'startedAt': _at(started),
  'completedAt': _at(completed),
  'cancelledAt': _at(cancelled),
  'cancelledBy': cancelledBy,
});

CrewPay _pay({int earnedToday = 0}) => CrewPay.fromJson({'earnedToday': earnedToday});

List<String> _ids(List<Job> jobs) => [for (final job in jobs) job.id];

void main() {
  group('groupMine', () {
    test('splits by status and orders each section', () {
      final jobs = groupMine([
        _job('done_old', 'done', completed: const Duration(days: 3)),
        _job('accepted_new', 'claimed', requested: const Duration(minutes: 5)),
        _job('running_late', 'inProgress', started: const Duration(minutes: 2)),
        _job('cancelled', 'cancelled', cancelled: const Duration(days: 1)),
        _job('accepted_old', 'claimed', requested: const Duration(minutes: 40)),
        _job('running_early', 'inProgress', started: const Duration(minutes: 30)),
        _job('done_new', 'done', completed: const Duration(hours: 1)),
      ]);

      expect(_ids(jobs.inProgress), ['running_early', 'running_late']);
      // The customer who has waited longest comes first.
      expect(_ids(jobs.accepted), ['accepted_old', 'accepted_new']);
      // Finished jobs, latest first, whether done or cancelled.
      expect(_ids(jobs.recent), ['done_new', 'cancelled', 'done_old']);
      expect(jobs.toDo, 4);
      expect(jobs.isEmpty, isFalse);
    });

    test('jobs without a timestamp go last instead of throwing', () {
      final jobs = groupMine([
        _job('undated', 'done'),
        _job('dated', 'done', completed: const Duration(hours: 1)),
        _job('no_request', 'claimed', requested: null),
        _job('requested', 'claimed'),
      ]);
      expect(_ids(jobs.recent), ['dated', 'undated']);
      expect(_ids(jobs.accepted), ['requested', 'no_request']);
    });

    test('ignores statuses that cannot be the crew member\'s own work', () {
      final jobs = groupMine([_job('open', 'open'), _job('odd', 'archived')]);
      expect(jobs.isEmpty, isTrue);
      expect(jobs.toDo, 0);
    });

    test('nothing at all is empty', () {
      expect(groupMine(const []).isEmpty, isTrue);
    });
  });

  group('lists after an action', () {
    final mine = [_job('running', 'inProgress'), _job('accepted', 'claimed'), _job('old', 'done')];
    final open = [_job('first', 'open'), _job('second', 'open')];

    test('mineAfter puts the returned job on top, in place of its old state', () {
      final started = mineAfter(mine, _job('accepted', 'inProgress'));
      expect(_ids(started), ['accepted', 'running', 'old']);
      expect(started.first.status, JobStatus.inProgress);
      expect(groupMine(started).accepted, isEmpty);

      // A job that was just accepted is new to the list.
      expect(_ids(mineAfter(mine, _job('second', 'claimed'))), [
        'second',
        'running',
        'accepted',
        'old',
      ]);
      expect(mineAfter(mine, _job('running', 'done')).first.status, JobStatus.done);
    });

    test('mineAfter drops a job that was released', () {
      expect(_ids(mineAfter(mine, _job('accepted', 'open'))), ['running', 'old']);
    });

    test('openAfter takes an accepted job off the open list and leaves the rest alone', () {
      expect(_ids(openAfter(open, _job('first', 'claimed'))!), ['second']);
      // Not on the list, or open again: nothing to change.
      expect(openAfter(open, _job('accepted', 'inProgress')), isNull);
      expect(openAfter(open, _job('first', 'open')), isNull);
    });
  });

  group('wording', () {
    test('homeSummary counts the work and adds today\'s earnings once known', () {
      final busy = groupMine([_job('a', 'claimed'), _job('b', 'inProgress')]);
      final idle = groupMine([_job('c', 'done')]);
      expect(homeSummary(busy, null), '2 to do');
      expect(homeSummary(busy, _pay(earnedToday: 60)), r'2 to do · $60 earned today');
      expect(homeSummary(idle, _pay()), r'Nothing to do · $0 earned today');
    });

    test('earningsKey changes with the day and with the finished jobs, and with nothing else', () {
      final jobs = [_job('a', 'done'), _job('b', 'inProgress'), _job('c', 'claimed')];
      final key = earningsKey(jobs, _now);

      // Later the same day, the list in another order, a job started or cancelled.
      expect(earningsKey(jobs.reversed.toList(), DateTime(2026, 1, 14, 23, 59)), key);
      expect(
        earningsKey([_job('a', 'done'), _job('b', 'inProgress'), _job('c', 'inProgress')], _now),
        key,
      );
      expect(earningsKey([_job('a', 'done'), _job('b', 'cancelled')], _now), key);

      // Past midnight "today" is another day.
      expect(earningsKey(jobs, DateTime(2026, 1, 15, 0, 0, 1)), isNot(key));
      // A job got finished, by the crew member or by the office.
      expect(
        earningsKey([_job('a', 'done'), _job('b', 'done'), _job('c', 'claimed')], _now),
        isNot(key),
      );
      expect(earningsKey([_job('b', 'done')], _now), isNot(key));
      expect(earningsKey(const [], _now), isNot(key));
    });

    test('countLabel pluralises', () {
      expect(countLabel(0, 'job'), '0 jobs');
      expect(countLabel(1, 'job'), '1 job');
      expect(countLabel(3, 'open request'), '3 open requests');
      expect(countLabel(2, 'entry', 'entries'), '2 entries');
    });

    test('longDate names the weekday and the day', () {
      expect(longDate(DateTime(2026, 1, 14)), 'Wednesday, Jan 14');
      expect(longDate(DateTime(2026, 2, 1)), 'Sunday, Feb 1');
      expect(longDate(DateTime(2025, 12, 29)), 'Monday, Dec 29');
    });

    test('crewStatusLabel speaks to the crew, not the customer', () {
      expect(crewStatusLabel(JobStatus.open), 'Open');
      expect(crewStatusLabel(JobStatus.claimed), 'Accepted');
      expect(crewStatusLabel(JobStatus.inProgress), 'In progress');
      expect(crewStatusLabel(JobStatus.done), 'Done');
      expect(crewStatusLabel(JobStatus.cancelled), 'Cancelled');
    });

    test('cancelledByLabel says who cancelled', () {
      String label(String? by) => cancelledByLabel(_job('j', 'cancelled', cancelledBy: by));
      expect(label('customer'), 'Cancelled by the customer');
      expect(label('admin'), 'Cancelled by the office');
      expect(label('system'), 'Cancelled');
      expect(label(null), 'Cancelled');
    });

    test('workLabel covers shovelling only when it was ordered', () {
      expect(workLabel(shovel: false), 'Plough the driveway');
      expect(workLabel(shovel: true), contains('shovel the walkways and steps'));
    });

    test('jobStatusLine follows the job through its statuses', () {
      expect(
        jobStatusLine(_job('j', 'open', requested: const Duration(minutes: 6)), now: _now),
        'Requested 6 min ago',
      );
      expect(
        jobStatusLine(_job('j', 'claimed', claimed: const Duration(hours: 2)), now: _now),
        'Accepted 2 h ago',
      );
      final started = _now.subtract(const Duration(minutes: 20));
      expect(
        jobStatusLine(_job('j', 'inProgress', started: const Duration(minutes: 20))),
        'Started · ${fmtDayTime(started)}',
      );
      final finished = _now.subtract(const Duration(days: 2));
      expect(
        jobStatusLine(_job('j', 'done', completed: const Duration(days: 2))),
        'Completed · ${fmtDayTime(finished)}',
      );
      expect(
        jobStatusLine(
          _job('j', 'cancelled', cancelled: const Duration(days: 2), cancelledBy: 'admin'),
        ),
        'Cancelled by the office · ${fmtDayTime(finished)}',
      );
      // A timestamp the server left out is simply not mentioned.
      expect(jobStatusLine(_job('j', 'claimed')), 'Accepted');
    });
  });

  group('job action failures', () {
    ApiException error(int status, String code) => ApiException(status, code, 'Server says $code.');

    test('classifyJobFailure maps the codes the screens treat specially', () {
      expect(classifyJobFailure(error(409, 'already_claimed')), JobFailure.taken);
      expect(classifyJobFailure(error(403, 'crew_pending')), JobFailure.notApproved);
      expect(classifyJobFailure(error(403, 'crew_rejected')), JobFailure.notApproved);
      expect(classifyJobFailure(error(409, 'invalid_state')), JobFailure.changed);
      expect(classifyJobFailure(error(404, 'not_found')), JobFailure.gone);
    });

    test('everything else keeps the server\'s message', () {
      for (final e in [
        error(403, 'forbidden'),
        error(503, 'storage_unavailable'),
        error(0, 'network'),
        error(400, 'validation'),
      ]) {
        expect(classifyJobFailure(e), JobFailure.other, reason: e.code);
      }
    });

    test('isApprovalError spots a crew member who is not approved', () {
      expect(isApprovalError(error(403, 'crew_pending')), isTrue);
      expect(isApprovalError(error(403, 'crew_rejected')), isTrue);
      expect(isApprovalError(error(403, 'forbidden')), isFalse);
      expect(isApprovalError(error(401, 'unauthorized')), isFalse);
    });
  });

  group('links', () {
    test('directionsUri sends the encoded address to Google Maps', () {
      final uri = directionsUri(' 412 Maple St, Thunder Bay, ON ');
      expect(
        uri.toString(),
        'https://www.google.com/maps/dir/?api=1&destination=412%20Maple%20St%2C%20Thunder%20Bay%2C%20ON',
      );
      expect(uri.queryParameters, {'api': '1', 'destination': '412 Maple St, Thunder Bay, ON'});
      // Characters that would otherwise end the parameter survive.
      expect(
        directionsUri('5 Côté Rd & Hwy #11').queryParameters['destination'],
        '5 Côté Rd & Hwy #11',
      );
    });

    test('telUri keeps digits and a leading plus', () {
      expect(telUri('(807) 555-0111').toString(), 'tel:8075550111');
      expect(telUri(' +1 807 555 0111').toString(), 'tel:+18075550111');
      expect(telUri('807.555.0111 ext'), Uri.parse('tel:8075550111'));
      expect(telUri('call the office'), isNull);
      expect(telUri(''), isNull);
    });
  });

  group('launching', () {
    TestWidgetsFlutterBinding.ensureInitialized();

    late List<Uri> opened;
    late List<String> copied;

    /// What the device was asked to do, in order: `copy`, `open`.
    late List<String> asked;
    late Future<bool> Function(Uri) original;
    late bool originalUnconfirmed;
    bool clipboardWorks = true;

    setUp(() {
      opened = [];
      copied = [];
      asked = [];
      clipboardWorks = true;
      original = openExternal;
      originalUnconfirmed = callsUnconfirmed;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method != 'Clipboard.setData') return null;
          asked.add('copy');
          if (!clipboardWorks) throw PlatformException(code: 'denied');
          copied.add((call.arguments as Map)['text'] as String);
          return null;
        },
      );
    });

    tearDown(() {
      openExternal = original;
      callsUnconfirmed = originalUnconfirmed;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      );
    });

    void device({required bool opens, bool throws = false}) => openExternal = (uri) async {
      asked.add('open');
      opened.add(uri);
      if (throws) throw PlatformException(code: 'no_handler');
      return opens;
    };

    /// A browser: it takes every link and says it opened, true or not.
    void browser() {
      callsUnconfirmed = true;
      device(opens: true);
    }

    test('openDirections launches the maps link and reports whether it opened', () async {
      device(opens: true);
      expect(await openDirections('78 Cedar Ave'), isTrue);
      expect(opened, [directionsUri('78 Cedar Ave')]);

      device(opens: false);
      expect(await openDirections('78 Cedar Ave'), isFalse);
      device(opens: false, throws: true);
      expect(await openDirections('78 Cedar Ave'), isFalse);
    });

    test('the link is launched before anything is awaited', () {
      device(opens: true);
      openDirections('78 Cedar Ave');
      callPhone('(807) 555-0111');
      // Still inside the "tap": both links have already gone out.
      expect(opened, hasLength(2));
    });

    test('callPhone dials when the device can', () async {
      device(opens: true);
      expect(await callPhone('(807) 555-0111'), CallResult.dialling);
      expect(opened.single.toString(), 'tel:8075550111');
      expect(copied, isEmpty);
    });

    test('callPhone copies the number when nothing can place the call', () async {
      device(opens: false);
      expect(await callPhone('(807) 555-0111'), CallResult.copied);
      expect(copied, ['(807) 555-0111']);

      device(opens: false, throws: true);
      expect(await callPhone('(807) 555-0142'), CallResult.copied);
      expect(copied.last, '(807) 555-0142');
    });

    test('callPhone reports failure when not even the clipboard works', () async {
      device(opens: false);
      clipboardWorks = false;
      expect(await callPhone('(807) 555-0111'), CallResult.failed);
    });

    test(
      'in a browser callPhone dials and copies, since it cannot tell if anything dialled',
      () async {
        browser();
        expect(await callPhone('(807) 555-0111'), CallResult.unconfirmedCopied);
        expect(opened.single.toString(), 'tel:8075550111');
        expect(copied, ['(807) 555-0111']);
      },
    );

    test('in a browser the copy and the link both go out inside the tap, the copy first', () {
      browser();
      callPhone('(807) 555-0111');
      expect(asked, ['copy', 'open']);
    });

    test('in a browser a refused clipboard still leaves the call attempt', () async {
      browser();
      clipboardWorks = false;
      expect(await callPhone('(807) 555-0111'), CallResult.unconfirmed);
      expect(opened, hasLength(1));
    });

    test('in a browser a link that was not taken is reported as on other devices', () async {
      callsUnconfirmed = true;
      device(opens: false, throws: true);
      expect(await callPhone('(807) 555-0111'), CallResult.copied);
      clipboardWorks = false;
      expect(await callPhone('(807) 555-0111'), CallResult.failed);

      // Nothing to dial: the text is copied and no link goes out.
      browser();
      clipboardWorks = true;
      opened.clear();
      expect(await callPhone('ask the office'), CallResult.copied);
      expect(opened, isEmpty);
      expect(copied.last, 'ask the office');
    });
  });
}

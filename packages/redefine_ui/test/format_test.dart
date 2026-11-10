import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:redefine_ui/redefine_ui.dart';

void main() {
  test('money shows whole dollars with thousands separators', () {
    expect(money(0), r'$0');
    expect(money(45), r'$45');
    expect(money(999), r'$999');
    expect(money(1000), r'$1,000');
    expect(money(1250), r'$1,250');
    expect(money(1234567), r'$1,234,567');
    expect(money(-20), r'-$20');
  });

  group('fmtDay', () {
    test('names today and yesterday', () {
      final now = DateTime.now();
      expect(fmtDay(now), 'Today');
      expect(fmtDay(DateTime(now.year, now.month, now.day)), 'Today');
      expect(fmtDay(DateTime(now.year, now.month, now.day - 1, 23, 59)), 'Yesterday');
    });

    test('shows month and day inside the current year', () {
      final now = DateTime.now();
      // A day of this year that is neither today nor yesterday.
      final day = now.month == 1 ? DateTime(now.year, 3, 15, 8) : DateTime(now.year, 1, 15, 8);
      expect(fmtDay(day), now.month == 1 ? 'Mar 15' : 'Jan 15');
    });

    test('adds the year outside the current year', () {
      expect(fmtDay(DateTime(2001, 10, 2, 9, 42)), 'Oct 2, 2001');
      expect(fmtDay(DateTime(2001, 12, 31)), 'Dec 31, 2001');
    });

    test('a later day is never called yesterday or today', () {
      final now = DateTime.now();
      final tomorrow = DateTime(now.year, now.month, now.day + 1, 12);
      expect(fmtDay(tomorrow), isNot(anyOf('Today', 'Yesterday')));
    });
  });

  test('fmtTime uses a 12-hour clock', () {
    expect(fmtTime(DateTime(2025, 10, 2, 9, 42)), '9:42 am');
    expect(fmtTime(DateTime(2025, 10, 2, 0, 5)), '12:05 am');
    expect(fmtTime(DateTime(2025, 10, 2, 12)), '12:00 pm');
    expect(fmtTime(DateTime(2025, 10, 2, 23, 7)), '11:07 pm');
  });

  test('UTC values are shown in local time', () {
    final local = DateTime(2001, 10, 2, 9, 42);
    expect(fmtTime(local.toUtc()), fmtTime(local));
    expect(fmtDayTime(local.toUtc()), fmtDayTime(local));
  });

  test('fmtDayTime joins the day and the time', () {
    expect(fmtDayTime(DateTime(2001, 10, 2, 9, 42)), 'Oct 2, 2001, 9:42 am');
    final now = DateTime.now();
    expect(fmtDayTime(DateTime(now.year, now.month, now.day, 9, 42)), 'Today, 9:42 am');
  });

  test('fmtAgo', () {
    final now = DateTime(2025, 10, 2, 12);
    String ago(Duration d) => fmtAgo(now.subtract(d), now: now);
    expect(ago(Duration.zero), 'just now');
    expect(ago(const Duration(seconds: 59)), 'just now');
    expect(ago(const Duration(seconds: -90)), 'just now');
    expect(ago(const Duration(minutes: 6)), '6 min ago');
    expect(ago(const Duration(minutes: 59, seconds: 59)), '59 min ago');
    expect(ago(const Duration(hours: 2)), '2 h ago');
    expect(ago(const Duration(hours: 23, minutes: 59)), '23 h ago');
    expect(ago(const Duration(hours: 24)), '1 day ago');
    expect(ago(const Duration(days: 3)), '3 days ago');
    expect(fmtAgo(DateTime.now()), 'just now');
  });

  test('fmtDuration', () {
    expect(fmtDuration(const Duration(minutes: 47)), '47 min');
    expect(fmtDuration(const Duration(minutes: 47, seconds: 59)), '47 min');
    expect(fmtDuration(const Duration(minutes: 60)), '1 h 00 min');
    expect(fmtDuration(const Duration(minutes: 65)), '1 h 05 min');
    expect(fmtDuration(const Duration(hours: 2, minutes: 30)), '2 h 30 min');
    expect(fmtDuration(const Duration(seconds: 30)), '< 1 min');
    expect(fmtDuration(const Duration(minutes: -5)), '< 1 min');
  });

  test('fmtElapsed', () {
    expect(fmtElapsed(Duration.zero), '0 min');
    expect(fmtElapsed(const Duration(minutes: 18, seconds: 30)), '18 min');
    expect(fmtElapsed(const Duration(minutes: 59, seconds: 59)), '59 min');
    expect(fmtElapsed(const Duration(hours: 1, minutes: 5, seconds: 22)), '1:05:22');
    expect(fmtElapsed(const Duration(hours: 10)), '10:00:00');
    expect(fmtElapsed(const Duration(seconds: -5)), '0 min');
  });

  test('service labels', () {
    expect(serviceLabel(shovel: false), 'Plough');
    expect(serviceLabel(shovel: true), 'Plough + shovel');
    expect(serviceIcon(shovel: true), serviceIcon(shovel: false));
  });

  test('every illustration key has its own icon; unknown keys fall back to house', () {
    expect(kIllustrations, [
      'house',
      'bungalow',
      'townhouse',
      'cabin',
      'duplex',
      'farmhouse',
      'cottage',
      'apartment',
      'garage',
    ]);
    expect(kIllustrations.map(illustrationIcon).toSet(), hasLength(kIllustrations.length));
    expect(illustrationIcon('house'), Icons.house_rounded);
    expect(illustrationIcon(''), Icons.house_rounded);
    expect(illustrationIcon('castle'), Icons.house_rounded);
    expect(illustrationColor(''), illustrationColor('house'));
  });
}

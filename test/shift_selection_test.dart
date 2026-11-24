import 'package:flutter_test/flutter_test.dart';
import 'package:supermarket_staff/data/models.dart';
import 'package:supermarket_staff/data/providers.dart';

Shift shift(String id, DateTime start, DateTime end, {DateTime? checkedInAt}) => Shift(
      shiftId: id,
      start: start,
      end: end,
      label: id,
      zoneName: 'Zone A',
      checkedInAt: checkedInAt,
    );

void main() {
  test('the previous night shift remains available for check-in after midnight', () {
    final overnight = shift('night', DateTime(2026, 11, 24, 23, 49), DateTime(2026, 11, 25, 7, 49));
    final morning = shift('morning', DateTime(2026, 11, 25, 8), DateTime(2026, 11, 25, 16));
    final shifts = [morning, overnight];

    expect(primaryShiftForToday(shifts, DateTime(2026, 11, 25, 0, 9)), overnight);
    expect(primaryShiftForToday(shifts, overnight.end), morning);
  });

  test('an overnight check-in window can open before the shift date', () {
    final overnight = shift('night', DateTime(2026, 11, 25, 0, 5), DateTime(2026, 11, 25, 8, 5));

    expect(primaryShiftForToday([overnight], DateTime(2026, 11, 24, 23, 49)), isNull);
    expect(primaryShiftForToday([overnight], overnight.checkInOpensAt), overnight);
  });

  test('an ended checked-in shift does not hide a later shift check-in', () {
    final day = DateTime(2026, 10, 29);
    final now = DateTime(2026, 10, 29, 7, 46);
    final selected = primaryShiftForToday([
      shift('early', day.add(const Duration(hours: 2, minutes: 20)), day.add(const Duration(hours: 6, minutes: 20)),
          checkedInAt: day.add(const Duration(hours: 2, minutes: 5))),
      shift('eight', day.add(const Duration(hours: 8)), day.add(const Duration(hours: 16))),
    ], now);

    expect(selected?.shiftId, 'eight');
    expect(now.isBefore(selected!.checkInOpensAt), isFalse);
  });

  test('a currently checked-in shift remains the primary shift', () {
    final day = DateTime(2026, 10, 29);
    final now = DateTime(2026, 10, 29, 5);
    final selected = primaryShiftForToday([
      shift('early', day.add(const Duration(hours: 2, minutes: 20)), day.add(const Duration(hours: 6, minutes: 20)),
          checkedInAt: day.add(const Duration(hours: 2, minutes: 5))),
      shift('eight', day.add(const Duration(hours: 8)), day.add(const Duration(hours: 16))),
    ], now);

    expect(selected?.shiftId, 'early');
  });
}

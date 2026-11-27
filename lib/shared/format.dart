import 'package:intl/intl.dart';

final _hm = DateFormat('HH:mm');
final _dayShort = DateFormat('EEE, MMM d');
final _dayLong = DateFormat('EEEE d MMM');

String hm(DateTime t) => _hm.format(t.toLocal());
String dayShort(DateTime t) => _dayShort.format(t.toLocal());
String dayLong(DateTime t) => _dayLong.format(t.toLocal());
String timeRange(DateTime a, DateTime b) => '${hm(a)}–${hm(b)}';

/// "Zone B · Checkout 3": the zone's short name plus the spot, when there is one.
String place(String zoneName, String location) =>
    [zoneName.split(' · ').first, location].where((s) => s.isNotEmpty).join(' · ');

String timeAgo(DateTime then, DateTime now) {
  final d = now.difference(then);
  if (d.inMinutes < 1) return 'now';
  if (d.inMinutes < 60) return '${d.inMinutes} min';
  if (d.inHours < 24) return '${d.inHours} h';
  return dayShort(then);
}

/// "in 2 h", "in 25 min", "Now" for an upcoming start.
String startsIn(DateTime start, DateTime end, DateTime now) {
  if (!now.isBefore(start) && now.isBefore(end)) return 'Now';
  if (!now.isBefore(end)) return 'Ended';
  final d = start.difference(now);
  if (d.inMinutes < 60) return 'in ${d.inMinutes.clamp(1, 59)} min';
  if (d.inHours < 24) return 'in ${d.inHours} h';
  return 'in ${d.inDays} d';
}

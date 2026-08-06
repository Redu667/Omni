import 'package:html_unescape/html_unescape.dart';

final _unescape = HtmlUnescape();

/// Convert a fragment of HTML (Mastodon statuses, RSS descriptions)
/// into readable plain text.
String htmlToPlainText(String html) {
  var text = html
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'</p>\s*<p[^>]*>', caseSensitive: false), '\n\n')
      .replaceAll(RegExp(r'<[^>]+>'), '');
  text = _unescape.convert(text);
  return text.trim();
}

const _months = {
  'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
  'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
};

const _tzOffsets = {
  'ut': 0, 'gmt': 0, 'utc': 0, 'z': 0,
  'est': -5, 'edt': -4, 'cst': -6, 'cdt': -5,
  'mst': -7, 'mdt': -6, 'pst': -8, 'pdt': -7,
};

/// Parse the date format X returns on tweets, which puts the month before
/// the day and the year last: "Wed Aug 05 20:15:00 +0000 2026".
DateTime? parseTwitterDate(String? input) {
  if (input == null || input.trim().isEmpty) return null;
  final m = RegExp(
    r'^\w{3}\s+(\w{3})\s+(\d{1,2})\s+(\d{2}):(\d{2}):(\d{2})\s+([+-]\d{4})\s+(\d{4})$',
  ).firstMatch(input.trim());
  if (m == null) return DateTime.tryParse(input.trim())?.toUtc();

  final month = _months[m.group(1)!.toLowerCase()];
  if (month == null) return null;

  final tz = m.group(6)!;
  final sign = tz.startsWith('-') ? -1 : 1;
  final offsetMinutes =
      sign * (int.parse(tz.substring(1, 3)) * 60 + int.parse(tz.substring(3, 5)));

  return DateTime.utc(
    int.parse(m.group(7)!),
    month,
    int.parse(m.group(2)!),
    int.parse(m.group(3)!),
    int.parse(m.group(4)!),
    int.parse(m.group(5)!),
  ).subtract(Duration(minutes: offsetMinutes));
}

/// Parse an RFC 822/1123 date as used by RSS 2.0,
/// e.g. "Tue, 05 Aug 2026 20:15:00 +0000". Falls back to ISO 8601.
DateTime? parseRfc822OrIso(String? input) {
  if (input == null || input.trim().isEmpty) return null;
  final s = input.trim();

  final iso = DateTime.tryParse(s);
  if (iso != null) return iso.toUtc();

  final m = RegExp(
    r'^(?:\w{3},\s*)?(\d{1,2})\s+(\w{3})\w*\s+(\d{2,4})\s+(\d{1,2}):(\d{2})(?::(\d{2}))?\s*([+-]\d{4}|\w{1,3})?',
    caseSensitive: false,
  ).firstMatch(s);
  if (m == null) return null;

  final month = _months[m.group(2)!.toLowerCase()];
  if (month == null) return null;

  var year = int.parse(m.group(3)!);
  if (year < 100) year += year >= 70 ? 1900 : 2000;

  var offsetMinutes = 0;
  final tz = m.group(7);
  if (tz != null) {
    if (tz.startsWith('+') || tz.startsWith('-')) {
      final sign = tz.startsWith('-') ? -1 : 1;
      offsetMinutes =
          sign * (int.parse(tz.substring(1, 3)) * 60 + int.parse(tz.substring(3, 5)));
    } else {
      offsetMinutes = (_tzOffsets[tz.toLowerCase()] ?? 0) * 60;
    }
  }

  return DateTime.utc(
    year,
    month,
    int.parse(m.group(1)!),
    int.parse(m.group(4)!),
    int.parse(m.group(5)!),
    int.parse(m.group(6) ?? '0'),
  ).subtract(Duration(minutes: offsetMinutes));
}

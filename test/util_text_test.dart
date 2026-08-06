import 'package:flutter_test/flutter_test.dart';
import 'package:omni/util/text.dart';

void main() {
  group('htmlToPlainText', () {
    test('strips tags and unescapes entities', () {
      expect(
        htmlToPlainText('<p>Hello <a href="x">world</a> &amp; friends</p>'),
        'Hello world & friends',
      );
    });

    test('converts <br> and paragraph breaks to newlines', () {
      expect(
        htmlToPlainText('<p>one<br/>two</p><p>three</p>'),
        'one\ntwo\n\nthree',
      );
    });
  });

  group('parseRfc822OrIso', () {
    test('parses RFC 822 with numeric offset', () {
      final dt = parseRfc822OrIso('Tue, 05 Aug 2026 20:15:00 +0200');
      expect(dt, DateTime.utc(2026, 8, 5, 18, 15));
    });

    test('parses RFC 822 with GMT', () {
      final dt = parseRfc822OrIso('Wed, 06 Aug 2026 01:00:00 GMT');
      expect(dt, DateTime.utc(2026, 8, 6, 1, 0));
    });

    test('parses named US timezone', () {
      final dt = parseRfc822OrIso('Wed, 06 Aug 2026 01:00:00 EST');
      expect(dt, DateTime.utc(2026, 8, 6, 6, 0));
    });

    test('parses ISO 8601', () {
      final dt = parseRfc822OrIso('2026-08-06T10:00:00Z');
      expect(dt, DateTime.utc(2026, 8, 6, 10, 0));
    });

    test('returns null for garbage', () {
      expect(parseRfc822OrIso('not a date'), isNull);
      expect(parseRfc822OrIso(null), isNull);
      expect(parseRfc822OrIso(''), isNull);
    });
  });
}

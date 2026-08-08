import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:omni/services/article_fetcher.dart';
import 'package:omni/services/readability.dart';

String page(String body) => '''
<!doctype html><html><head><title>A page</title></head>
<body>$body</body></html>''';

/// Long enough to clear the minimum-length bar, so tests exercise the
/// scoring rather than the floor.
String paragraphs(int count, {String prefix = 'Sentence'}) => [
      for (var i = 0; i < count; i++)
        '<p>$prefix $i: the quick brown fox jumps over the lazy dog, and '
            'then it does so again, at some length, to look like prose.</p>',
    ].join();

void main() {
  group('finds the article', () {
    test('among navigation and a footer', () {
      final html = page('''
        <nav><a href="/a">Home</a><a href="/b">About</a><a href="/c">More</a></nav>
        <article>${paragraphs(4, prefix: 'Body')}</article>
        <footer><a href="/x">Terms</a><a href="/y">Privacy</a></footer>
      ''');

      final article = extractArticleText(html)!;
      expect(article, contains('Body 0'));
      expect(article, contains('Body 3'));
      expect(article, isNot(contains('Terms')));
      expect(article, isNot(contains('About')));
    });

    test('and drops a related-links block that scores well on length', () {
      final related = [
        for (var i = 0; i < 8; i++)
          '<p><a href="/r$i">Another article you might like, number $i, with '
              'a reasonably long headline</a></p>',
      ].join();
      final html = page('''
        <div class="content">${paragraphs(5, prefix: 'Body')}</div>
        <div class="related-posts">$related</div>
      ''');

      final article = extractArticleText(html)!;
      expect(article, contains('Body 0'));
      expect(article, isNot(contains('might like')));
    });

    test('keeps paragraph breaks rather than running it together', () {
      final article = extractArticleText(
          page('<div>${paragraphs(4, prefix: 'Body')}</div>'))!;
      expect(article, contains('\n\n'));
    });

    test('marks list items so a list still reads as one', () {
      final html = page('''
        <article>
          ${paragraphs(3, prefix: 'Body')}
          <ul><li>The first considered point, spelled out at some length</li>
              <li>The second considered point, also spelled out at length</li></ul>
        </article>
      ''');
      expect(extractArticleText(html), contains('• The first considered'));
    });

    test('strips scripts and styles', () {
      final html = page('''
        <script>var tracking = "should never appear in the article";</script>
        <style>.x { content: "neither should this"; }</style>
        <article>${paragraphs(4, prefix: 'Body')}</article>
      ''');

      final article = extractArticleText(html)!;
      expect(article, isNot(contains('tracking')));
      expect(article, isNot(contains('neither should')));
    });
  });

  group('declines rather than guessing', () {
    test('on a page with no prose', () {
      final html = page('''
        <nav><a href="/a">One</a><a href="/b">Two</a><a href="/c">Three</a></nav>
      ''');
      expect(extractArticleText(html), isNull);
    });

    test('on a stub too short to be an article', () {
      expect(extractArticleText(page('<p>Sign in to continue.</p>')), isNull);
    });

    test('on something that is not HTML at all', () {
      expect(extractArticleText('%PDF-1.4 not html'), isNull);
    });

    test('on an empty body', () {
      expect(extractArticleText(page('')), isNull);
    });
  });

  group('fetching', () {
    ArticleFetcher fetcher(http.Client client) =>
        ArticleFetcher(httpClient: client);

    test('returns the extracted text', () async {
      final client = MockClient((_) async => http.Response(
            page('<article>${paragraphs(4, prefix: 'Body')}</article>'),
            200,
            headers: {'content-type': 'text/html; charset=utf-8'},
          ));

      final text = await fetcher(client).fetch('https://example.com/a');
      expect(text, contains('Body 0'));
    });

    test('only fetches once per url', () async {
      var calls = 0;
      final client = MockClient((_) async {
        calls++;
        return http.Response(
            page('<article>${paragraphs(4, prefix: 'Body')}</article>'), 200);
      });

      final subject = fetcher(client);
      await subject.fetch('https://example.com/a');
      await subject.fetch('https://example.com/a');

      expect(calls, 1);
      expect(subject.cached('https://example.com/a'), isNotNull);
    });

    test('says what went wrong rather than throwing a status code', () async {
      final client = MockClient((_) async => http.Response('nope', 404));

      await expectLater(
        fetcher(client).fetch('https://example.com/a'),
        throwsA(isA<ArticleException>().having((e) => e.message, 'message',
            allOf(contains('example.com'), contains('404')))),
      );
    });

    test('names the likely cause when there is no article', () async {
      final client = MockClient(
          (_) async => http.Response(page('<p>Subscribe to read.</p>'), 200));

      await expectLater(
        fetcher(client).fetch('https://example.com/a'),
        throwsA(isA<ArticleException>()
            .having((e) => e.message, 'message', contains('paywall'))),
      );
    });

    test('refuses a non-page', () async {
      final client = MockClient((_) async => http.Response('{}', 200,
          headers: {'content-type': 'application/json'}));

      await expectLater(
        fetcher(client).fetch('https://example.com/a.json'),
        throwsA(isA<ArticleException>()
            .having((e) => e.message, 'message', contains('not a web page'))),
      );
    });

    test('refuses a page too large to be worth downloading', () async {
      final client = MockClient((_) async => http.Response('x' * 10, 200));
      final subject = ArticleFetcher(httpClient: client, maxBytes: 5);

      await expectLater(
        subject.fetch('https://example.com/a'),
        throwsA(isA<ArticleException>()
            .having((e) => e.message, 'message', contains('too large'))),
      );
    });

    test('refuses something that is not a link', () async {
      final client = MockClient((_) async => http.Response('', 200));
      await expectLater(
        fetcher(client).fetch('not a url'),
        throwsA(isA<ArticleException>()),
      );
    });

    test('an unreachable host reads as unreachable', () async {
      final client = MockClient((_) async => throw Exception('no route'));
      await expectLater(
        fetcher(client).fetch('https://example.com/a'),
        throwsA(isA<ArticleException>()
            .having((e) => e.message, 'message', contains("Couldn't reach"))),
      );
    });
  });
}

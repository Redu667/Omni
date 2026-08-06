import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:omni/models/feed_source.dart';
import 'package:omni/models/network.dart';
import 'package:omni/services/source_client.dart';
import 'package:omni/services/source_validator.dart';

void main() {
  test('passes through a working source', () async {
    final client = MockClient((req) async => http.Response(
        '<rss version="2.0"><channel><title>Ok</title></channel></rss>', 200));
    final validator = SourceValidator(httpClient: client);

    final source = FeedSource(
      id: '1',
      network: Network.rss,
      displayName: 'Feed',
      params: {'url': 'https://example.com/feed.xml'},
    );
    expect(await validator.validate(source), same(source));
  });

  test('fixes an RSS source pointing at an HTML page', () async {
    final client = MockClient((req) async {
      if (req.url.path == '/feed.xml') {
        return http.Response(
            '<rss version="2.0"><channel><title>Found</title></channel></rss>',
            200);
      }
      return http.Response(
          '<html><head><link rel="alternate" type="application/rss+xml" '
          'href="/feed.xml"></head></html>',
          200);
    });
    final validator = SourceValidator(httpClient: client);

    final source = FeedSource(
      id: '1',
      network: Network.rss,
      displayName: 'example.com',
      params: {'url': 'https://example.com'},
    );
    final fixed = await validator.validate(source);
    expect(fixed.params['url'], 'https://example.com/feed.xml');
    expect(fixed.id, source.id);
  });

  test('throws a readable error for a broken source', () async {
    final client = MockClient((_) async => http.Response('nope', 404));
    final validator = SourceValidator(httpClient: client);

    final source = FeedSource(
      id: '1',
      network: Network.reddit,
      displayName: 'r/doesnotexist',
      params: {'subreddit': 'doesnotexist'},
    );
    expect(validator.validate(source), throwsA(isA<SourceFetchException>()));
  });
}

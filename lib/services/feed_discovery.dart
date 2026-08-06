import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';

/// Finds the RSS/Atom feed URL advertised by an HTML page's
/// `<link rel="alternate" type="application/rss+xml" ...>` tag.
/// Returns null if the page doesn't advertise one.
String? findFeedLinkInHtml(String html, Uri baseUri) {
  for (final match in RegExp(r'<link\b[^>]*>', caseSensitive: false)
      .allMatches(html)) {
    final tag = match.group(0)!;
    if (!RegExp('''rel\\s*=\\s*["']?alternate''', caseSensitive: false)
        .hasMatch(tag)) {
      continue;
    }
    if (!RegExp(r'(rss|atom)\+?xml', caseSensitive: false).hasMatch(tag)) {
      continue;
    }
    final href = RegExp('''href\\s*=\\s*["']([^"']+)["']''',
            caseSensitive: false)
        .firstMatch(tag)
        ?.group(1);
    if (href != null && href.isNotEmpty) {
      return baseUri.resolve(href).toString();
    }
  }
  return null;
}

/// Fetches [pageUrl] and, if it's an HTML page, returns the feed URL it
/// advertises. Returns null when nothing is discovered.
Future<String?> discoverFeedUrl(http.Client client, String pageUrl) async {
  final uri =
      Uri.parse(pageUrl.startsWith('http') ? pageUrl : 'https://$pageUrl');
  try {
    final res = await client.get(uri, headers: {
      'User-Agent': 'Omni/0.2 (+feed reader)',
      'Accept': 'text/html, application/xhtml+xml',
    });
    if (res.statusCode != 200) return null;
    return findFeedLinkInHtml(res.body, uri);
  } catch (_) {
    return null;
  }
}

class OpmlFeed {
  const OpmlFeed({required this.title, required this.url});
  final String title;
  final String url;
}

/// Parses OPML (the standard feed-reader export format) into feed entries.
/// Throws [FormatException] when the input isn't OPML.
List<OpmlFeed> parseOpml(String content) {
  final XmlDocument doc;
  try {
    doc = XmlDocument.parse(content);
  } on XmlException {
    throw const FormatException('Not a valid OPML file');
  }
  if (doc.findAllElements('opml').isEmpty) {
    throw const FormatException('Not a valid OPML file');
  }

  final feeds = <OpmlFeed>[];
  final seen = <String>{};
  for (final outline in doc.findAllElements('outline')) {
    final url = outline.getAttribute('xmlUrl');
    if (url == null || url.isEmpty || !seen.add(url)) continue;
    final title = outline.getAttribute('title') ??
        outline.getAttribute('text') ??
        (Uri.tryParse(url)?.host ?? url);
    feeds.add(OpmlFeed(title: title, url: url));
  }
  return feeds;
}

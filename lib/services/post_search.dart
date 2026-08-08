import '../models/feed_item.dart';

/// Searching the posts already on the device.
///
/// Deliberately local: it's instant, works offline, and needs nothing from
/// five different search APIs with five different rate limits. Searching the
/// networks themselves is a separate feature, not a substitute for this one.

/// Splits what the user typed into the words a post has to contain.
List<String> searchTerms(String query) => query
    .toLowerCase()
    .split(RegExp(r'\s+'))
    .where((t) => t.isNotEmpty)
    .toList();

/// Everything about a post that's worth searching, flattened.
///
/// Includes the quoted post and link card: a post whose only text is "this"
/// above a quote should still be findable by what it was quoting.
String searchableText(FeedItem item) => [
      item.title ?? '',
      item.text,
      item.fullText ?? '',
      item.author,
      item.handle ?? '',
      item.context ?? '',
      item.flair ?? '',
      item.quoted?.text ?? '',
      item.quoted?.author ?? '',
      item.linkCard?.title ?? '',
      item.linkCard?.description ?? '',
      // Alt text describes the picture, which is sometimes the whole post.
      for (final m in item.media) m.alt ?? '',
    ].join('\n').toLowerCase();

/// Every term must appear somewhere in the post, so "flutter release" finds
/// posts mentioning both rather than either.
bool postMatches(FeedItem item, List<String> terms) {
  if (terms.isEmpty) return false;
  final haystack = searchableText(item);
  return terms.every(haystack.contains);
}

/// Posts matching [query], in the order given. An empty or whitespace-only
/// query matches nothing rather than everything — an empty search box means
/// "I haven't asked yet", not "show me all of it".
List<FeedItem> searchPosts(Iterable<FeedItem> items, String query) {
  final terms = searchTerms(query);
  if (terms.isEmpty) return const [];
  return items.where((i) => postMatches(i, terms)).toList();
}

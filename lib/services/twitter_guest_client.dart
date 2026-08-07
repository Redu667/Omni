import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/feed_item.dart';
import '../models/network.dart';
import '../util/text.dart';
import 'source_client.dart';
import 'twitter_guest_config.dart';
import 'twitter_guest_session.dart';
import 'twitter_session_store.dart';

/// Reads public tweets the way X's own logged-out web client does: activate an
/// anonymous guest token, then call the internal GraphQL endpoints with it.
///
/// This is the approach Squawker and Nitter use. It needs no API plan, but it
/// is not a supported interface — X rotates the GraphQL query IDs on every
/// frontend deploy, so when fetches start failing the fix is usually to paste
/// fresh query IDs into Settings → Twitter (X) access.
class TwitterGuestClient extends SourceClient {
  TwitterGuestClient(
    super.source,
    super.httpClient, {
    required this.config,
    required this.session,
    this.account,
  });

  final TwitterGuestConfig config;
  final TwitterGuestSession session;

  /// A signed-in x.com session, when the user has logged in. Anonymous guest
  /// access is increasingly served a stale timeline, so an account is the
  /// difference between live results and year-old ones.
  final TwitterSession? account;

  bool get _authenticated => account != null;

  static const _host = 'api.twitter.com';

  @override
  Future<List<FeedItem>> fetchLatest({int limit = 40}) async {
    final usernames = (source.params['usernames'] ?? '')
        .split(RegExp(r'[,\s]+'))
        .where((u) => u.isNotEmpty)
        .map((u) => u.replaceAll('@', ''))
        .toList();
    if (usernames.isEmpty) {
      throw SourceFetchException(source.displayName, 'no usernames set');
    }

    final perUser = (limit / usernames.length).ceil().clamp(5, 100);
    final items = <FeedItem>[];
    final failures = <String>[];

    for (final username in usernames) {
      try {
        final userId = await _resolveUserId(username);
        items.addAll(await _fetchUserTweets(userId, perUser));
      } on TwitterGuestException catch (e) {
        failures.add('@$username: ${e.message}');
      }
    }

    // Every account failing means the setup is broken, not the accounts.
    if (items.isEmpty && failures.isNotEmpty) {
      throw SourceFetchException(source.displayName, failures.first);
    }

    items.sort((a, b) => b.createdAt.compareTo(a.createdAt));

    // Anonymous access degrades quietly: X keeps answering 200 but serves a
    // stale slice of the timeline. Silently showing year-old posts as if
    // they were current is worse than saying nothing, so call it out.
    if (items.isNotEmpty) {
      final age = DateTime.now().toUtc().difference(items.first.createdAt);
      if (age > staleThreshold) {
        throw SourceFetchException(
          source.displayName,
          _authenticated
              ? 'X returned only posts older than ${age.inDays} days even '
                  'though you are signed in, which usually means the query IDs '
                  'need refreshing in Settings → Twitter (X) access.'
              : 'X returned only posts older than ${age.inDays} days — '
                  'anonymous access is being served a stale timeline rather '
                  'than the live one. Signing in from Settings → Twitter (X) '
                  'access is the reliable fix; X gives real timelines to '
                  'accounts and stale ones to guests.',
        );
      }
    }
    return items;
  }

  /// How out of date the newest post must be before the timeline is treated
  /// as stale rather than merely quiet. Generous, so genuinely inactive
  /// accounts don't trip it.
  static const staleThreshold = Duration(days: 45);

  Future<String> _resolveUserId(String username) async {
    final body = await _graphql(
      queryId: config.userByScreenNameQueryId,
      operation: 'UserByScreenName',
      variables: {
        'screen_name': username,
        'withSafetyModeUserFields': true,
      },
    );

    final result = _dig(body, ['data', 'user', 'result']);
    final restId = result?['rest_id'] as String?;
    if (restId == null) {
      final reason = result?['reason'] as String?;
      throw TwitterGuestException(reason == 'Suspended'
          ? 'account is suspended'
          : 'no such account, or it is private');
    }
    return restId;
  }

  Future<List<FeedItem>> _fetchUserTweets(String userId, int count) async {
    final body = await _graphql(
      queryId: config.userTweetsQueryId,
      operation: 'UserTweets',
      variables: {
        'userId': userId,
        'count': count,
        'includePromotedContent': false,
        'withQuickPromoteEligibilityTweetFields': false,
        'withVoice': true,
        'withV2Timeline': true,
      },
    );

    final timeline = _dig(body, ['data', 'user', 'result', 'timeline_v2']) ??
        _dig(body, ['data', 'user', 'result', 'timeline']);
    final instructions =
        (_dig(timeline, ['timeline', 'instructions']) as List?) ?? const [];

    final items = <FeedItem>[];
    for (final instruction in instructions.cast<Map<String, dynamic>>()) {
      if (instruction['type'] != 'TimelineAddEntries') continue;
      for (final entry
          in (instruction['entries'] as List? ?? const []).cast<Map<String, dynamic>>()) {
        items.addAll(_itemsFromEntry(entry));
      }
    }
    return items;
  }

  Iterable<FeedItem> _itemsFromEntry(Map<String, dynamic> entry) sync* {
    final entryId = entry['entryId'] as String? ?? '';
    if (entryId.startsWith('cursor-')) return;

    final content = entry['content'] as Map<String, dynamic>?;
    if (content == null) return;

    // A single tweet.
    final single = _dig(content, ['itemContent', 'tweet_results', 'result']);
    if (single != null) {
      final item = _toItem(single);
      if (item != null) yield item;
      return;
    }

    // A self-thread renders as a module of several tweets.
    for (final moduleItem
        in (content['items'] as List? ?? const []).cast<Map<String, dynamic>>()) {
      final nested = _dig(
          moduleItem, ['item', 'itemContent', 'tweet_results', 'result']);
      if (nested == null) continue;
      final item = _toItem(nested);
      if (item != null) yield item;
    }
  }

  /// Limited-visibility tweets wrap the real payload one level down.
  static Map<String, dynamic>? _unwrap(dynamic node) {
    if (node is! Map) return null;
    final map = node.cast<String, dynamic>();
    if (map['__typename'] == 'TweetWithVisibilityResults') {
      final inner = map['tweet'];
      return inner is Map ? inner.cast<String, dynamic>() : null;
    }
    return map;
  }

  FeedItem? _toItem(dynamic raw) {
    final outer = _unwrap(raw);
    if (outer == null) return null;

    String? repostedBy;
    var tweet = outer;
    final retweet =
        _unwrap(_dig(outer, ['legacy', 'retweeted_status_result', 'result']));
    if (retweet != null) {
      repostedBy = _userField(outer, 'name');
      tweet = retweet;
    }

    final legacy = tweet['legacy'] as Map<String, dynamic>?;
    if (legacy == null) return null;

    final restId = tweet['rest_id'] as String?;
    final screenName = _userField(tweet, 'screen_name') ?? '';

    // Long posts carry their full body outside the 280-char legacy field.
    final noteText =
        _dig(tweet, ['note_tweet', 'note_tweet_results', 'result', 'text'])
            as String?;
    final text = _cleanText(
      noteText ?? legacy['full_text'] as String? ?? '',
      legacy,
    );

    final media = (_dig(legacy, ['extended_entities', 'media']) as List? ??
            _dig(legacy, ['entities', 'media']) as List? ??
            const [])
        .cast<Map<String, dynamic>>();

    return FeedItem(
      id: '${source.id}:${restId ?? legacy['id_str']}',
      sourceId: source.id,
      network: Network.twitter,
      author: _userField(tweet, 'name') ?? screenName,
      handle: screenName.isNotEmpty ? '@$screenName' : null,
      avatarUrl: _userField(tweet, 'profile_image_url_https'),
      text: text,
      url: screenName.isNotEmpty && restId != null
          ? 'https://x.com/$screenName/status/$restId'
          : null,
      imageUrls: [
        for (final m in media)
          if (m['media_url_https'] != null) m['media_url_https'] as String,
      ],
      repostedBy: repostedBy,
      likes: legacy['favorite_count'] as int?,
      reposts: legacy['retweet_count'] as int?,
      replies: legacy['reply_count'] as int?,
      context: source.displayName,
      createdAt: parseTwitterDate(legacy['created_at'] as String?) ??
          DateTime.now().toUtc(),
    );
  }

  /// Expands t.co links back to readable URLs and drops the trailing t.co
  /// link X appends for attached media.
  String _cleanText(String text, Map<String, dynamic> legacy) {
    var out = text;
    for (final url in (_dig(legacy, ['entities', 'urls']) as List? ?? const [])
        .cast<Map<String, dynamic>>()) {
      final short = url['url'] as String?;
      final expanded = url['expanded_url'] as String?;
      if (short != null && expanded != null) {
        out = out.replaceAll(short, expanded);
      }
    }
    for (final m in (_dig(legacy, ['extended_entities', 'media']) as List? ??
            const [])
        .cast<Map<String, dynamic>>()) {
      final short = m['url'] as String?;
      if (short != null) out = out.replaceAll(short, '');
    }
    return htmlToPlainText(out).trim();
  }

  /// User fields moved between `legacy` and `core` across X's frontend
  /// revisions, so check both.
  String? _userField(Map<String, dynamic> tweet, String field) {
    final user = _dig(tweet, ['core', 'user_results', 'result']);
    if (user == null) return null;

    final fromLegacy = _dig(user, ['legacy', field]) as String?;
    if (fromLegacy != null && fromLegacy.isNotEmpty) return fromLegacy;

    final core = user['core'] as Map<String, dynamic>?;
    final fromCore = switch (field) {
      'name' => core?['name'] as String?,
      'screen_name' => core?['screen_name'] as String?,
      'profile_image_url_https' =>
        _dig(user, ['avatar', 'image_url']) as String?,
      _ => null,
    };
    return (fromCore != null && fromCore.isNotEmpty) ? fromCore : null;
  }

  Future<Map<String, dynamic>> _graphql({
    required String queryId,
    required String operation,
    required Map<String, dynamic> variables,
  }) async {
    final uri = Uri.https(_host, '/graphql/$queryId/$operation', {
      'variables': jsonEncode(variables),
      'features': jsonEncode(config.features),
    });

    const baseHeaders = {
      'x-twitter-active-user': 'yes',
      'x-twitter-client-language': 'en',
      'Accept': '*/*',
      'User-Agent':
          'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36',
    };

    // A signed-in session authenticates with cookies and needs the CSRF
    // token echoed back; anonymous access uses a guest token instead.
    Future<http.Response> sendAsAccount() => httpClient.get(uri, headers: {
          ...baseHeaders,
          'Authorization': 'Bearer ${config.bearerToken}',
          'Cookie': account!.cookieHeader,
          'x-csrf-token': account!.csrfToken,
          'x-twitter-auth-type': 'OAuth2Session',
        });

    Future<http.Response> sendAsGuest(String guestToken) =>
        httpClient.get(uri, headers: {
          ...baseHeaders,
          'Authorization': 'Bearer ${config.bearerToken}',
          'x-guest-token': guestToken,
        });

    http.Response res;
    if (_authenticated) {
      res = await sendAsAccount();
      if (res.statusCode == 401 || res.statusCode == 403) {
        throw TwitterGuestException(
            'X rejected your sign-in (HTTP ${res.statusCode}). The session has '
            'probably expired — sign in again from Settings → Twitter (X) access.');
      }
    } else {
      res = await sendAsGuest(await session.token(httpClient, config));
      // An expired guest token reads as an auth failure; re-activate once.
      if (res.statusCode == 401 || res.statusCode == 403) {
        session.invalidate();
        res = await sendAsGuest(
            await session.token(httpClient, config, forceRefresh: true));
      }
    }

    if (res.statusCode == 404) {
      throw TwitterGuestException(
          'X did not recognize the $operation query ID. It has almost '
          'certainly been rotated — paste a current one into '
          'Settings → Twitter (X) access.');
    }
    if (res.statusCode == 400) {
      throw TwitterGuestException(
          'X rejected the request for $operation, usually a feature-flag '
          'mismatch. Update the feature flags in Settings → Twitter (X) access. '
          '(${_briefError(res.body)})');
    }
    if (res.statusCode == 429) {
      throw TwitterGuestException(
          'rate limited by X — anonymous access allows only a modest number '
          'of requests, so try again in a few minutes');
    }
    if (res.statusCode != 200) {
      throw TwitterGuestException('HTTP ${res.statusCode} from X');
    }

    final body = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    final errors = body['errors'] as List?;
    if (errors != null && errors.isNotEmpty && body['data'] == null) {
      final message =
          (errors.first as Map<String, dynamic>)['message'] as String?;
      throw TwitterGuestException(message ?? 'X returned an error');
    }
    return body;
  }

  static String _briefError(String body) {
    final message = RegExp(r'"message"\s*:\s*"([^"]{0,160})')
        .firstMatch(body)
        ?.group(1);
    return message ?? 'no detail';
  }

  /// Walks a nested JSON structure, returning null the moment a step is
  /// missing — X's payloads vary in shape between deploys.
  static dynamic _dig(dynamic node, List<String> path) {
    var current = node;
    for (final key in path) {
      if (current is! Map) return null;
      current = current[key];
      if (current == null) return null;
    }
    return current;
  }
}

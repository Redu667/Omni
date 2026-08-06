import 'network.dart';

/// User-configured source of posts (one Mastodon timeline, one subreddit, ...).
///
/// All settings live in [params]; keys depend on [network]:
///  - mastodon: instance, accessToken?, local? ("true"/"false")
///  - bluesky:  handle? (public author feed) OR identifier + appPassword (home)
///  - reddit:   subreddit (may be "a+b+c"), sort? (hot|new|top)
///  - twitter:  bearerToken, usernames (comma separated)
///  - rss:      url
class FeedSource {
  FeedSource({
    required this.id,
    required this.network,
    required this.displayName,
    required this.params,
    this.enabled = true,
  });

  final String id;
  final Network network;
  final String displayName;
  final Map<String, String> params;
  bool enabled;

  Map<String, dynamic> toJson() => {
        'id': id,
        'network': network.name,
        'displayName': displayName,
        'params': params,
        'enabled': enabled,
      };

  factory FeedSource.fromJson(Map<String, dynamic> json) => FeedSource(
        id: json['id'] as String,
        network: NetworkInfo.fromName(json['network'] as String),
        displayName: json['displayName'] as String,
        params: (json['params'] as Map).cast<String, String>(),
        enabled: json['enabled'] as bool? ?? true,
      );
}

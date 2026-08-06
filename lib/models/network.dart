import 'package:flutter/material.dart';

/// The social networks Omni can aggregate.
enum Network { mastodon, bluesky, reddit, twitter, rss }

extension NetworkInfo on Network {
  String get label => switch (this) {
        Network.mastodon => 'Mastodon',
        Network.bluesky => 'Bluesky',
        Network.reddit => 'Reddit',
        Network.twitter => 'Twitter / X',
        Network.rss => 'RSS',
      };

  Color get color => switch (this) {
        Network.mastodon => const Color(0xFF6364FF),
        Network.bluesky => const Color(0xFF1185FE),
        Network.reddit => const Color(0xFFFF4500),
        Network.twitter => const Color(0xFF14171A),
        Network.rss => const Color(0xFFF26522),
      };

  IconData get icon => switch (this) {
        Network.mastodon => Icons.forum_outlined,
        Network.bluesky => Icons.cloud_outlined,
        Network.reddit => Icons.reddit,
        Network.twitter => Icons.tag,
        Network.rss => Icons.rss_feed,
      };

  static Network fromName(String name) =>
      Network.values.firstWhere((n) => n.name == name);
}

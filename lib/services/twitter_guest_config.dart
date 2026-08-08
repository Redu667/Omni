import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// The volatile parts of talking to X's internal web API.
///
/// X rotates its GraphQL query IDs on every frontend deploy and periodically
/// changes which feature flags a request must carry. None of these values are
/// documented or stable, so they live here as *editable settings* rather than
/// baked-in constants — when a fetch starts failing, update them in
/// Settings → Twitter (X) access instead of waiting for an app release.
///
/// Current values can be lifted from an actively-maintained client such as
/// Squawker (github.com/j-fbriere/squawker) or Nitter
/// (github.com/zedeus/nitter) — look for their GraphQL endpoint definitions.
class TwitterGuestConfig {
  const TwitterGuestConfig({
    required this.bearerToken,
    required this.userByScreenNameQueryId,
    required this.userTweetsQueryId,
    required this.featuresJson,
    this.homeTimelineQueryId = defaultHomeTimelineQueryId,
  });

  /// The public bearer token X's own logged-out web client ships. It is the
  /// same for every anonymous visitor and has been stable for years, so it is
  /// the least likely of these values to need changing.
  static const defaultBearerToken =
      'AAAAAAAAAAAAAAAAAAAAANRILgAAAAAAnNwIzUejRCOuH5E6I8xnZz4puTs%3D1Zv7ttfk8LF81IUq16cHjhLTvJu4FA33AGWWjCpTnA';

  /// Last-known-good query IDs. These rotate frequently — treat a sudden
  /// "unknown query ID" error as a prompt to refresh them, not as a bug.
  static const defaultUserByScreenNameQueryId = 'G3KGOASz96M-Qu0nwmGXNg';
  static const defaultUserTweetsQueryId = 'V7H0Ap3_Hh2FyS75OCDO3Q';
  static const defaultHomeTimelineQueryId = 'HJFjzBgCs16TqxewQOeLNg';

  /// Feature flags the endpoints require. X rejects a request that omits a
  /// flag it expects, but tolerates extras, so this is a superset.
  static const defaultFeaturesJson = '''{
  "rweb_tipjar_consumption_enabled": true,
  "responsive_web_graphql_exclude_directive_enabled": true,
  "verified_phone_label_enabled": false,
  "creator_subscriptions_tweet_preview_api_enabled": true,
  "responsive_web_graphql_timeline_navigation_enabled": true,
  "responsive_web_graphql_skip_user_profile_image_extensions_enabled": false,
  "communities_web_enable_tweet_community_results_fetch": true,
  "c9s_tweet_anatomy_moderator_badge_enabled": true,
  "articles_preview_enabled": true,
  "tweetypie_unmention_optimization_enabled": true,
  "responsive_web_edit_tweet_api_enabled": true,
  "graphql_is_translatable_rweb_tweet_is_translatable_enabled": true,
  "view_counts_everywhere_api_enabled": true,
  "longform_notetweets_consumption_enabled": true,
  "responsive_web_twitter_article_tweet_consumption_enabled": true,
  "tweet_awards_web_tipping_enabled": false,
  "creator_subscriptions_quote_tweet_preview_enabled": false,
  "freedom_of_speech_not_reach_fetch_enabled": true,
  "standardized_nudges_misinfo": true,
  "tweet_with_visibility_results_prefer_gql_limited_actions_policy_enabled": true,
  "rweb_video_timestamps_enabled": true,
  "longform_notetweets_rich_text_read_enabled": true,
  "longform_notetweets_inline_media_enabled": true,
  "responsive_web_enhance_cards_enabled": false,
  "hidden_profile_likes_enabled": true,
  "hidden_profile_subscriptions_enabled": true,
  "subscriptions_verification_info_is_identity_verified_enabled": true,
  "subscriptions_verification_info_verified_since_enabled": true,
  "highlights_tweets_tab_ui_enabled": true,
  "responsive_web_twitter_article_notes_tab_enabled": true,
  "subscriptions_feature_can_gift_premium": true
}''';

  static const defaults = TwitterGuestConfig(
    bearerToken: defaultBearerToken,
    userByScreenNameQueryId: defaultUserByScreenNameQueryId,
    userTweetsQueryId: defaultUserTweetsQueryId,
    homeTimelineQueryId: defaultHomeTimelineQueryId,
    featuresJson: defaultFeaturesJson,
  );

  final String bearerToken;
  final String userByScreenNameQueryId;
  final String userTweetsQueryId;

  /// Only used by signed-in sources set to follow your home timeline.
  final String homeTimelineQueryId;

  final String featuresJson;

  /// The feature flags as a map, or an empty map when the stored JSON is
  /// malformed (so a bad edit degrades instead of crashing the feed).
  Map<String, dynamic> get features {
    try {
      return (jsonDecode(featuresJson) as Map).cast<String, dynamic>();
    } catch (_) {
      return const {};
    }
  }

  bool get featuresJsonIsValid {
    try {
      return jsonDecode(featuresJson) is Map;
    } catch (_) {
      return false;
    }
  }

  TwitterGuestConfig copyWith({
    String? bearerToken,
    String? userByScreenNameQueryId,
    String? userTweetsQueryId,
    String? homeTimelineQueryId,
    String? featuresJson,
  }) =>
      TwitterGuestConfig(
        bearerToken: bearerToken ?? this.bearerToken,
        userByScreenNameQueryId:
            userByScreenNameQueryId ?? this.userByScreenNameQueryId,
        userTweetsQueryId: userTweetsQueryId ?? this.userTweetsQueryId,
        homeTimelineQueryId: homeTimelineQueryId ?? this.homeTimelineQueryId,
        featuresJson: featuresJson ?? this.featuresJson,
      );

  Map<String, dynamic> toJson() => {
        'bearerToken': bearerToken,
        'userByScreenNameQueryId': userByScreenNameQueryId,
        'userTweetsQueryId': userTweetsQueryId,
        'homeTimelineQueryId': homeTimelineQueryId,
        'featuresJson': featuresJson,
      };

  factory TwitterGuestConfig.fromJson(Map<String, dynamic> json) =>
      TwitterGuestConfig(
        bearerToken: json['bearerToken'] as String? ?? defaultBearerToken,
        userByScreenNameQueryId: json['userByScreenNameQueryId'] as String? ??
            defaultUserByScreenNameQueryId,
        userTweetsQueryId:
            json['userTweetsQueryId'] as String? ?? defaultUserTweetsQueryId,
        homeTimelineQueryId: json['homeTimelineQueryId'] as String? ??
            defaultHomeTimelineQueryId,
        featuresJson: json['featuresJson'] as String? ?? defaultFeaturesJson,
      );
}

class TwitterGuestConfigStore {
  TwitterGuestConfigStore({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
            );

  static const _key = 'omni_twitter_guest_config_v1';
  final FlutterSecureStorage _storage;

  Future<TwitterGuestConfig> load() async {
    final raw = await _storage.read(key: _key);
    if (raw == null || raw.isEmpty) return TwitterGuestConfig.defaults;
    try {
      return TwitterGuestConfig.fromJson(
          (jsonDecode(raw) as Map).cast<String, dynamic>());
    } catch (_) {
      return TwitterGuestConfig.defaults;
    }
  }

  Future<void> save(TwitterGuestConfig config) =>
      _storage.write(key: _key, value: jsonEncode(config.toJson()));
}

import 'feed_item.dart';

/// Words and accounts the user doesn't want to see, applied across every
/// source as the timeline is built.
class FeedFilters {
  const FeedFilters({this.mutedWords = const [], this.mutedAccounts = const []});

  static const empty = FeedFilters();

  final List<String> mutedWords;

  /// Handles or display names, stored without any leading `@` or `u/` so a
  /// user can type them either way.
  final List<String> mutedAccounts;

  bool get isEmpty => mutedWords.isEmpty && mutedAccounts.isEmpty;

  /// Strips the decorations different networks put on handles so "u/spez",
  /// "@spez" and "spez" all match each other.
  static String normalizeAccount(String raw) => raw
      .trim()
      .toLowerCase()
      .replaceFirst(RegExp(r'^@'), '')
      .replaceFirst(RegExp(r'^u/'), '')
      .replaceFirst(RegExp(r'^/u/'), '');

  /// A single word matches on word boundaries, so muting "art" doesn't also
  /// hide "start". A multi-word phrase matches as a plain substring.
  static bool _mentions(String haystack, String term) {
    final needle = term.trim().toLowerCase();
    if (needle.isEmpty) return false;
    final text = haystack.toLowerCase();

    if (needle.contains(RegExp(r'\s'))) return text.contains(needle);

    return RegExp('(?<![a-z0-9])${RegExp.escape(needle)}(?![a-z0-9])')
        .hasMatch(text);
  }

  bool hides(FeedItem item) {
    for (final account in mutedAccounts) {
      final muted = normalizeAccount(account);
      if (muted.isEmpty) continue;
      if (normalizeAccount(item.author) == muted) return true;
      if (item.handle != null && normalizeAccount(item.handle!) == muted) {
        return true;
      }
    }

    if (mutedWords.isNotEmpty) {
      final haystack = [
        item.title ?? '',
        item.text,
        item.fullText ?? '',
      ].join(' \n ');
      for (final word in mutedWords) {
        if (_mentions(haystack, word)) return true;
      }
    }

    return false;
  }

  FeedFilters copyWith({List<String>? mutedWords, List<String>? mutedAccounts}) =>
      FeedFilters(
        mutedWords: mutedWords ?? this.mutedWords,
        mutedAccounts: mutedAccounts ?? this.mutedAccounts,
      );

  Map<String, dynamic> toJson() =>
      {'mutedWords': mutedWords, 'mutedAccounts': mutedAccounts};

  factory FeedFilters.fromJson(Map<String, dynamic> json) => FeedFilters(
        mutedWords:
            (json['mutedWords'] as List? ?? const []).cast<String>().toList(),
        mutedAccounts:
            (json['mutedAccounts'] as List? ?? const []).cast<String>().toList(),
      );
}

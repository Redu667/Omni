import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// One piece of a message: either literal text, or a custom emoji.
sealed class TextRun {
  const TextRun();
}

class TextChunk extends TextRun {
  const TextChunk(this.text);
  final String text;

  @override
  bool operator ==(Object other) =>
      other is TextChunk && other.text == text;

  @override
  int get hashCode => text.hashCode;

  @override
  String toString() => 'TextChunk("$text")';
}

class EmojiRun extends TextRun {
  const EmojiRun(this.shortcode, this.url);
  final String shortcode;
  final String url;

  @override
  bool operator ==(Object other) =>
      other is EmojiRun && other.shortcode == shortcode && other.url == url;

  @override
  int get hashCode => Object.hash(shortcode, url);

  @override
  String toString() => 'EmojiRun(:$shortcode:)';
}

final _shortcodePattern = RegExp(r':([a-zA-Z0-9_+-]+):');

/// Splits [text] into literal chunks and the custom emoji named in it.
///
/// Only shortcodes the post actually declares become emoji — everything
/// else, including ordinary uses of colons like `10:30` or a `:-)`, is left
/// exactly as written.
List<TextRun> splitEmoji(String text, Map<String, String> emojis) {
  if (text.isEmpty) return const [];
  if (emojis.isEmpty) return [TextChunk(text)];

  final runs = <TextRun>[];
  var cursor = 0;

  for (final match in _shortcodePattern.allMatches(text)) {
    final url = emojis[match.group(1)];
    if (url == null) continue;

    if (match.start > cursor) {
      runs.add(TextChunk(text.substring(cursor, match.start)));
    }
    runs.add(EmojiRun(match.group(1)!, url));
    cursor = match.end;
  }

  if (cursor < text.length) runs.add(TextChunk(text.substring(cursor)));
  return runs;
}

/// Text with custom emoji rendered inline.
///
/// Falls back to a plain [Text] when there's nothing to substitute, so the
/// overwhelmingly common case costs nothing extra.
class EmojiText extends StatelessWidget {
  const EmojiText(
    this.text, {
    super.key,
    this.emojis = const {},
    this.style,
    this.maxLines,
    this.overflow,
  });

  final String text;
  final Map<String, String> emojis;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow? overflow;

  @override
  Widget build(BuildContext context) {
    final runs = splitEmoji(text, emojis);
    if (!runs.any((r) => r is EmojiRun)) {
      return Text(text, style: style, maxLines: maxLines, overflow: overflow);
    }

    final resolved = style ?? DefaultTextStyle.of(context).style;
    // Sized to the line so emoji sit with the text rather than towering
    // over it or vanishing into it.
    final size = (resolved.fontSize ?? 14) * 1.2;

    return Text.rich(
      TextSpan(
        children: [
          for (final run in runs)
            switch (run) {
              TextChunk(:final text) => TextSpan(text: text),
              EmojiRun(:final shortcode, :final url) => WidgetSpan(
                  alignment: PlaceholderAlignment.middle,
                  child: Semantics(
                    label: ':$shortcode:',
                    child: CachedNetworkImage(
                      imageUrl: url,
                      width: size,
                      height: size,
                      fit: BoxFit.contain,
                      // An emoji that won't load falls back to the code it
                      // stands for, which at least still reads.
                      errorWidget: (_, _, _) =>
                          Text(':$shortcode:', style: resolved),
                    ),
                  ),
                ),
            },
        ],
      ),
      style: resolved,
      maxLines: maxLines,
      overflow: overflow ?? TextOverflow.clip,
    );
  }
}

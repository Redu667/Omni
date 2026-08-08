import 'package:html/dom.dart';
import 'package:html/parser.dart' as html;

/// Pulls the article out of a web page.
///
/// Many feeds publish a teaser and nothing else, which leaves Omni showing
/// two sentences and a link. This finds the body text the page is actually
/// about, so the article can be read in the app.
///
/// The approach is the well-worn one: score block elements by how much
/// prose they hold, discount them for being mostly links, and take the
/// winner plus whatever siblings look like part of the same article. It is
/// a heuristic and it will occasionally be wrong, which is why the original
/// page stays one tap away.

/// Elements that are never article text, whatever they score.
const _junkTags = {
  'script',
  'style',
  'noscript',
  'nav',
  'header',
  'footer',
  'aside',
  'form',
  'button',
  'iframe',
  'svg',
  'template',
};

/// Class and id fragments that mark furniture rather than content. Matched
/// case-insensitively against both attributes.
final _junkPattern = RegExp(
  r'(^|[-_\s])(comment|share|social|related|recommend|promo|advert|ad|ads|'
  r'sidebar|nav|menu|footer|header|breadcrumb|newsletter|subscribe|paywall|'
  r'popup|modal|cookie|banner|byline|meta|tags|author-bio)([-_\s]|$)',
  caseSensitive: false,
);

/// Tags whose contents read as prose, used to score a candidate.
const _proseTags = {'p', 'pre', 'blockquote', 'li'};

/// A candidate has to clear this to be considered at all, so a page of
/// navigation doesn't produce a confident wrong answer.
const _minimumArticleLength = 250;

/// The extracted article, or null when the page didn't have one worth
/// showing — a paywall, a login wall, a page that is genuinely just links.
String? extractArticleText(String pageHtml) {
  final Document document;
  try {
    document = html.parse(pageHtml);
  } catch (_) {
    return null;
  }

  final body = document.body;
  if (body == null) return null;

  _strip(body);

  final scores = <Element, double>{};
  for (final element in body.querySelectorAll('p, pre, blockquote, li, td')) {
    final text = _textOf(element);
    if (text.length < 25) continue;

    // A paragraph's score accrues to its container: the article is the
    // thing holding the paragraphs, not any one of them.
    var score = 1 + text.split(',').length + (text.length / 100).clamp(0, 3);
    if (_proseTags.contains(element.localName)) score += 3;

    var parent = element.parent;
    var depth = 0;
    while (parent != null && depth < 3) {
      // Each level up gets a smaller share, so the tightest wrapper wins
      // over <body>.
      scores[parent] = (scores[parent] ?? 0) + score / (depth + 1);
      parent = parent.parent;
      depth++;
    }
  }

  Element? best;
  var bestScore = 0.0;
  for (final entry in scores.entries) {
    // Mostly-links means a navigation block dressed as content.
    final adjusted = entry.value * (1 - _linkDensity(entry.key));
    if (adjusted > bestScore) {
      bestScore = adjusted;
      best = entry.key;
    }
  }
  if (best == null) return null;

  // Siblings scoring near the winner are usually the rest of the same
  // article, split across wrappers by the page's layout.
  final threshold = bestScore * 0.2;
  final parts = <String>[];
  for (final sibling in best.parent?.children ?? [best]) {
    final isWinner = identical(sibling, best);
    final score = scores[sibling] ?? 0;
    if (!isWinner && score < threshold) continue;
    if (!isWinner && _linkDensity(sibling) > 0.4) continue;

    final text = _blockText(sibling);
    if (text.isNotEmpty) parts.add(text);
  }

  final article = parts.join('\n\n').trim();
  return article.length < _minimumArticleLength ? null : article;
}

/// Removes the parts of a page that are never the article.
void _strip(Element root) {
  for (final element in root.querySelectorAll('*').toList()) {
    if (_junkTags.contains(element.localName)) {
      element.remove();
      continue;
    }
    if (element.attributes['aria-hidden'] == 'true' ||
        element.attributes['hidden'] != null ||
        element.localName == 'figcaption') {
      element.remove();
      continue;
    }
    final marker =
        '${element.className} ${element.id} ${element.attributes['role'] ?? ''}';
    if (marker.trim().isNotEmpty && _junkPattern.hasMatch(marker)) {
      element.remove();
    }
  }
}

/// The share of an element's text that sits inside links. Navigation and
/// "related articles" blocks run high; prose runs near zero.
double _linkDensity(Element element) {
  final total = _textOf(element).length;
  if (total == 0) return 1;
  final linked = element
      .querySelectorAll('a')
      .fold<int>(0, (sum, a) => sum + _textOf(a).length);
  return (linked / total).clamp(0, 1);
}

String _textOf(Element element) =>
    element.text.replaceAll(RegExp(r'\s+'), ' ').trim();

/// Renders a subtree as paragraphs, so the result reads like an article
/// rather than one unbroken wall of text.
String _blockText(Element element) {
  final blocks = element.querySelectorAll('p, pre, blockquote, li, h1, h2, h3, h4');
  if (blocks.isEmpty) return _textOf(element);

  final lines = <String>[];
  for (final block in blocks) {
    final text = _textOf(block);
    if (text.isEmpty) continue;
    // A list item reads as a list item.
    lines.add(block.localName == 'li' ? '• $text' : text);
  }
  return lines.join('\n\n');
}

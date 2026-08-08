import '../models/feed_item.dart';

/// A reply as the thread view shows it, with whatever it's folding away.
typedef FoldedReply = ({ThreadEntry entry, int hidden});

/// Applies collapsed comments to a flattened thread.
///
/// Folding is by depth rather than by parent id: a flattened thread carries
/// no parent links, so everything deeper than a collapsed comment — until
/// the depth comes back up to its level — is what belongs to it.
List<FoldedReply> foldThread(
  List<ThreadEntry> replies,
  Set<String> collapsedIds,
) {
  if (collapsedIds.isEmpty) {
    return [for (final e in replies) (entry: e, hidden: 0)];
  }

  final out = <FoldedReply>[];
  int? foldedAt;
  var hiddenSoFar = 0;

  void closeFold() {
    if (foldedAt == null) return;
    out[out.length - 1] = (entry: out.last.entry, hidden: hiddenSoFar);
    foldedAt = null;
    hiddenSoFar = 0;
  }

  for (final entry in replies) {
    if (foldedAt != null && entry.depth > foldedAt!) {
      hiddenSoFar++;
      continue;
    }
    closeFold();
    out.add((entry: entry, hidden: 0));
    if (collapsedIds.contains(entry.item.id)) foldedAt = entry.depth;
  }
  closeFold();
  return out;
}

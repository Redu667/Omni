/// A user-made grouping of sources that cuts across networks.
///
/// The per-network chips answer "show me Mastodon"; a collection answers
/// "show me everything about this subject", which is usually the question
/// worth asking when you follow one topic on four different services.
class Collection {
  const Collection({
    required this.id,
    required this.name,
    this.sourceIds = const {},
  });

  final String id;
  final String name;

  /// Sources belong to any number of collections, so this is a plain set
  /// of ids rather than an ownership relation.
  final Set<String> sourceIds;

  bool contains(String sourceId) => sourceIds.contains(sourceId);

  Collection copyWith({String? name, Set<String>? sourceIds}) => Collection(
        id: id,
        name: name ?? this.name,
        sourceIds: sourceIds ?? this.sourceIds,
      );

  Collection withSource(String sourceId, bool member) => copyWith(
        sourceIds: member
            ? {...sourceIds, sourceId}
            : sourceIds.where((id) => id != sourceId).toSet(),
      );

  Map<String, dynamic> toJson() =>
      {'id': id, 'name': name, 'sourceIds': sourceIds.toList()};

  factory Collection.fromJson(Map<String, dynamic> json) => Collection(
        id: json['id'] as String,
        name: json['name'] as String? ?? 'Untitled',
        sourceIds:
            (json['sourceIds'] as List? ?? const []).cast<String>().toSet(),
      );
}

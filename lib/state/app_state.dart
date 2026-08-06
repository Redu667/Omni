import 'package:flutter/foundation.dart';

import '../models/feed_item.dart';
import '../models/feed_source.dart';
import '../models/network.dart';
import '../services/feed_repository.dart';
import '../services/source_store.dart';

class AppState extends ChangeNotifier {
  AppState({FeedRepository? repository, SourceStore? store})
      : _repository = repository ?? FeedRepository(),
        _store = store ?? SourceStore();

  final FeedRepository _repository;
  final SourceStore _store;

  List<FeedSource> _sources = [];
  List<FeedItem> _items = [];
  List<String> _errors = [];
  bool _loading = false;
  bool _initialized = false;

  /// null = show everything; otherwise only this network.
  Network? _filter;

  List<FeedSource> get sources => List.unmodifiable(_sources);
  List<String> get errors => List.unmodifiable(_errors);
  bool get loading => _loading;
  bool get initialized => _initialized;
  Network? get filter => _filter;

  List<FeedItem> get items => _filter == null
      ? List.unmodifiable(_items)
      : List.unmodifiable(_items.where((i) => i.network == _filter));

  /// Networks that currently have at least one configured source.
  Set<Network> get activeNetworks => _sources.map((s) => s.network).toSet();

  Future<void> init() async {
    _sources = await _store.load();
    _initialized = true;
    notifyListeners();
    if (_sources.isNotEmpty) await refresh();
  }

  Future<void> refresh() async {
    if (_loading) return;
    _loading = true;
    _errors = [];
    notifyListeners();

    final result = await _repository.fetchAll(_sources);
    _items = result.items;
    _errors = result.errors;
    _loading = false;
    notifyListeners();
  }

  Future<void> addSource(FeedSource source) async {
    _sources = [..._sources, source];
    await _store.save(_sources);
    notifyListeners();
    await refresh();
  }

  Future<void> removeSource(String id) async {
    _sources = _sources.where((s) => s.id != id).toList();
    _items = _items.where((i) => i.sourceId != id).toList();
    if (_filter != null && !activeNetworks.contains(_filter)) _filter = null;
    await _store.save(_sources);
    notifyListeners();
  }

  Future<void> toggleSource(String id, bool enabled) async {
    final source = _sources.firstWhere((s) => s.id == id);
    source.enabled = enabled;
    await _store.save(_sources);
    notifyListeners();
    await refresh();
  }

  void setFilter(Network? network) {
    _filter = network;
    notifyListeners();
  }

  @override
  void dispose() {
    _repository.dispose();
    super.dispose();
  }
}

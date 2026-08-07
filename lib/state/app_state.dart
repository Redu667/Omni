import 'package:flutter/foundation.dart';

import '../models/feed_item.dart';
import '../models/feed_source.dart';
import '../models/network.dart';
import '../services/feed_repository.dart';
import '../services/source_store.dart';
import '../services/settings_store.dart';
import '../services/source_validator.dart';
import '../services/twitter_guest_config.dart';
import '../services/twitter_session_store.dart';

class AppState extends ChangeNotifier {
  AppState({
    FeedRepository? repository,
    SourceStore? store,
    SourceValidator? validator,
    TwitterGuestConfigStore? twitterConfigStore,
    SettingsStore? settingsStore,
    TwitterSessionStore? twitterSessionStore,
  })  : _repository = repository ?? FeedRepository(),
        _store = store ?? SourceStore(),
        _validator = validator ?? SourceValidator(),
        _twitterConfigStore = twitterConfigStore ?? TwitterGuestConfigStore(),
        _settingsStore = settingsStore ?? SettingsStore(),
        _twitterSessionStore = twitterSessionStore ?? TwitterSessionStore();

  final FeedRepository _repository;
  final SourceStore _store;
  final SourceValidator _validator;
  final TwitterGuestConfigStore _twitterConfigStore;
  final SettingsStore _settingsStore;
  final TwitterSessionStore _twitterSessionStore;

  TwitterSession? _twitterAccount;

  /// The signed-in x.com account, if any. Anonymous access gets a stale
  /// timeline from X, so this is what makes Twitter sources useful.
  TwitterSession? get twitterAccount => _twitterAccount;

  Future<void> signInToTwitter(TwitterSession session) async {
    _twitterAccount = session;
    await _twitterSessionStore.save(session);
    notifyListeners();
    if (_sources.any((s) => s.network == Network.twitter && s.enabled)) {
      await refresh();
    }
  }

  Future<void> signOutOfTwitter() async {
    _twitterAccount = null;
    await _twitterSessionStore.clear();
    notifyListeners();
  }

  bool _openInApp = true;

  /// Whether tapping a post opens Omni's built-in viewer or the browser.
  bool get openInApp => _openInApp;

  Future<void> setOpenInApp(bool value) async {
    _openInApp = value;
    await _settingsStore.saveOpenInApp(value);
    notifyListeners();
  }

  TwitterGuestConfig _twitterConfig = TwitterGuestConfig.defaults;
  TwitterGuestConfig get twitterConfig => _twitterConfig;

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
    _twitterConfig = await _twitterConfigStore.load();
    _openInApp = await _settingsStore.loadOpenInApp();
    _twitterAccount = await _twitterSessionStore.load();
    _initialized = true;
    notifyListeners();
    if (_sources.isNotEmpty) await refresh();
  }

  Future<List<ThreadEntry>> fetchThread(FeedItem item) =>
      _repository.fetchThread(item, _sources,
          twitterConfig: _twitterConfig, twitterAccount: _twitterAccount);

  Future<void> updateTwitterConfig(TwitterGuestConfig config) async {
    _twitterConfig = config;
    await _twitterConfigStore.save(config);
    notifyListeners();
    if (_sources.any((s) => s.network == Network.twitter && s.enabled)) {
      await refresh();
    }
  }

  Future<void> refresh() async {
    if (_loading) return;
    _loading = true;
    _errors = [];
    notifyListeners();

    final result = await _repository.fetchAll(_sources,
        twitterConfig: _twitterConfig, twitterAccount: _twitterAccount);
    _items = result.items;
    _errors = result.errors;
    _loading = false;
    notifyListeners();
  }

  /// Test-fetches the source first; throws [SourceFetchException] with a
  /// readable message if it's misconfigured. May return a fixed-up source
  /// (e.g. RSS URL swapped for the feed a web page advertises).
  Future<void> validateAndAddSource(FeedSource source) async {
    final validated =
        await _validator.validate(source,
            twitterConfig: _twitterConfig, twitterAccount: _twitterAccount);
    await addSources([validated]);
  }

  Future<void> addSources(List<FeedSource> sources) async {
    _sources = [..._sources, ...sources];
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
    _validator.dispose();
    super.dispose();
  }
}

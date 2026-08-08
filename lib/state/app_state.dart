import 'package:flutter/material.dart';

import '../models/feed_item.dart';
import '../models/feed_filters.dart';
import '../models/feed_source.dart';
import '../models/network.dart';
import '../services/feed_repository.dart';
import '../services/saved_store.dart';
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
    SavedStore? savedStore,
  })  : _repository = repository ?? FeedRepository(),
        _store = store ?? SourceStore(),
        _validator = validator ?? SourceValidator(),
        _twitterConfigStore = twitterConfigStore ?? TwitterGuestConfigStore(),
        _settingsStore = settingsStore ?? SettingsStore(),
        _twitterSessionStore = twitterSessionStore ?? TwitterSessionStore(),
        _savedStore = savedStore ?? SavedStore();

  final FeedRepository _repository;
  final SourceStore _store;
  final SourceValidator _validator;
  final TwitterGuestConfigStore _twitterConfigStore;
  final SettingsStore _settingsStore;
  final TwitterSessionStore _twitterSessionStore;
  final SavedStore _savedStore;

  List<FeedItem> _saved = [];

  /// Posts the user kept, newest save first.
  List<FeedItem> get saved => List.unmodifiable(_saved);

  bool isSaved(FeedItem item) => _saved.any((s) => s.id == item.id);

  /// Returns true if the post ended up saved, so callers can word their
  /// confirmation without re-querying.
  Future<bool> toggleSaved(FeedItem item) async {
    final wasSaved = isSaved(item);
    _saved = wasSaved
        ? _saved.where((s) => s.id != item.id).toList()
        : [item, ..._saved];
    await _savedStore.save(_saved);
    notifyListeners();
    return !wasSaved;
  }

  Future<void> clearSaved() async {
    _saved = [];
    await _savedStore.save(_saved);
    notifyListeners();
  }

  Future<List<FeedItem>> fetchAuthorPosts(FeedItem item) =>
      _repository.fetchAuthorPosts(item, _sources,
          twitterConfig: _twitterConfig, twitterAccount: _twitterAccount);

  bool supportsAuthorFeed(FeedItem item) => _repository
      .supportsAuthorFeed(item, _sources, twitterConfig: _twitterConfig);

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

  FeedFilters _filters = FeedFilters.empty;

  /// Words and accounts hidden from the timeline.
  FeedFilters get filters => _filters;

  /// How many fetched posts the filters are currently hiding, so the UI can
  /// say so rather than leaving the user wondering where posts went.
  int get hiddenCount {
    if (_filters.isEmpty) return 0;
    final visible = _filter == null
        ? _items
        : _items.where((i) => i.network == _filter);
    return visible.where(_filters.hides).length;
  }

  Future<void> updateFilters(FeedFilters filters) async {
    _filters = filters;
    await _settingsStore.saveFilters(filters);
    notifyListeners();
  }

  Future<void> muteWord(String word) async {
    final trimmed = word.trim();
    if (trimmed.isEmpty ||
        _filters.mutedWords.any((w) => w.toLowerCase() == trimmed.toLowerCase())) {
      return;
    }
    await updateFilters(
        _filters.copyWith(mutedWords: [..._filters.mutedWords, trimmed]));
  }

  Future<void> unmuteWord(String word) async => updateFilters(_filters.copyWith(
      mutedWords: _filters.mutedWords.where((w) => w != word).toList()));

  Future<void> muteAccount(String account) async {
    final trimmed = account.trim();
    if (trimmed.isEmpty) return;
    final normalized = FeedFilters.normalizeAccount(trimmed);
    if (normalized.isEmpty ||
        _filters.mutedAccounts
            .any((a) => FeedFilters.normalizeAccount(a) == normalized)) {
      return;
    }
    await updateFilters(_filters
        .copyWith(mutedAccounts: [..._filters.mutedAccounts, trimmed]));
  }

  Future<void> unmuteAccount(String account) async =>
      updateFilters(_filters.copyWith(
          mutedAccounts:
              _filters.mutedAccounts.where((a) => a != account).toList()));

  bool _useDynamicColour = true;

  /// Whether to take colours from the system wallpaper (Material You) when
  /// the platform offers them. On by default; falls back to Omni's own
  /// palette where unsupported.
  bool get useDynamicColour => _useDynamicColour;

  Future<void> setUseDynamicColour(bool value) async {
    _useDynamicColour = value;
    await _settingsStore.saveDynamicColour(value);
    notifyListeners();
  }

  ThemeMode _themeMode = ThemeMode.system;

  ThemeMode get themeMode => _themeMode;

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    await _settingsStore.saveThemeMode(mode);
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
  bool _loadingMore = false;
  bool _initialized = false;

  /// Where each source got to. Empty once everything has run out.
  Map<String, String> _cursors = {};

  /// null = show everything; otherwise only this network.
  Network? _filter;

  List<FeedSource> get sources => List.unmodifiable(_sources);
  List<String> get errors => List.unmodifiable(_errors);
  bool get loading => _loading;
  bool get loadingMore => _loadingMore;
  bool get initialized => _initialized;

  /// Whether any source still has older posts to offer.
  bool get hasMore => _cursors.isNotEmpty;
  Network? get filter => _filter;

  List<FeedItem> get items => List.unmodifiable(_items.where((i) =>
      (_filter == null || i.network == _filter) && !_filters.hides(i)));

  /// Networks that currently have at least one configured source.
  Set<Network> get activeNetworks => _sources.map((s) => s.network).toSet();

  Future<void> init() async {
    _sources = await _store.load();
    _twitterConfig = await _twitterConfigStore.load();
    _openInApp = await _settingsStore.loadOpenInApp();
    _filters = await _settingsStore.loadFilters();
    _themeMode = await _settingsStore.loadThemeMode();
    _useDynamicColour = await _settingsStore.loadDynamicColour();
    _twitterAccount = await _twitterSessionStore.load();
    _saved = await _savedStore.load();
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
    _cursors = result.cursors;
    _loading = false;
    notifyListeners();
  }

  /// Appends the next page from every source that still has one.
  Future<void> loadMore() async {
    if (_loading || _loadingMore || _cursors.isEmpty) return;
    _loadingMore = true;
    notifyListeners();

    final result = await _repository.fetchAll(
      _sources,
      twitterConfig: _twitterConfig,
      twitterAccount: _twitterAccount,
      cursors: _cursors,
    );

    // Merge rather than replace, and re-sort so a slow source's older posts
    // still land in the right place.
    final seen = _items.map((i) => i.id).toSet();
    _items = [..._items, ...result.items.where((i) => seen.add(i.id))]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    _cursors = result.cursors;
    // Paging errors are transient and the feed still shows; don't replace
    // the banner contents wholesale over them.
    if (result.errors.isNotEmpty) _errors = result.errors;
    _loadingMore = false;
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

  /// Replaces a source's settings in place, keeping its id so its posts
  /// aren't orphaned. Used for things like changing a subreddit's sort.
  Future<void> updateSource(
      String id, Map<String, String> params, String displayName) async {
    final index = _sources.indexWhere((s) => s.id == id);
    if (index < 0) return;

    final existing = _sources[index];
    _sources = [..._sources]..[index] = FeedSource(
        id: existing.id,
        network: existing.network,
        displayName: displayName,
        params: params,
        enabled: existing.enabled,
      );
    await _store.save(_sources);
    notifyListeners();
    await refresh();
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

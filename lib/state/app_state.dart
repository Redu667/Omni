import 'package:flutter/material.dart';

import '../models/feed_item.dart';
import '../models/collection.dart';
import '../models/feed_filters.dart';
import '../models/feed_source.dart';
import '../models/network.dart';
import '../services/feed_cache.dart';
import '../services/article_fetcher.dart';
import '../services/feed_repository.dart';
import '../services/reddit_auth.dart';
import '../services/saved_store.dart';
import '../services/source_health.dart';
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
    FeedCache? cache,
    RedditCredentialStore? redditCredentials,
    RedditAuth? redditAuth,
    ArticleFetcher? articleFetcher,
  })  : _articles = articleFetcher ?? ArticleFetcher(),
        _repository = repository ??
            FeedRepository(redditAuth: redditAuth ?? RedditAuth()),
        _store = store ?? SourceStore(),
        _validator = validator ??
            SourceValidator(redditAuth: redditAuth ?? RedditAuth()),
        _twitterConfigStore = twitterConfigStore ?? TwitterGuestConfigStore(),
        _settingsStore = settingsStore ?? SettingsStore(),
        _twitterSessionStore = twitterSessionStore ?? TwitterSessionStore(),
        _savedStore = savedStore ?? SavedStore(),
        _cache = cache ?? FeedCache(),
        _redditCredentials = redditCredentials ?? RedditCredentialStore();

  final FeedRepository _repository;
  final SourceStore _store;
  final SourceValidator _validator;
  final TwitterGuestConfigStore _twitterConfigStore;
  final SettingsStore _settingsStore;
  final TwitterSessionStore _twitterSessionStore;
  final SavedStore _savedStore;
  final FeedCache _cache;
  final RedditCredentialStore _redditCredentials;
  final ArticleFetcher _articles;

  /// Fetches and extracts the article a truncated feed only linked to.
  Future<String> fetchArticle(String url) => _articles.fetch(url);

  String? _redditClientId;

  /// The Reddit app ID, if the user has supplied one. Without it, Reddit
  /// sources fall back to anonymous requests and the blocking they attract.
  String? get redditClientId => _redditClientId;

  Future<void> setRedditClientId(String? id) async {
    final trimmed = id?.trim();
    _redditClientId = (trimmed?.isEmpty ?? true) ? null : trimmed;
    await _redditCredentials.saveClientId(_redditClientId);
    notifyListeners();
    if (_sources.any((s) => s.network == Network.reddit && s.enabled)) {
      await refresh();
    }
  }

  Set<String> _readIds = {};
  bool _hideRead = false;
  bool _markReadOnScroll = false;

  /// Marked read by scrolling since the last refresh.
  ///
  /// Held apart from the hide-read filter on purpose: pulling posts out of
  /// the list as they pass the top of the screen moves everything under the
  /// reader's thumb. They dim immediately and disappear on the next refresh.
  final Set<String> _readWhileScrolling = {};

  bool isRead(FeedItem item) => _readIds.contains(item.id);

  /// Whether read posts are hidden outright rather than just dimmed.
  bool get hideRead => _hideRead;

  /// Whether scrolling a post off the top of the screen marks it read.
  bool get markReadOnScroll => _markReadOnScroll;

  int get unreadCount =>
      _visibleItems.where((i) => !_readIds.contains(i.id)).length;

  Future<void> setHideRead(bool value) async {
    _hideRead = value;
    await _settingsStore.saveHideRead(value);
    notifyListeners();
  }

  Future<void> setMarkReadOnScroll(bool value) async {
    _markReadOnScroll = value;
    await _settingsStore.saveMarkReadOnScroll(value);
    notifyListeners();
  }

  Future<void> markRead(FeedItem item) async {
    if (!_readIds.add(item.id)) return;
    await _settingsStore.saveReadIds(_readIds);
    notifyListeners();
  }

  /// Marks everything scrolled past, in one go — the scroll listener fires
  /// far more often than the list actually advances.
  Future<void> markScrolledRead(Iterable<String> ids) async {
    final fresh = ids.where(_readIds.add).toList();
    if (fresh.isEmpty) return;
    _readWhileScrolling.addAll(fresh);
    await _settingsStore.saveReadIds(_readIds);
    notifyListeners();
  }

  Future<void> markAllRead() async {
    _readIds = {..._readIds, ..._items.map((i) => i.id)};
    await _settingsStore.saveReadIds(_readIds);
    notifyListeners();
  }

  /// True when the timeline on screen came from disk rather than the
  /// network, so the UI can say so rather than implying it is current.
  bool _fromCache = false;
  bool get showingCached => _fromCache;

  /// The last refresh couldn't reach anything at all. Distinguished from
  /// per-source errors because "no connection" is one fact, not five.
  bool _offline = false;
  bool get offline => _offline;

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

  Set<String> _staleSourceIds = {};

  /// Sources currently showing their last-known posts because a refresh
  /// failed. Their content is still in the timeline.
  Set<String> get staleSourceIds => Set.unmodifiable(_staleSourceIds);

  SourceHealth healthOf(String sourceId) => _repository.healthOf(sourceId);

  /// Names of sources that are failing but still contributing posts, for a
  /// message that says what's actually happening.
  List<String> get staleSourceNames => [
        for (final s in _sources)
          if (_staleSourceIds.contains(s.id)) s.displayName,
      ];

  /// null = show everything; otherwise only this network.
  Network? _filter;

  /// Set when viewing a collection, which supersedes the network filter.
  String? _collectionId;

  List<Collection> _collections = [];

  List<Collection> get collections => List.unmodifiable(_collections);

  /// The collection currently being viewed, if any.
  Collection? get activeCollection => _collectionId == null
      ? null
      : _collections.where((c) => c.id == _collectionId).firstOrNull;

  /// What the app bar should call the current view.
  String get viewTitle =>
      activeCollection?.name ?? _filter?.label ?? 'Omni';

  void showCollection(String? id) {
    _collectionId = id;
    if (id != null) _filter = null;
    notifyListeners();
  }

  Future<void> addCollection(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    _collections = [
      ..._collections,
      Collection(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        name: trimmed,
      ),
    ];
    await _settingsStore.saveCollections(_collections);
    notifyListeners();
  }

  Future<void> renameCollection(String id, String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    _collections = [
      for (final c in _collections) c.id == id ? c.copyWith(name: trimmed) : c,
    ];
    await _settingsStore.saveCollections(_collections);
    notifyListeners();
  }

  Future<void> removeCollection(String id) async {
    _collections = _collections.where((c) => c.id != id).toList();
    if (_collectionId == id) _collectionId = null;
    await _settingsStore.saveCollections(_collections);
    notifyListeners();
  }

  Future<void> setCollectionMembership(
      String collectionId, String sourceId, bool member) async {
    _collections = [
      for (final c in _collections)
        c.id == collectionId ? c.withSource(sourceId, member) : c,
    ];
    await _settingsStore.saveCollections(_collections);
    notifyListeners();
  }

  /// Collections a given source belongs to, for the sources list.
  List<Collection> collectionsFor(String sourceId) =>
      [for (final c in _collections) if (c.contains(sourceId)) c];

  List<FeedSource> get sources => List.unmodifiable(_sources);
  List<String> get errors => List.unmodifiable(_errors);
  bool get loading => _loading;
  bool get loadingMore => _loadingMore;
  bool get initialized => _initialized;

  /// Whether any source still has older posts to offer.
  bool get hasMore => _cursors.isNotEmpty;
  Network? get filter => _filter;

  /// Everything that passes the network chip and mute filters, before
  /// read-hiding — so the unread count doesn't change as posts are hidden.
  Iterable<FeedItem> get _visibleItems {
    final collection = activeCollection;
    return _items.where((i) =>
        (collection == null || collection.contains(i.sourceId)) &&
        (_filter == null || i.network == _filter) &&
        !_filters.hides(i));
  }

  List<FeedItem> get items => List.unmodifiable(_hideRead
      ? _visibleItems.where((i) =>
          !_readIds.contains(i.id) || _readWhileScrolling.contains(i.id))
      : _visibleItems);

  /// Every post loaded, ignoring the collection, network chip and mute
  /// filters. Search uses this: when you're hunting for a specific post you
  /// don't want the answer withheld because a chip is set somewhere else.
  List<FeedItem> get allItems => List.unmodifiable(_items);

  /// Networks that currently have at least one configured source.
  Set<Network> get activeNetworks => _sources.map((s) => s.network).toSet();

  Future<void> init() async {
    _sources = await _store.load();
    _readIds = await _settingsStore.loadReadIds();
    _hideRead = await _settingsStore.loadHideRead();
    _markReadOnScroll = await _settingsStore.loadMarkReadOnScroll();
    _collections = await _settingsStore.loadCollections();

    // Show the cached timeline immediately; the network refresh follows.
    final cached = await _cache.load();
    if (cached.isNotEmpty) {
      _items = cached;
      _fromCache = true;
    }
    _twitterConfig = await _twitterConfigStore.load();
    _openInApp = await _settingsStore.loadOpenInApp();
    _filters = await _settingsStore.loadFilters();
    _themeMode = await _settingsStore.loadThemeMode();
    _useDynamicColour = await _settingsStore.loadDynamicColour();
    _twitterAccount = await _twitterSessionStore.load();
    _saved = await _savedStore.load();
    _redditClientId = await _redditCredentials.loadClientId();
    _initialized = true;
    notifyListeners();
    if (_sources.isNotEmpty) await refresh();
  }

  Future<PostThread> fetchThread(FeedItem item, {String? sort}) =>
      _repository.fetchThread(item, _sources,
          twitterConfig: _twitterConfig,
          twitterAccount: _twitterAccount,
          sort: sort);

  Future<List<ThreadEntry>> fetchMoreReplies(FeedItem item, MoreReplies more,
          {String? sort}) =>
      _repository.fetchMoreReplies(item, more, _sources,
          twitterConfig: _twitterConfig,
          twitterAccount: _twitterAccount,
          sort: sort);

  /// Asks the networks themselves, rather than the posts already loaded.
  Future<List<FeedItem>> searchNetworks(String query) =>
      _repository.search(query, _sources,
          twitterConfig: _twitterConfig, twitterAccount: _twitterAccount);

  bool get canSearchNetworks =>
      _repository.canSearch(_sources, twitterConfig: _twitterConfig);

  Map<String, String> commentSorts(FeedItem item) =>
      _repository.commentSorts(item, _sources, twitterConfig: _twitterConfig);

  Future<void> updateTwitterConfig(TwitterGuestConfig config) async {
    _twitterConfig = config;
    await _twitterConfigStore.save(config);
    notifyListeners();
    if (_sources.any((s) => s.network == Network.twitter && s.enabled)) {
      await refresh();
    }
  }

  /// [force] bypasses the per-source retry backoff, because someone
  /// watching the screen and pulling to refresh is asking for a real
  /// attempt rather than a policy.
  Future<void> refresh({bool force = false}) async {
    if (_loading) return;
    _loading = true;
    _errors = [];
    notifyListeners();

    final result = await _repository.fetchAll(_sources,
        twitterConfig: _twitterConfig,
        twitterAccount: _twitterAccount,
        force: force);

    // A refresh that failed everywhere shouldn't wipe a usable cache —
    // including when the failure was having no connection, which produces
    // no per-source errors to check for.
    _offline = result.offline;
    if (result.items.isEmpty &&
        (result.errors.isNotEmpty || result.offline) &&
        _items.isNotEmpty) {
      _errors = result.errors;
      _loading = false;
      notifyListeners();
      return;
    }

    _items = result.items;
    _errors = result.errors;
    _cursors = result.cursors;
    _staleSourceIds = result.staleSourceIds;
    _fromCache = false;
    // Posts held back from the hide-read filter while they were on screen
    // can go now: the reader has left the list.
    _readWhileScrolling.clear();
    _loading = false;
    notifyListeners();
    await _cache.save(_items);
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
    await _cache.save(_items);
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
    // A removed source shouldn't linger as a phantom member.
    _collections = [
      for (final c in _collections) c.withSource(id, false),
    ];
    await _settingsStore.saveCollections(_collections);
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
    if (network != null) _collectionId = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _repository.dispose();
    _validator.dispose();
    super.dispose();
  }
}

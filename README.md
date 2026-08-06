# Omni

One timeline for all your feeds. Omni is a Flutter app for Android that merges
**Mastodon**, **Bluesky**, **Reddit**, **Twitter/X** and **RSS/Atom** into a
single reverse-chronological feed — in the spirit of focused clients like
Moshidon, but spanning multiple networks.

## Features

- **Unified timeline** — posts from every configured source, merged and sorted
  by time, with pull-to-refresh.
- **Easy setup** — in-app Mastodon sign-in (OAuth, no token pasting), a
  quick-start screen with curated no-account sources, and every source is
  test-fetched when you add it so mistakes fail immediately with a clear
  message.
- **RSS auto-discovery & OPML import** — paste any website URL and Omni finds
  its feed; bring your subscriptions from another reader via OPML.
- **Per-network filtering** — chips to show only Mastodon, only Reddit, etc.
- **Multiple sources per network** — several subreddits, several feeds,
  several accounts; toggle each on/off or remove it.
- **Graceful partial failure** — if one source is down you still get the rest,
  with an inline warning.
- **Material 3** with dynamic light/dark themes.
- **Encrypted credential storage** — tokens and app passwords are kept in
  Android's encrypted storage via `flutter_secure_storage`.

## Supported sources

| Network | What you can add | Auth |
|---|---|---|
| Mastodon | Home timeline, or any instance's public/local timeline | In-app OAuth sign-in (or none for public timelines) |
| Bluesky | Your home timeline, or any user's public feed | Optional app password (Settings → App Passwords) |
| Reddit | Any subreddit (`flutter` or `flutter+androiddev`) | None |
| Twitter/X | Public posts from chosen usernames | **Anonymous** (default, no account) or the official API v2 with your own bearer token |
| RSS / Atom | Any feed URL | None |

### Twitter/X without an API plan

X removed free API read access in 2023, which is what killed the third-party
client ecosystem. Omni's default Twitter mode works around that the same way
Squawker and Nitter do: it activates an **anonymous guest token** — the exact
credential x.com hands a logged-out browser — and calls X's internal GraphQL
endpoints with it. No account, no API plan, read-only.

Two things to know before relying on it:

- **It breaks periodically, by design.** Those endpoints are identified by
  query IDs that change whenever X ships a frontend build. When Twitter
  sources start failing, open **Sources → Twitter (X) access** and paste
  current values, which you can lift from an actively-maintained project like
  [Squawker](https://github.com/j-fbriere/squawker) or
  [Nitter](https://github.com/zedeus/nitter). Because these live in settings
  rather than in the code, recovering takes a few seconds and no app update.
  Omni's error messages name the specific thing to update.
- **It is not a supported interface** and using it is contrary to X's terms of
  service. It is also rate limited, so a handful of accounts works much better
  than dozens. If you would rather stay inside the sanctioned path, switch the
  source to **Official API** mode and supply a bearer token from a paid plan.

## Building

Requires Flutter 3.32+.

```sh
flutter pub get
flutter run            # debug on a connected device/emulator
flutter build apk      # release APK
```

Run checks:

```sh
flutter analyze
flutter test
```

## Releases

Pre-release APKs are built and published by the **Release APK** GitHub Actions
workflow (`.github/workflows/release.yml`) — push a `v*` tag or run the
workflow manually with a tag name, and a signed APK lands on the release page.

Release builds are currently signed with `android/app/dev-keystore.jks`, a
**development keystore committed to this repo** so pre-releases work with zero
setup. Anyone with the repo can sign APKs with it, so before distributing the
app for real, generate a private keystore and point the build at it via the
`OMNI_KEYSTORE_PATH`, `OMNI_KEYSTORE_PASSWORD`, `OMNI_KEY_ALIAS` and
`OMNI_KEY_PASSWORD` environment variables (e.g. from GitHub Actions secrets).
Note that switching keys changes the APK signature, so devices with an older
install must uninstall before updating.

## Architecture

```
lib/
├── models/        # Network enum, FeedItem (normalized post), FeedSource (config)
├── services/      # One client per network + FeedRepository (parallel fetch/merge)
│   ├── mastodon_client.dart
│   ├── bluesky_client.dart
│   ├── reddit_client.dart
│   ├── twitter_client.dart
│   ├── rss_client.dart
│   ├── feed_repository.dart
│   └── source_store.dart   # encrypted persistence of source configs
├── state/         # AppState (ChangeNotifier via provider)
└── ui/            # Home timeline, post cards, add-source & manage-sources screens
```

Every client implements `SourceClient.fetchLatest()` and normalizes its
network's payload into a shared `FeedItem`, so adding a new network is one
client class plus an enum entry.

## Roadmap ideas

- Full Mastodon/Bluesky OAuth login flows (instead of pasted tokens)
- Post detail view with reply threads
- Posting/cross-posting
- Background refresh and notifications
- Offline cache of the timeline

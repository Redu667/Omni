# Omni

<img src="docs/icon.png" alt="Omni" width="96" align="right">

One timeline for all your feeds. Omni is a Flutter app for Android that merges
**Mastodon**, **Bluesky**, **Reddit**, **Twitter/X** and **RSS/Atom** into a
single reverse-chronological feed — in the spirit of focused clients like
Moshidon, but spanning multiple networks.

## Features

- **Unified timeline** — posts from every configured source, merged and sorted
  by time, with pull-to-refresh and endless scrolling: each network is paged
  with its own cursor, and sources that run out drop out quietly.
- **Easy setup** — in-app Mastodon sign-in (OAuth, no token pasting), a
  quick-start screen with curated no-account sources, and every source is
  test-fetched when you add it so mistakes fail immediately with a clear
  message.
- **RSS auto-discovery, OPML import & export** — paste any website URL and
  Omni finds its feed; bring subscriptions in from another reader, and take
  them out again.
- **Native post view** — tapping a post renders it with Flutter widgets in
  the same visual language as the timeline: full text, media, engagement
  counts, and the reply thread underneath (Reddit comments, Mastodon context,
  Bluesky threads). The original page is one tap away, in Omni's browser or
  yours, but you never have to go there to read.
- **Open any account** — tap an author anywhere to see their recent posts,
  on Mastodon, Bluesky, Reddit or X.
- **Save posts** — long-press to keep one. Saved posts are stored in full, so
  they stay readable after the source is removed or the original is deleted.
- **Works offline** — the timeline is cached to disk and shown the moment you
  open the app; a failed refresh keeps what you had instead of blanking.
- **Read state** — opening a post marks it read; read posts dim, or hide
  entirely if you prefer, with mark-all-read a tap away.
- **Alt text** — image descriptions are carried through from Mastodon,
  Bluesky and X, shown under the image and exposed to screen readers.
- **Collections** — group sources across networks under one name. Put a
  subreddit, an account and a feed about the same subject together and read
  them as one timeline.
- **Sidebar navigation** — collections and networks live in a drawer rather
  than a chip bar that would overflow once you have a few of each.
- **Content warnings honoured** — Mastodon spoilers and Reddit's over-18 flag
  hide a post's body and media behind a reveal rather than showing content the
  author marked as hidden.
- **Mute filters** — hide posts by word, phrase or account across every
  source. Single words match on word boundaries (muting "art" won't hide
  "start"); accounts match however you type them, `@name`, `u/name` or bare.
  The timeline says how many posts are being hidden so nothing vanishes
  silently.
- **Multiple sources per network** — several subreddits, several feeds,
  several accounts; toggle each on/off or remove it.
- **Graceful partial failure** — a source that fails keeps its last posts in
  the timeline rather than vanishing, and says so. Transient failures retry
  with backoff; rate limits are honoured rather than hammered.
- **Reddit without the 403s** — an optional app ID authenticates requests,
  which Reddit doesn't block, restoring scores and comment counts that its
  Atom fallback can't carry.
- **Material 3 with Material You** — takes its palette from your wallpaper on
  Android 12+, with a light/dark/system override and a switch back to Omni's
  own colours.
- **Encrypted credential storage** — tokens and app passwords are kept in
  Android's encrypted storage via `flutter_secure_storage`.

## Supported sources

| Network | What you can add | Auth |
|---|---|---|
| Mastodon | Home timeline, or any instance's public/local timeline | In-app OAuth sign-in (or none for public timelines) |
| Bluesky | Your home timeline, or any user's public feed | Optional app password (Settings → App Passwords) |
| Reddit | Any subreddit (`flutter` or `flutter+androiddev`) | None — falls back to Reddit's Atom feeds when the JSON API is blocked, which it often is |
| Twitter/X | Public posts from chosen usernames | **Sign in** (recommended), anonymous, or the official API v2 with your own bearer token |
| RSS / Atom | Any feed URL | None |

### Twitter/X without an API plan

X removed free API read access in 2023, which is what killed the third-party
client ecosystem. Omni works around that the same way Squawker and Nitter do:
it talks to X's internal GraphQL endpoints — the ones x.com's own web app
uses — rather than the paid API. Read-only, no API plan.

There are two ways to authenticate that, and the difference matters a lot:

- **Signed in (recommended).** Log in to x.com in an in-app browser; Omni
  keeps the session cookie X sets and sends it with each request. Your
  password is typed on X's own pages and never passes through Omni. This is
  the only mode that reliably returns a **live** timeline.
- **Anonymous.** Omni activates a guest token, the credential x.com issues to
  logged-out visitors. It needs no account, but X increasingly serves guests a
  stale slice of the timeline — often posts a year old — rather than current
  ones. Fine for a quick look, unreliable as a feed.

Two things to know before relying on it:

- **It breaks periodically, by design.** Those endpoints are identified by
  query IDs that change whenever X ships a frontend build. When Twitter
  sources start failing, open **Sources → Twitter (X) access** and paste
  current values, which you can lift from an actively-maintained project like
  [Squawker](https://github.com/j-fbriere/squawker) or
  [Nitter](https://github.com/zedeus/nitter). Because these live in settings
  rather than in the code, recovering takes a few seconds and no app update.
  Omni's error messages name the specific thing to update.
- **Stale results are reported, not shown.** Guest access degrades quietly: X
  keeps answering `200 OK` while serving an old slice of the timeline. Omni
  refuses to present that as current — if the newest post is more than 45 days
  old, the source reports an error instead of passing year-old posts off as
  fresh, and points at whichever fix applies.
- **Signing in carries real risk to that account.** Using an account outside
  the official API is contrary to X's terms of service, and accounts have been
  suspended for it. Use a secondary account rather than one you depend on.
- **It is not a supported interface** and it is rate limited, so a handful of
  accounts works much better than dozens. To stay inside the sanctioned path,
  switch the source to **Official API** mode and supply a bearer token from a
  paid plan.

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

## App icon

The launcher icon is an "O" built from five arcs, one per network Omni
aggregates. It's generated rather than hand-drawn — run `python3
tools/make_icon.py` (needs Pillow) to regenerate every density plus the
Android adaptive-icon layers after changing the colours or proportions.

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

## Roadmap

[`docs/FEATURE-AUDIT.md`](docs/FEATURE-AUDIT.md) surveys what dedicated
clients for each network offer against what Omni does today, per network plus
the cross-cutting gaps, with a shortlist ordered by value per effort.

The largest gaps as of 0.5.x: no pagination (only the newest ~40 posts per
source are ever fetched), no offline cache or read state, no image viewer or
video playback, and no thread parent context.

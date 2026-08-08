# Feature audit — what Omni is missing as a reader

A survey of what dedicated clients for each network offer, measured against
what Omni does today. This is a map of the gap, not a commitment: plenty of
these are deliberate non-goals for a read-only aggregator.

Status key: **✗** missing · **◐** partial · **✓** done

---

## Resilience

How Omni behaves when a service says no, which on Reddit and X is often.

| Behaviour | Status | Notes |
|---|---|---|
| **Retry with backoff** | ✓ | Transient failures (429, 5xx, timeouts, dropped connections) retry with jittered exponential backoff. 403 and 404 are terminal — retrying a block just delays the fallback. |
| **`Retry-After`** | ✓ | Honoured when short; a server asking for ten minutes is told no and the refresh returns instead of blocking. |
| **Graceful degradation** | ✓ | A source that starts failing keeps its last posts in the timeline, marked stale, instead of vanishing. |
| **Per-source health** | ✓ | Consecutive failures and last success tracked, so a blip reads differently from a week-long outage. |
| **Reddit authentication** | ✓ | An optional app ID makes requests authenticated, which is the actual fix for its 403s rather than the Atom fallback's damage limitation. |
| **Conditional requests** | ◐ | RSS sends `If-None-Match`/`If-Modified-Since` and reuses parsed items on a 304. Not yet applied to the JSON APIs. |
| **Per-source retry scheduling** | ✗ | A persistently failing source is retried as often as a healthy one. |
| **Offline detection** | ✗ | No connectivity awareness; a refresh with no signal fails per-source rather than being skipped. |

## Cross-cutting — affects every source

These matter more than any single network's features, because they shape
whether Omni is usable as a daily reader at all.

| Gap | Status | Notes |
|---|---|---|
| **Pagination / infinite scroll** | ✓ | Each network is paged with its own cursor (Mastodon `max_id`, Reddit `after`, Bluesky/X tokens); sources drop out as they run out. RSS is the exception — feeds publish a fixed window with no way to ask for older entries. |
| **Offline cache** | ✓ | The timeline is kept on disk and shown instantly at launch, with a banner while it's stale. A refresh that fails everywhere keeps the cache rather than blanking the feed. |
| **Read / unread state** | ◐ | Opening a post marks it read; read posts dim, or hide entirely by choice, and there's mark-all-read. Not yet: marking read by scrolling past. |
| **Save / bookmark posts** | ✓ | Long-press to save. The whole post is stored, so it survives its source being removed or the original being deleted. |
| **Background refresh & notifications** | ✗ | Omni only fetches while open and in the foreground. |
| **Search** | ✗ | Neither within the loaded feed nor against each network's search API. |
| **Image viewer** | ◐ | The detail view shows every image; the timeline shows the first with a count badge. Still no tap-to-zoom, pan, or saving. |
| **Video** | ✗ | No playback anywhere. Reddit `v.redd.it`, Mastodon and Bluesky video, and X video are all silently dropped. |
| **Alt text** | ✓ | Carried from Mastodon, Bluesky and X, shown under each image in the detail view, exposed to screen readers, and flagged with an ALT badge in the timeline. |
| **Link preview cards** | ✗ | Link posts show a bare URL rather than title/description/thumbnail. |
| **Share sheet** | ✗ | Can copy a link from the detail menu; can't share to another app. |
| **Content warnings** | ✓ | Mastodon spoilers and Reddit `over_18` hide the body behind a reveal. |
| **Mute filters** | ◐ | Words and accounts work. No regex, no per-source scoping, no time-limited mutes, no muting by hashtag or domain. |
| **Display settings** | ◐ | Material You wallpaper colours plus a light/dark/system override. No text size, density, or compact layout. |
| **Per-source refresh interval** | ✗ | Everything refreshes together, on demand only. |
| **Collections / folders** | ✓ | User-made groupings that span networks, selected from the sidebar. |
| **Cross-post de-duplication** | ✗ | The same story from an RSS feed and a subreddit appears twice. Only exact id collisions are deduped. |
| **Translation** | ✗ | No inline translation of foreign-language posts. |

---

## Mastodon

Closest comparison: Moshidon, Tusky, Ivory.

| Gap | Status | Notes |
|---|---|---|
| Home timeline | ✓ | Via OAuth sign-in. |
| Public / local timeline | ✓ | No account needed. |
| Content warnings | ✓ | |
| **Thread parent context** | ✓ | Ancestors are shown above the post, tappable to walk up the conversation. |
| **Polls** | ✗ | Poll posts render as empty text. |
| **Custom emoji** | ✗ | `:shortcodes:` show as literal text instead of the instance's emoji. |
| **Interactions** | ✗ | No favourite, boost, reply, or follow. Omni is read-only by design, but favouriting is the one most readers expect. |
| **Notifications timeline** | ✗ | No mentions, follows, or replies view. |
| **Lists & hashtag timelines** | ✗ | Only home and public. Mastodon lists are a major curation tool. |
| **Profile view** | ✓ | Tap an author to see their recent posts. |
| **Bookmarks & favourites** | ✗ | Can't read your own saved posts. |
| **Sensitive media blur** | ◐ | Whole post is hidden; no per-attachment blur-with-tap. |
| **Filters (server-side)** | ✗ | Mastodon's own keyword filters are ignored; Omni's local ones are separate. |

---

## Bluesky

Closest comparison: the official app, Graysky, deck.blue.

| Gap | Status | Notes |
|---|---|---|
| Home timeline | ✓ | Via app password. |
| Public author feed | ✓ | No auth needed. |
| Thread replies | ✓ | |
| **Custom feeds** | ✗ | Bluesky's headline feature — "Discover", "What's Hot", and thousands of community algorithms — is entirely absent. Arguably the biggest single omission for Bluesky users. |
| **Lists** | ✗ | No list timelines or moderation lists. |
| **Quote posts** | ✗ | The quoted post isn't rendered; only the commentary shows, which can invert the meaning. |
| **External embed cards** | ✗ | Link embeds are dropped rather than shown as cards. |
| **Labels & moderation** | ◐ | Adult and graphic-media labels hide the post behind a reveal. Custom labeler subscriptions and per-label preferences aren't supported. |
| **Thread parent context** | ✓ | The parent chain is walked and shown oldest-first. |
| **Interactions** | ✗ | No like, repost, reply, or follow. |
| **Profile view** | ✓ | Tap an author to see their recent posts. |
| **Video** | ✗ | |
| **Session reuse** | ✗ | Signs in fresh on every refresh instead of caching the JWT — slower, and needlessly hard on their servers. |

---

## Reddit

Closest comparison: Infinity, RedReader, Boost.

| Gap | Status | Notes |
|---|---|---|
| Subreddit listings | ✓ | Multireddits (`a+b+c`) work. |
| Sort (hot/new/top/rising) | ✓ | Selectable when adding, changeable afterwards. |
| Comments with nesting | ✓ | |
| **Time filter for `top`** | ✗ | `top` always means all-time; no hour/day/week/month/year. |
| **Comment sort** | ✗ | Hardcoded to `top`; no best/new/controversial/old. |
| **Collapse comment threads** | ✗ | Long chains can't be folded, which makes big threads unreadable on a phone. |
| **Load more comments** | ✗ | "more" stubs are skipped, so deep threads are silently truncated. |
| **Galleries** | ✗ | Multi-image posts show one image. |
| **Video** | ✗ | `v.redd.it` unsupported. |
| **Polls** | ✗ | |
| **Flair** | ✗ | Neither shown nor filterable, though flair is how many subreddits organise themselves. |
| **User profile feeds** | ◐ | Tapping an author shows their submitted posts; can't add `u/someone` as a standing source. |
| **Logged-in Reddit** | ◐ | An app ID authenticates requests and sidesteps the blocking. A full user login (home feed, saved posts, subscriptions) is still missing. |
| **Crossposts** | ✗ | Render as empty posts. |
| **Atom fallback is lossy** | ◐ | Still the last resort when unauthenticated and blocked — no score, comment count or self-text. Configuring an app ID avoids needing it. |

---

## Twitter / X

Closest comparison: Squawker; historically Tweetbot and Talon.

| Gap | Status | Notes |
|---|---|---|
| User timelines | ✓ | Via signed-in session. |
| Stale-data detection | ✓ | Refuses to present a stale timeline as current. |
| **Home timeline** | ✓ | A Twitter source can follow your own timeline instead of named accounts, when signed in. |
| **Quote tweets** | ✗ | Quoted post not rendered. |
| **Conversation threads** | ✗ | `fetchThread` isn't implemented for X at all; replies are unavailable. |
| **Search** | ✗ | |
| **Lists** | ✗ | |
| **Bookmarks** | ✗ | |
| **Polls** | ✗ | |
| **Video** | ✗ | |
| **Interactions** | ✗ | No like, repost, or reply. |
| **Fragility** | ◐ | Query IDs are user-editable, which softens breakage but doesn't prevent it. No automatic detection or self-updating. |

---

## RSS / Atom

Closest comparison: Feedly, NetNewsWire, Miniflux.

| Gap | Status | Notes |
|---|---|---|
| RSS 2.0 & Atom | ✓ | |
| Feed auto-discovery | ✓ | Paste a site URL, Omni finds the feed. |
| OPML import | ✓ | |
| **OPML export** | ✓ | Settings → Export OPML. |
| **Full-text extraction** | ✗ | Truncated feeds stay truncated. A readability pass would fix the many feeds that publish only a teaser. |
| **Folders / categories** | ◐ | Collections group feeds (and everything else) across networks. OPML folder structure is still discarded on import. |
| **Unread counts per feed** | ✗ | |
| **Podcast enclosures** | ✗ | Audio enclosures are ignored — no playback, no queue. |
| **Per-feed favicon** | ✗ | All feeds share one generic icon, making a mixed timeline harder to scan. |
| **Conditional requests** | ✓ | `ETag`/`If-Modified-Since` sent, with a 304 reusing already-parsed items. |
| **JSON Feed** | ✗ | |

---

## If you want a shortlist

Ordered by value-per-effort rather than by how impressive they sound.

1. **Full-screen image viewer** — tap to zoom, swipe a gallery, save. The most visible day-to-day rough edge now.
2. **Search** — across the loaded feed first, which needs no new API work at all.
3. **Bluesky custom feeds** — the main reason Bluesky users use Bluesky.
4. **Reddit "load more" comments** — deep threads are quietly cut off today.
5. **Mark read by scrolling past** — the half of read-state that's still missing.
6. **Quote posts** (Bluesky + X) — a quote with the quoted post missing can invert its meaning.
7. **Link preview cards** — link posts currently show a bare URL.
8. **Background refresh & notifications** — the last thing keeping Omni a foreground-only app.
9. **Video playback** — big lift, touches every network.
10. **Polls** — Mastodon, Reddit and X all have them; all render as empty posts.

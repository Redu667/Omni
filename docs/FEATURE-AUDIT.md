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
| **Read / unread state** | ✓ | Opening a post marks it read; scrolling one off the top of the screen does too, behind a setting. Read posts dim, or hide entirely by choice, and there's mark-all-read. Posts marked by scrolling stay in place until the next refresh, so the list never shifts under a moving thumb. |
| **Save / bookmark posts** | ✓ | Long-press to save. The whole post is stored, so it survives its source being removed or the original being deleted. |
| **Background refresh & notifications** | ✗ | Omni only fetches while open and in the foreground. |
| **Search** | ◐ | Searches everything loaded — titles, bodies, authors, flair, alt text, quoted posts and link cards — ignoring the active collection and network chip. Not yet: querying each network's own search API for posts you haven't loaded. |
| **Image viewer** | ◐ | Tap any image for full screen: pinch-zoom, pan, swipe between a gallery, alt text under the picture. Not yet: saving to the device. |
| **Video** | ✓ | Plays in-app on all four networks that have it — Mastodon video and `gifv`, Bluesky's HLS embeds, Reddit `v.redd.it`, and X video and animated GIFs. Timeline shows the poster frame with a play badge and the running time; GIFs loop silently, everything else plays once with sound. |
| **Alt text** | ✓ | Carried from Mastodon, Bluesky and X, shown under each image in the detail view, exposed to screen readers, and flagged with an ALT badge in the timeline. |
| **Link preview cards** | ✓ | Mastodon cards, Bluesky external embeds and Reddit outbound links render as tappable cards. |
| **Share sheet** | ✓ | Long-press a post to hand its link to Android's share sheet, or copy it. |
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
| **Polls** | ✓ | Options and vote shares shown. Read-only — Omni doesn't vote. |
| **Custom emoji** | ✓ | Instance emoji render inline in post bodies, titles, display names and replies, sized to the line. Only shortcodes the post declares are substituted, so `10:30` stays a time. An emoji that won't load falls back to the code it stands for. |
| **Interactions** | ✗ | No favourite, boost, reply, or follow. Omni is read-only by design, but favouriting is the one most readers expect. |
| **Notifications timeline** | ✗ | No mentions, follows, or replies view. |
| **Lists & hashtag timelines** | ✓ | Hashtag timelines need no account and can be scoped to one instance; lists are offered by name after signing in, rather than by numeric id. |
| **Profile view** | ✓ | Tap an author to see their recent posts. |
| **Bookmarks & favourites** | ✓ | Both readable as sources once signed in. They page by their own ids from the `Link` header, not by status id — paging them as a timeline returns the same page forever. |
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
| **Custom feeds** | ✓ | Paste a feed's bsky.app link (or an `at://` URI) and it becomes a source. The handle in the link is resolved to a DID, and signing in routes the request through the authenticated host so generators that refuse anonymous readers still work. |
| **Lists** | ◐ | List feeds work the same way, from a `/lists/` link. Moderation lists aren't applied. |
| **Quote posts** | ✓ | The quoted post renders inline; deleted and blocked quotes are omitted rather than shown blank. |
| **External embed cards** | ✓ | |
| **Labels & moderation** | ◐ | Adult and graphic-media labels hide the post behind a reveal. Custom labeler subscriptions and per-label preferences aren't supported. |
| **Thread parent context** | ✓ | The parent chain is walked and shown oldest-first. |
| **Interactions** | ✗ | No like, repost, reply, or follow. |
| **Profile view** | ✓ | Tap an author to see their recent posts. |
| **Video** | ✓ | HLS embeds play, including when nested under `recordWithMedia`. |
| **Session reuse** | ✓ | One sign-in serves every Bluesky source and survives between refreshes; the token is renewed with the refresh token rather than the password, and a rejected token triggers one fresh sign-in and a retry instead of a visible failure. |

---

## Reddit

Closest comparison: Infinity, RedReader, Boost.

| Gap | Status | Notes |
|---|---|---|
| Subreddit listings | ✓ | Multireddits (`a+b+c`) work. |
| Sort (hot/new/top/rising) | ✓ | Selectable when adding, changeable afterwards. |
| Comments with nesting | ✓ | |
| **Time filter for `top`** | ✓ | Hour through all-time, offered only for `top` and `controversial` — Reddit ignores it elsewhere. |
| **Comment sort** | ✓ | Best, top, new, old, controversial and Q&A, chosen from the thread itself. |
| **Collapse comment threads** | ✓ | Tap a comment's header to fold it and everything under it, with a count of what's hidden. The body isn't the handle — selecting text there would fold the comment out from under you. |
| **Load more comments** | ✓ | "N more replies" loads in place, at the right indentation, both at the top level and under a specific comment. Reddit's 100-per-request cap is handled by leaving the remainder behind the next button. "Continue this thread" stubs, which carry nothing to request, aren't offered. |
| **Galleries** | ✓ | Every image of a gallery is carried, with captions as alt text. |
| **Video** | ✓ | `v.redd.it` plays via its HLS stream. The `fallback_url` is video-only, so it's the last resort — a silent clip is worse than an obvious failure — except for converted GIFs, which have no audio to lose. |
| **Polls** | ✗ | |
| **Flair** | ◐ | Shown as a chip on posts. Not yet filterable. |
| **User profile feeds** | ◐ | Tapping an author shows their submitted posts; can't add `u/someone` as a standing source. |
| **Logged-in Reddit** | ◐ | An app ID authenticates requests and sidesteps the blocking. A full user login (home feed, saved posts, subscriptions) is still missing. |
| **Crossposts** | ✓ | Content is taken from the original, with the source subreddit attributed. |
| **Atom fallback is lossy** | ◐ | Still the last resort when unauthenticated and blocked — no score, comment count or self-text. Configuring an app ID avoids needing it. |

---

## Twitter / X

Closest comparison: Squawker; historically Tweetbot and Talon.

| Gap | Status | Notes |
|---|---|---|
| User timelines | ✓ | Via signed-in session. |
| Stale-data detection | ✓ | Refuses to present a stale timeline as current. |
| **Home timeline** | ✓ | A Twitter source can follow your own timeline instead of named accounts, when signed in. |
| **Quote tweets** | ✓ | Rendered inline, as on Bluesky. |
| **Conversation threads** | ✓ | Replies load via TweetDetail, with the tweets above the one being read shown as its ancestors and reply chains indented. A stale query ID leaves the post readable and simply shows no conversation. |
| **Search** | ✗ | |
| **Lists** | ✗ | |
| **Bookmarks** | ✗ | |
| **Polls** | ✗ | |
| **Video** | ✓ | The highest-bitrate MP4 variant, since the HLS one carries no bitrate to compare and is often account-gated. |
| **Interactions** | ✗ | No like, repost, or reply. |
| **Fragility** | ◐ | Every query ID is user-editable — including the home timeline and TweetDetail ones, which were previously reset to defaults whenever the screen was saved. Still no automatic detection or self-updating. |

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

1. **Background refresh & notifications** — the last thing keeping Omni foreground-only.
2. **Network-side search** — local search covers what's loaded; finding an old post still means scrolling to it.
3. **Cross-post de-duplication** — the same story from an RSS feed and a subreddit still appears twice.
4. **RSS full-text extraction** — feeds that publish only a teaser stay a teaser.
5. **JSON Feed** — a third feed format Omni doesn't read.

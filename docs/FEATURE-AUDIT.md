# Feature audit — what Omni is missing as a reader

A survey of what dedicated clients for each network offer, measured against
what Omni does today. This is a map of the gap, not a commitment: plenty of
these are deliberate non-goals for a read-only aggregator.

Status key: **✗** missing · **◐** partial · **✓** done

---

## Cross-cutting — affects every source

These matter more than any single network's features, because they shape
whether Omni is usable as a daily reader at all.

| Gap | Status | Notes |
|---|---|---|
| **Pagination / infinite scroll** | ✗ | Only the newest ~40 posts per source are ever fetched. There is no way to reach older posts — scroll to the bottom and the feed simply ends. Arguably the single biggest limitation. |
| **Offline cache** | ✗ | Nothing is persisted. Every launch refetches from scratch; with no signal there is no feed at all, and a refresh discards what you were reading. |
| **Read / unread state** | ✗ | No notion of what you've already seen, so refreshing loses your place. Feed readers live on this. |
| **Save / bookmark posts** | ✓ | Long-press to save. The whole post is stored, so it survives its source being removed or the original being deleted. |
| **Background refresh & notifications** | ✗ | Omni only fetches while open and in the foreground. |
| **Search** | ✗ | Neither within the loaded feed nor against each network's search API. |
| **Image viewer** | ✗ | Images are fixed-height crops; no tap-to-zoom, no pan, no swiping a gallery, no saving. Only the *first* image of a multi-image post is shown at all. |
| **Video** | ✗ | No playback anywhere. Reddit `v.redd.it`, Mastodon and Bluesky video, and X video are all silently dropped. |
| **Alt text** | ✗ | Never displayed, and never surfaced to screen readers. Both Mastodon and Bluesky have strong alt-text cultures, so this is a real accessibility gap. |
| **Link preview cards** | ✗ | Link posts show a bare URL rather than title/description/thumbnail. |
| **Share sheet** | ✗ | Can copy a link from the detail menu; can't share to another app. |
| **Content warnings** | ✓ | Mastodon spoilers and Reddit `over_18` hide the body behind a reveal. |
| **Mute filters** | ◐ | Words and accounts work. No regex, no per-source scoping, no time-limited mutes, no muting by hashtag or domain. |
| **Display settings** | ◐ | Light/dark/system theme override. No text size, density, or compact layout. |
| **Per-source refresh interval** | ✗ | Everything refreshes together, on demand only. |
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
| **Thread parent context** | ✗ | The detail view fetches `descendants` but ignores `ancestors`, so opening a reply shows the replies *to* it and never what it was replying to. The API call already returns this — it's discarded. |
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
| **Labels & moderation** | ✗ | Labeler annotations (including adult-content labels) are ignored, so Bluesky's own moderation is bypassed. Worth treating as a correctness issue, not a feature. |
| **Thread parent context** | ✗ | Same gap as Mastodon: replies shown, parents not. |
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
| **Logged-in Reddit** | ✗ | No account, so no home feed, saved posts, subscriptions, or voting. Would also sidestep the blocking below. |
| **Crossposts** | ✗ | Render as empty posts. |
| **Atom fallback is lossy** | ◐ | When Reddit blocks the JSON API (common, even for public subreddits) Omni falls back to Atom, which carries no score, comment count, or self-text. |

---

## Twitter / X

Closest comparison: Squawker; historically Tweetbot and Talon.

| Gap | Status | Notes |
|---|---|---|
| User timelines | ✓ | Via signed-in session. |
| Stale-data detection | ✓ | Refuses to present a stale timeline as current. |
| **Home timeline** | ✗ | Omni is signed in, so `HomeTimeline` is available — it just isn't wired up. Probably the cheapest high-value win on this list. |
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
| **Folders / categories** | ✗ | Flat list only; no grouping, and OPML folder structure is discarded on import. |
| **Unread counts per feed** | ✗ | |
| **Podcast enclosures** | ✗ | Audio enclosures are ignored — no playback, no queue. |
| **Per-feed favicon** | ✗ | All feeds share one generic icon, making a mixed timeline harder to scan. |
| **Conditional requests** | ✗ | No `ETag`/`If-Modified-Since`, so every refresh refetches everything in full. Wasteful for both you and the publisher. |
| **JSON Feed** | ✗ | |

---

## If you want a shortlist

Ordered by value-per-effort rather than by how impressive they sound.

1. **Pagination** — without it the feed is a fixed window, and everything else is polish on a stunted app.
2. **Offline cache + read state** — turns Omni from a live query into an actual reader that keeps your place.
3. **X home timeline** — small change, large payoff, and the auth work is already done.
4. **Thread parent context** (Mastodon + Bluesky) — a few lines each; the data is already in the responses Omni fetches and discards.
5. **Image viewer with multi-image support** — currently the most visible day-to-day rough edge.
6. **Bluesky custom feeds** — the main reason Bluesky users use Bluesky.
7. **Bluesky labels** — moderation currently bypassed; belongs with correctness work rather than features.
8. **Reddit "load more" comments** — deep threads are quietly cut off today.
9. **Video playback** — big lift, touches every network.
10. **OPML export** — small, and removes a lock-in problem.

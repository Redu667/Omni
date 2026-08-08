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
| **Per-source retry scheduling** | ✓ | A source that keeps refusing is left alone for a while — two minutes, then five, fifteen, thirty — rather than being asked on every refresh. Hammering a 403 is how a temporary block becomes a lasting one. The first two failures cost nothing, the delay is capped so a source is never abandoned, and pull-to-refresh or Retry overrides it. |
| **Offline detection** | ✓ | A dropped connection is told apart from a service refusing, by the failure itself rather than by asking the platform — a phone on wifi with no route out is still offline. It doesn't count against any source's retry backoff, and shows as one "no connection" line instead of the same error once per source. |

## Cross-cutting — affects every source

These matter more than any single network's features, because they shape
whether Omni is usable as a daily reader at all.

| Gap | Status | Notes |
|---|---|---|
| **Pagination / infinite scroll** | ✓ | Each network is paged with its own cursor (Mastodon `max_id`, Reddit `after`, Bluesky/X tokens); sources drop out as they run out. RSS is the exception — feeds publish a fixed window with no way to ask for older entries. |
| **Offline cache** | ✓ | The timeline is kept on disk and shown instantly at launch, with a banner while it's stale. A refresh that fails everywhere keeps the cache rather than blanking the feed. |
| **Read / unread state** | ✓ | Opening a post marks it read; scrolling one off the top of the screen does too, behind a setting. Read posts dim, or hide entirely by choice, and there's mark-all-read. Posts marked by scrolling stay in place until the next refresh, so the list never shifts under a moving thumb. |
| **Save / bookmark posts** | ✓ | Long-press to save. The whole post is stored, so it survives its source being removed or the original being deleted. |
| **Background refresh & notifications** | ✓ | A periodic fetch while Omni is closed, off by default, with the interval chosen in Settings. Notifications are opted into per source, one per source rather than per post, and the first run for a source stays quiet so switching it on doesn't announce a backlog. Android treats the interval as a request, which the setting says. |
| **Search** | ✓ | Searches everything loaded — titles, bodies, authors, flair, alt text, quoted posts and link cards — ignoring the active collection and network chip; press enter to ask Mastodon, Bluesky and Reddit for posts you haven't loaded. RSS has no search API and X's would be another rotating query ID, so neither is offered. |
| **Image viewer** | ✓ | Tap any image for full screen: pinch-zoom, pan, swipe between a gallery, alt text under the picture, and save to the device gallery — video too, where the network serves a file rather than a stream. |
| **Video** | ✓ | Plays in-app on all four networks that have it — Mastodon video and `gifv`, Bluesky's HLS embeds, Reddit `v.redd.it`, and X video and animated GIFs. Timeline shows the poster frame with a play badge and the running time; GIFs loop silently, everything else plays once with sound. |
| **Alt text** | ✓ | Carried from Mastodon, Bluesky and X for images and video alike, shown under each image in the detail view and under a playing video, exposed to screen readers, and flagged with an ALT badge in the timeline. |
| **Link preview cards** | ✓ | Mastodon cards, Bluesky external embeds and Reddit outbound links render as tappable cards. |
| **Share sheet** | ✓ | Long-press a post to hand its link to Android's share sheet, or copy it. |
| **Content warnings** | ✓ | Mastodon spoilers, Bluesky's adult and graphic-media labels, Reddit `over_18`, and the reader's own instance filters all hide the body behind a reveal — or drop the post outright, where the filter says hide. |
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
| **Search** | ✓ | Status search when signed in, and a `#tag` query uses the public tag timeline instead — status search is authenticated on nearly every instance. |
| **Notifications timeline** | ✗ | No mentions, follows, or replies view. |
| **Lists & hashtag timelines** | ✓ | Hashtag timelines need no account and can be scoped to one instance; lists are offered by name after signing in, rather than by numeric id. |
| **Profile view** | ✓ | Tap an author to see their recent posts. |
| **Bookmarks & favourites** | ✓ | Both readable as sources once signed in. They page by their own ids from the `Link` header, not by status id — paging them as a timeline returns the same page forever. |
| **Sensitive media blur** | ◐ | Whole post is hidden; no per-attachment blur-with-tap. |
| **Filters (server-side)** | ✓ | The instance's own filters are respected: `hide` drops the post, `warn` hides the body behind a reveal naming the filter. Mastodon evaluates them server-side and reports the verdict per status, so keyword rules, whole-word matching and expiry come from the instance rather than being reimplemented. |

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
| **Search** | ✓ | `searchPosts` on the public AppView, so it works on a source with no credentials. |
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
| **Search** | ✓ | Scoped to the subreddit the source follows, since site-wide results would drown out what the reader actually added. |
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
| **Search** | ✗ | SearchTimeline would need another rotating query ID, and every one of those is another thing to break. Local search covers X posts already fetched. |
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
| **Full-text extraction** | ✓ | A truncated post offers to go and get the article. Block elements are scored by how much prose they hold and discounted for being mostly links, so navigation and "related posts" don't win. It's a heuristic — when it can't find an article it says so, including that a paywall is one reason, rather than showing a confident wrong answer. |
| **Folders / categories** | ◐ | Collections group feeds (and everything else) across networks. OPML folder structure is still discarded on import. |
| **Unread counts per feed** | ✗ | |
| **Podcast enclosures** | ◐ | Audio enclosures play, with the episode's own art or the show's standing in for a picture, and `itunes:duration` read in either `HH:MM:SS` or plain seconds. No queue, no playback position, no background audio. |
| **Per-feed favicon** | ✓ | The image a feed declares (`channel/image`, `itunes:image`, Atom `icon`/`logo`, JSON Feed `icon`), falling back to the site's favicon. Relative paths are ignored in favour of the favicon rather than resolved against the wrong base. |
| **Conditional requests** | ✓ | `ETag`/`If-Modified-Since` sent, with a 304 reusing already-parsed items. |
| **JSON Feed** | ✓ | Detected by the body rather than the content type, since publishers serve it under several. Attachments become media by MIME type; anything Omni can't present, like a PDF, is skipped rather than shown as a broken image. |

---

## If you want a shortlist

Ordered by value-per-effort rather than by how impressive they sound.

1. **Cross-post de-duplication** — the same story from an RSS feed and a subreddit still appears twice. Deliberately not done: it needs a decision about which copy to keep, and it doesn't happen often enough to be worth getting wrong.
2. **Saving streamed video** — HLS and DASH are manifests, not files; keeping one means muxing the segments, which is a lot of machinery for a rare want.
4. **Per-source refresh interval** — everything refreshes together, on demand only. Only worth having alongside background refresh, and probably not even then.

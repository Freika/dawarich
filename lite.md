# Dawarich Cloud — Lite Plan Launch

## Overview

Dawarich Cloud currently offers a single plan at €119.99/year (€10/month). This document outlines the introduction of a lower-cost **Lite** plan at **€49/year (annual-only)** to serve casual and light users long-term, expanding the addressable market without cannibalizing the existing plan (renamed to **Pro**).

The core pricing philosophy: **never gate access to users' own data, only gate the power tools for working with that data.** Every user can always export everything. The tier split is about visualization depth, integration power, and history window — not data ownership.

---

## Plan Structure

### Lite — €49/year (annual-only)

The plan for casual trackers who want a private, managed alternative to Google Timeline without running their own server. Core tracking, interactive map, full import/export, trips, and 12 months of searchable history.

No monthly billing option at launch. Monthly may be added later based on demand.

### Pro — €120/year · €10/month

The plan for power users, lifeloggers, and tinkerers who need unlimited history, advanced visualizations, integrations, and full API access. This is the current plan, renamed.

---

## Feature Comparison

### Tracking & Data Collection

| Feature | Lite | Pro |
|---|---|---|
| iOS & Android native apps | ✓ | ✓ |
| Background location tracking | ✓ | ✓ |
| OwnTracks / GPSLogger / Overland | ✓ | ✓ |
| Apple Health import | ✓ | ✓ |

### Data Retention & Storage

| Feature | Lite | Pro |
|---|---|---|
| Searchable data history | 12 months | Unlimited |
| Older data archived (always exportable) | ✓ | n/a |
| European encrypted storage (LUKS + SSL) | ✓ | ✓ |

### Imports & Exports

| Feature | Lite | Pro |
|---|---|---|
| Google Takeout / GPX / GeoJSON / KML | Unlimited | Unlimited |
| Strava import | Unlimited | Unlimited |
| Photo EXIF import | Unlimited | Unlimited |
| Data export (GPX / GeoJSON) | Unlimited | Unlimited |

### Map & Visualization

| Feature | Lite | Pro |
|---|---|---|
| Interactive map (Map V2 — MapLibre GL JS) | ✓ | ✓ |
| Points & routes layers | ✓ | ✓ |
| Speed-colored routes | ✓ | ✓ |
| Daily timeline / replay | ✓ | ✓ |
| Heatmap layer | ✗ | ✓ |
| Fog of War / Scratch map | ✗ | ✓ |
| Globe view (3D) | ✗ | ✓ |

**Note:** Legacy Map V1 (Leaflet) is deprecated and will be removed in a future release. It is not offered to new users on any plan.

### Trips & Places

| Feature | Lite | Pro |
|---|---|---|
| Create & manage trips | ✓ | ✓ |
| Trip photo integration | ✗ | ✓ |
| Custom areas & visit suggestions | ✓ | ✓ |
| Places with tags & privacy zones | ✓ | ✓ |

### Statistics & Insights

| Feature | Lite | Pro |
|---|---|---|
| Basic stats (distance, cities, countries) | ✓ | ✓ |
| Monthly / yearly breakdowns | ✓ | ✓ |
| Year-in-review digest | limited | full |
| Year-in-review shareable card | ✓ | ✓ |
| Public stats sharing | ✗ | ✓ |

### Integrations

| Feature | Lite | Pro |
|---|---|---|
| Immich / PhotoPrism integration | ✗ | ✓ |

**Note:** Family location sharing is currently available only on self-hosted instances. It is not offered on any Cloud plan.

### API

| Feature | Lite | Pro |
|---|---|---|
| Tracker ingestion (OwnTracks, Overland, GPSLogger) | ✓ | ✓ |
| Read API (scoped to searchable data window) | ✓ | ✓ |
| Write API (programmatic point creation, bulk ops) | ✗ | ✓ |
| Rate limit | 200 req/hr | 1,000 req/hr |

### Inactive / Lapsed Subscription

| Feature | Inactive |
|---|---|
| View existing data on map (read-only) | ✓ |
| Data export (GPX / GeoJSON) | ✓ |
| New tracking / data ingestion | ✗ |
| All other features | ✗ |

After multiple years of inactivity and multiple warnings, data will be removed.

### Support

| Feature | Lite | Pro |
|---|---|---|
| Email support | ✓ | ✓ |

---

## Design Decisions & Rationale

### Why 12 months of searchable history

The data retention window is the single strongest pricing lever in the location-tracking SaaS space. Life360 uses 2 days (free) → 7 days (Silver) → 30 days (Gold). Gyroscope uses 30 days (free) → unlimited (paid). Google Timeline itself defaults to 3-month auto-delete.

Twelve months was chosen because:

- It covers a full year — users can revisit any season and see meaningful patterns across all four.
- It aligns with the annual billing cycle: "you pay for a year, you see a year."
- 6 months felt too aggressive for a paid plan and risked triggering churn instead of upgrades (users opening the app to find their data "gone" react with anger, not purchase intent).
- At a 2.4× price gap (€49 vs €120), a 12-month vs unlimited retention gap feels proportional without being punitive.
- Users wanting multi-year comparisons, life logs, or complete historical archives will naturally outgrow the window.

**Critical implementation detail:** Data older than 12 months must never be hard-deleted. Instead, implement a "rolling window + archive" model:

1. Points older than 12 months are **archived** — they remain in the database and are still visible on the map, but rendered in a visually distinct "locked" state (see [Archived Data Visual Treatment](#archived-data-visual-treatment) below).
2. Archived data is not interactive: no timeline replay, no stats inclusion, no search results.
3. Archived data remains fully accessible via the export endpoint at all times.
4. The UI clearly indicates: *"12 archived months — upgrade to Pro to explore them."*
5. Upgrading to Pro instantly makes all archived data fully interactive again — zero data loss.

This respects GDPR Article 20 data portability rights, preserves trust with the privacy-conscious community, and avoids the Fitbit backlash trap (they paywalled historical health data behind 7-day windows, triggering massive user revolt and ultimately reversing course).

The upgrade pitch: *"Your data is always yours — Pro makes all of it searchable and visualizable in-app."*

**Proactive archival warnings:**

- At 11 months: in-app notification — "Your oldest month will archive in 30 days."
- At 11.5 months: email — "Upgrade to Pro to keep your full history searchable."
- On archival: in-app banner — "1 month archived. [View archived data] [Upgrade to Pro]"

These warnings convert the archival moment from a surprise into a decision point.

### Archived data visual treatment

Archived points and routes must look clearly "locked but present" — not broken, not invisible, not aggressively disabled. The goal is to communicate "your data is here, it's just behind the upgrade" without triggering frustration.

**Options to evaluate:**

1. **Semi-transparent overlay** — Archived routes/points rendered at ~30% opacity. Feels like a "preview" of data that could be unlocked. Less likely to be confused with a rendering bug than full desaturation.

2. **Desaturation + dashed lines** — Archived routes rendered as gray dashed lines, archived points as gray hollow circles. Clearly distinct from active data. Risk: may look like a broken/loading state.

3. **Color tint + lock badge** — Archived routes rendered in a muted blue/purple tint (distinct from active data colors) with a small lock icon at the start of each archived route segment. Click/tap shows an upgrade tooltip.

4. **Boundary indicator** — A visible "timeline boundary" line on the map marking the 12-month cutoff. Data beyond the boundary is rendered normally but with a subtle overlay. Clicking anywhere beyond the boundary shows an upgrade prompt.

**Recommendation for MVP:** Start with option 1 (semi-transparent) combined with elements of option 3 (lock badge on tap/click). This is the simplest to implement in MapLibre (just change the `opacity` paint property for archived layers) and clearly communicates "data exists but is locked." Evaluate user feedback post-launch and refine.

**Interaction behavior on archived data:**
- **Tap/click on archived point or route** → Tooltip: *"This data is archived. [Upgrade to Pro] to explore your full history."*
- **Hover on archived route** (desktop) → Cursor changes to indicate non-interactive state.
- **No timeline replay, no stats, no search** — archived data is visual-only.

### Pro-only map layer previews

Instead of showing only a lock icon when a Lite user clicks a gated map layer toggle (heatmap, fog-of-war, globe), show a **time-limited preview** using the user's actual data:

1. User clicks the locked heatmap toggle.
2. Heatmap renders with their real data for ~15-30 seconds.
3. After the preview, the layer fades out and an upgrade prompt appears: *"Like your heatmap? Upgrade to Pro to keep it."*

This is significantly more compelling than a static screenshot. The preview uses real data the user already has, so there's no additional API cost — just a frontend timer that removes the layer.

**Implementation:** The frontend already loads all point data for the map. The heatmap/fog/globe layers can render from this existing data. The gating is a client-side timer + prompt, not a server-side restriction. The backend doesn't need to change for previews — it only needs to enforce that the layer toggle state doesn't persist for Lite users.

### Why gate heatmap, fog-of-war, and globe view

These are the "wow" features — visually impressive, emotionally engaging, and the most likely to appear in screenshots, social media posts, and word-of-mouth recommendations. Strava's personal heatmap is their single strongest upgrade driver.

Gating these creates a natural discovery → desire → upgrade path:

1. User signs up for Lite, imports Google Takeout data.
2. Sees the basic map with points, routes, and speed-colored routes — useful, functional.
3. Notices the locked heatmap/fog-of-war toggles in map settings.
4. Curiosity drives a preview click → sees their own heatmap → wants to keep it.

Keeping points, routes, speed-colored routes, and daily replay on Lite ensures the plan is genuinely useful — not a crippled demo.

### Why trips are available on Lite

Trips are the feature that turns passive tracking into active engagement. Gating them on Lite would leave the plan emotionally flat — a map with dots and lines but no way to organize travel memories. The moment a user takes a vacation and can't create a trip, they don't think "I should upgrade" — they think "this product doesn't do what I need."

Including trips on Lite:

- Makes the plan genuinely useful for the core "Google Timeline replacement" use case
- Increases engagement, which increases retention and upgrade probability
- Creates data investment (trip photos, names, notes) that raises switching costs

The upgrade path from Lite to Pro is driven by visualization depth (heatmap, fog-of-war, globe), data history (12 months vs unlimited), integrations (Immich), and power tools (full API, public sharing) — not by withholding core organizational features.

### Why limited year-in-review on Lite

Year-in-review is the single most shareable feature in any tracking product. Spotify Wrapped generates millions of social media posts annually. Strava recently paywalled their Year in Sport recap entirely and faced significant backlash. Gating it entirely on Pro means the largest audience (Lite users) can't share anything viral — cutting off the best organic acquisition channel.

**Lite year-in-review includes:**
- Top 3 cities visited
- Total distance traveled
- Total countries visited
- Total points tracked
- **Shareable image/card** optimized for social media (Instagram Stories / Twitter card format)
- Referral hook: "Track your own adventures — try Dawarich" with signup link

**Pro year-in-review adds:**
- Full monthly breakdown
- Detailed city/country rankings
- Transportation mode analysis
- Trip highlights with photos
- Shareable public link (interactive web page, not just image)

The limited version is a sharing hook that drives organic signups. The full version is the upgrade trigger. Both versions generate shareable cards — the Lite card is simpler but still designed for viral distribution.

### Why separate tracker ingestion from write API

The codebase confirms that tracker ingestion endpoints are architecturally separate from the general write API:

- **OwnTracks:** `POST /api/v1/owntracks/points` (separate controller: `Api::V1::Owntracks::PointsController`)
- **Overland:** `POST /api/v1/overland/batches` (separate controller: `Api::V1::Overland::BatchesController`)
- **General write API:** `POST /api/v1/points`, `PATCH /api/v1/points/:id`, `DELETE /api/v1/points/:id`

All tracker ingestion endpoints remain open on both plans. The write API restriction on Lite only blocks programmatic point creation, editing, deletion, and bulk operations via the general API. This is a clean separation:

- **Tracking endpoints** (open on all plans): The pipes that feed data in from mobile apps and third-party trackers.
- **Automation endpoints** (Pro only): The tools power users use for custom scripts, Home Assistant integrations, and programmatic data manipulation.

### Why Read API is scoped to the searchable data window

The Read API on Lite returns only data within the 12-month searchable window. Archived data is excluded from API responses (but always available via the export endpoint). This prevents technically savvy users from building their own visualization layer on top of the full dataset via API while paying for Lite. The export endpoint remains unrestricted — users can always get all their data out, they just can't programmatically query archived data in real time.

### Why Pro also gets rate-limited

No plan should have unlimited API access. Even Pro at 1,000 req/hr is generous for personal use and protects against:

- Runaway scripts or misconfigured automations
- Accidental DDoS from broken integrations
- Abuse from scrapers or bots

1,000 req/hr is roughly 16 requests per minute — more than enough for any reasonable personal automation, dashboard refresh, or integration sync.

### Why imports and exports are unlimited on both plans

This is a non-negotiable for a privacy-focused product. Gating data portability would:

- Contradict the core brand promise ("your data, your rules")
- Create GDPR compliance risk (Article 20 — right to data portability)
- Alienate the self-hosting community that forms Dawarich's word-of-mouth engine

The cost of unlimited imports is manageable — import jobs run asynchronously via Sidekiq and the primary cost is one-time processing, not ongoing resource consumption.

### Why family sharing is self-hosted only (not on any Cloud plan)

Family location sharing involves:

- Real-time WebSocket connections (ongoing server cost)
- Multi-user coordination and consent management
- Significantly more complex infrastructure per user

Family sharing is currently available only on self-hosted instances. It is not offered on any Cloud plan at launch. This may change in a future Cloud tier (e.g., a "Family" plan), but for now, the feature stays self-hosted only to manage infrastructure complexity.

### Why inactive users retain read-only access

When a subscription lapses (active → inactive, user doesn't renew), the user can still:

- Log in and view their existing data on the map (read-only)
- Export all their data (GPX / GeoJSON)

They cannot:
- Track new data (OwnTracks, Overland, GPS Logger ingestion is blocked)
- Use any interactive features (trips, stats, search, etc.)

After multiple years of inactivity and multiple email warnings, data will be removed. This respects the "never gate data ownership" principle while ensuring inactive accounts don't consume resources indefinitely.

---

## Pricing Psychology

### Annual-only for Lite

Lite launches as **annual-only at €49/year**. No monthly option.

Rationale:
- Monthly billing on a €4.99 plan creates high churn risk — users try for one month and leave before forming a habit. Location tracking needs weeks of accumulated data before the map becomes meaningful.
- Annual-only increases commitment and reduces early churn.
- Eliminates the "try for one month and leave" segment.
- Simplifies billing operations (one Paddle price ID for Lite instead of two).
- Monthly can be added later as a "by popular demand" move if data shows demand.

Display the effective monthly rate prominently on the pricing page:

> **Lite:** €4.08/mo billed annually
> **Pro:** €10/mo billed annually (or €10/mo billed monthly)

### Price anchoring

The €49/€120 pairing creates natural anchoring. The ~2.4× gap feels proportional to the feature difference and sits in the zone where most users self-select correctly without feeling punished.

### Competitive benchmarks

The €4-5/month zone is the established price point for consumer personal data subscriptions:

- Komoot Premium: €4.99/month
- Life360 Silver: $4.99/month
- Arc Timeline: ~$5/month
- Cronometer Gold: $4.99/month
- Exist.io: $6.99/month

Dawarich Lite at €4.08/mo effective fits naturally in this band.

### Future consideration: adding a third tier

A higher "Family" or "Team" tier (€199+/year) would strengthen the pricing architecture through the compromise effect — research shows three-tier structures convert ~8% better than two-tier, because the middle option (Pro at €120) looks like the reasonable choice rather than the expensive one. Even if few users select the top tier, its presence as an anchor makes Pro more attractive. This is not part of the initial launch but worth planning for.

---

## Upgrade Trigger Map

Every gated touchpoint is a revenue event. Design each deliberately:

| Trigger Point | User Action | Response |
|---|---|---|
| Locked heatmap toggle | Clicks heatmap in map layer panel | 15-30s live preview with user's data, then fade + upgrade card |
| Locked fog-of-war toggle | Clicks fog-of-war in layer panel | 15-30s live preview, then fade + upgrade card |
| Locked globe view | Clicks globe toggle | 15-30s live preview, then fade + upgrade card |
| 11 months of data | Time passes | In-app notification: "Your oldest month archives in 30 days" |
| 11.5 months of data | Time passes | Email: "Keep your full history — upgrade to Pro" |
| Data archived | Oldest month hits 12-month mark | Banner: "N months archived. [Upgrade to Pro]" |
| Archived data on map | Taps semi-transparent archived point/route | Tooltip: "This data is archived — upgrade to Pro to explore it" |
| Public stats sharing | Clicks "Share" on stats page | Modal: "Public sharing available on Pro — share your adventures" |
| Write API attempt | `POST /api/v1/points` | 403 with JSON: upgrade URL and clear message |
| API rate limit hit | Exceeds 200 req/hr | 429 with upgrade URL in response body |
| Immich/PhotoPrism | Attempts integration setup | Redirect to upgrade page with integration highlight |
| Year-in-review (full) | Views limited digest, sees "See full review" | Upgrade prompt with preview of full digest features |

Each trigger should be:
1. **Visible but non-blocking** — never interrupt core functionality
2. **Contextual** — shown at the moment of desire, not randomly
3. **Actionable** — one-click path to upgrade, pre-filled with current plan context

---

## Growth Strategy (54 Customers)

With 54 paying customers and sub-10% trial conversion, the primary challenge is **acquisition and activation**, not cannibalization protection. The Lite plan is a growth tool, not a revenue risk.

### Cannibalization analysis

**Direct cannibalization (existing users downgrading):**
- Worst-case: ~5 Pro users downgrade = -€355/year in revenue
- Mitigated by downgrade friction screen showing concrete losses

**Indirect cannibalization (new users choosing Lite instead of Pro):**
- If Lite captures 60% of new signups, and those users would have otherwise chosen Pro, the opportunity cost per user is €71/year (€120 - €49).
- However, with sub-10% trial conversion, many of these users would not have converted at all at the €120 price point. The Lite plan captures revenue that otherwise wouldn't exist.
- Over 12 months, if 40 new users sign up: 24 choose Lite (€1,176), 16 choose Pro (€1,920) = €3,096 total. Without Lite, if only 20 would have signed up (all Pro): €2,400. Net gain: +€696.
- Even if Lite cannibalizes 30% of would-be Pro users: 12 Lite (€588) + 8 Pro (€960) + 12 new Lite-only converts (€588) = €2,136. Without Lite: 20 Pro (€2,400). Net loss: -€264.
- **Breakeven point:** Lite needs to bring ~4 net-new users per year to offset the cannibalization of each lost Pro user.

At 54 customers, speed of market feedback outweighs cannibalization protection. Launch to all.

### Trial structure (7-day, Pro features)

Keep the current 7-day trial mapped to Pro features. This showcases the full product and creates natural desire to retain access to heatmap, fog-of-war, and unlimited history.

### Plan choice after trial

After the 7-day trial expires, present the plan choice:
- **Default-select the annual Pro plan** (highest revenue, lowest churn).
- Show Lite as an alternative, not as the default.
- Show concrete data from the trial: "During your trial, you viewed the heatmap 8 times and explored 14 months of history. On Lite, the heatmap would be locked and only 12 months would be searchable."
- Offer a "not sure?" path that defaults to Lite with a prominent "upgrade anytime" message.

### Downgrade friction for existing Pro users

When existing Pro users consider downgrading, show them concretely what they'll lose:

- "You have 18 months of data — 6 months will be archived."
- "You've used the heatmap 12 times this month — this will be locked."

Concrete loss aversion is more effective than abstract feature tables. This isn't about blocking the downgrade — it's about making the decision informed.

### Patreon community as launch channel

Announce the Lite plan on Patreon first as a "community preview." Let existing supporters spread the word. They're the most likely source of word-of-mouth referrals and can provide early feedback before broader launch.

### Metrics to track post-launch

Track monthly:

- **Trial-to-paid conversion rate** (overall and per plan) — the #1 metric
- **Plan mix:** What % of new signups choose Lite vs Pro?
- **Upgrade rate:** What % of Lite users upgrade within 3/6/12 months?
- **Downgrade rate:** How many existing Pro users switch to Lite?
- **Revenue per user:** Is total revenue growing even if ARPU dips?
- **Feature engagement:** Which Pro-only features drive the most upgrade triggers?
- **Archival-driven upgrades:** How many users upgrade within 7 days of their first data archival?
- **Preview-driven upgrades:** How many users upgrade after viewing a heatmap/fog/globe preview?
- **Year-in-review sharing:** How many Lite users generate and share review cards?

---

## Technical Implementation Notes

### Development workflow

All Lite plan work must be developed in **separate feature branches** that merge into a `feature/lite` integration branch. Each PR must be an **atomic, independently mergeable** iteration. This ensures:

- Each feature gate can be reviewed and tested in isolation.
- Partial work can ship behind feature flags without blocking other changes.
- Rollback is granular — a single broken feature gate doesn't require reverting the entire Lite plan.
- Multiple developers can work on different aspects in parallel.

**Branch structure:**
```
feature/lite                    ← integration branch
├── feature/lite/plan-enum      ← User model + plan enum + self-hosted bypass
├── feature/lite/api-gating     ← Write API 403 + Read API scoping + rack-attack rate limiting
├── feature/lite/map-layers     ← Frontend layer gating + lock UI + previews
├── feature/lite/data-retention ← Application-level archival filter + archived data rendering
├── feature/lite/archival-jobs  ← Sidekiq warning jobs (11mo, 11.5mo, 12mo banners/emails)
├── feature/lite/insights       ← Limited vs full year-in-review + shareable cards
├── feature/lite/upgrade-ui     ← Upgrade prompts at all trigger points
├── feature/lite/billing        ← Paddle Lite plan + Manager JWT updates + plan selection UI
└── feature/lite/inactive-state ← Lapsed subscription handling (read-only + export)
```

Each branch should be independently deployable (behind a plan check that defaults to Pro for existing users). The integration branch is used to test all features together before merging to `dev`.

### Plan model

Add a `plan` enum to the User model in **both** Dawarich and Manager apps:

```ruby
enum :plan, { self_hoster: 0, lite: 1, pro: 2 }, default: :self_hoster
```

**Three values:**
- `self_hoster` (0) — Default. Self-hosted users get full access with no restrictions. This is also the default for existing Cloud users during migration (set to `pro` via data migration for users with `status: active`).
- `lite` (1) — Cloud Lite plan. Feature-restricted.
- `pro` (2) — Cloud Pro plan. Full access.

**Feature gating pattern:**

```ruby
# In controllers/views
def feature_accessible?(feature)
  current_user.pro? || current_user.self_hoster?
end

# Shorthand for most checks
def pro_or_self_hosted?
  current_user.pro? || current_user.self_hoster?
end

# Example: heatmap layer
def heatmap_accessible?
  pro_or_self_hosted?
end
```

The `self_hoster` plan value replaces the `DawarichSettings.self_hosted?` check for feature gating. Self-hosted instances set the default plan to `self_hoster` at user creation. Cloud instances set it based on the billing plan from Manager.

### Data retention enforcement

The 12-month rolling window requires a background job (Sidekiq) that runs daily:

1. Query points where `created_at < 12.months.ago` for Lite plan users.
2. Flag these points as `archived: true` (or move to a separate partition/table).
3. In map/stats/timeline queries, show archived points in semi-transparent "locked" state (visible but non-interactive).
4. Keep archived points fully accessible via the export endpoint.
5. On plan upgrade to Pro, simply flip `archived: false` for all points (or remove the query filter).

**Implementation options:**

- **Option A — Flag column:** Add `archived boolean DEFAULT false` to points table. Filter in all queries. Simplest to implement, but adds query complexity.
- **Option B — Separate table/partition:** Move archived points to a `points_archive` table or PostgreSQL partition. Cleaner query performance, but more complex migration.
- **Option C — Application-level filter:** No schema change. Filter by `created_at` in application queries based on user's plan. Simplest to ship, instant rollback.

Given the 60GB+ database size, **Option C is recommended for initial launch** (no migration risk, instant rollback), with Option B as a future optimization if Lite plan adoption generates significant cold data.

### Archival warnings (Sidekiq scheduled jobs)

```ruby
# Daily check for users approaching archival
LiteArchivalWarningJob.perform_later
  # At 11 months: in-app notification
  # At 11.5 months: email via Users::MailerSendingJob
  # At 12 months: archive + in-app banner
```

### API rate limiting

Implement per-plan rate limits using `rack-attack` gem with Redis backend (Redis is already in the stack for Sidekiq):

- Lite: 200 requests/hour, keyed by API token
- Pro: 1,000 requests/hour, keyed by API token
- Return `429 Too Many Requests` with `Retry-After` header when exceeded
- Include `X-RateLimit-Limit`, `X-RateLimit-Remaining`, and `X-RateLimit-Reset` headers on all API responses

### Write API enforcement

For Lite plan users, reject requests to write endpoints with `403 Forbidden` and a clear error message:

```json
{
  "error": "write_api_restricted",
  "message": "Write API access requires a Pro plan. Your data was not modified.",
  "upgrade_url": "https://dawarich.app/pricing"
}
```

**Endpoints to restrict for Lite:**

- `POST /api/v1/points` (direct point creation)
- `PATCH /api/v1/points/:id` (point editing)
- `DELETE /api/v1/points/:id` (point deletion via API)
- Any future bulk write endpoints

**Endpoints open on all plans:**

- All `GET` endpoints — scoped to searchable data window for Lite (12 months), full data for Pro
- `POST /api/v1/owntracks/points` — tracker ingestion (separate controller)
- `POST /api/v1/overland/batches` — tracker ingestion (separate controller)
- GPSLogger ingestion endpoint
- Export endpoints (always return full data regardless of plan)

### Read API scoping

For Lite plan users, `GET` endpoints that return point data filter results to the 12-month searchable window:

```ruby
# In API controllers
def scoped_points
  if current_user.lite?
    current_user.points.where('created_at >= ?', 12.months.ago)
  else
    current_user.points
  end
end
```

Export endpoints are NOT scoped — they always return all data regardless of plan.

### Feature gating

Simple plan-level checks for initial launch:

```ruby
# In controllers/views
current_user.pro? || current_user.self_hoster?

# Example: heatmap layer
def heatmap_accessible?
  current_user.pro? || current_user.self_hoster?
end
```

Feature flags (via `flipper` or similar) add value later for A/B testing (e.g., testing whether ungating heatmap on Lite increases or decreases upgrades).

### Map layer gating

In the Map V2 frontend, gated layers (heatmap, fog-of-war, scratch map, globe view) should:

1. Still appear in the layer toggle UI (visible but locked with a lock icon).
2. Show a tooltip: "Available on Pro — click to preview."
3. Clicking a locked toggle shows a **live preview** (15-30 seconds) using the user's actual data, then fades out and shows an upgrade prompt.
4. The preview is purely client-side — the data is already loaded for the map, so no additional API calls are needed.

This creates discovery and desire. Hiding gated features entirely removes the upgrade trigger.

### Billing integration (Paddle)

The current system uses **Paddle Billing** via the `pay` gem in the Manager app. JWT-based callbacks (`Subscription::DecodeJwtToken` / `EncodeSubscriptionToken`) update user `status` and `active_until` in Dawarich. Updates needed:

**Paddle configuration:**
- Create a new Paddle product/price for Lite annual (€49/year).
- Keep existing Pro prices (€10/month, €119.99/year).
- Configure hosted checkout URLs for Lite in Manager env vars.

**Manager app changes:**
- Add `plan` enum to Manager User model (matching Dawarich: `self_hoster: 0, lite: 1, pro: 2`).
- Update `SubscriptionExtensions` to derive `plan` from the Paddle price ID (map each Paddle price to a plan value).
- Update `EncodeSubscriptionToken` to include `plan` in JWT payload:
  ```ruby
  payload = {
    user_id: @user.dawarich_user_id,
    status: @user.status,
    active_until: @user.active_until&.iso8601,
    plan: @user.plan,  # NEW: 'lite' or 'pro'
    exp: 30.minutes.from_now.to_i
  }
  ```
- Add plan selection UI in Manager dashboard (pricing card showing Lite vs Pro).
- Handle plan changes (upgrade Lite → Pro, downgrade Pro → Lite) via Paddle subscription update.

**Dawarich app changes:**
- Add `plan` enum to Dawarich User model.
- Update `Subscription::DecodeJwtToken` consumer to read and store `plan` from JWT payload.
- On upgrade: immediately unlock all features, mark archived data as active.
- On downgrade: schedule feature restriction and data archival for end of current billing period.
- Prorate upgrades via Paddle (credit remaining Lite time toward Pro).

**Data migration:**
- Existing Cloud users with `status: active` → set `plan: :pro`.
- Existing Cloud users with `status: trial` → set `plan: :pro` (trial shows Pro features).
- Existing Cloud users with `status: inactive` → set `plan: :lite` (default for new/inactive).
- Self-hosted instances → set `plan: :self_hoster` for all users (this becomes the new way to check self-hosted status).

### Inactive subscription handling

When a user's subscription lapses (`status: inactive`, `active_until` is in the past):

- **Allow:** Login, map viewing (read-only), data export
- **Block:** New tracking data ingestion (return 403 on OwnTracks/Overland/GPSLogger endpoints), all interactive features

Implementation: Add an `authenticate_active_api_user!` check variant that allows read/export but blocks writes and ingestion for inactive users.

---

## Rollout Plan

### Phase 1 — Build

Each item below maps to a separate feature branch merging into `feature/lite`.

**Core infrastructure (must ship first):**
- [ ] Add `plan` enum to User model in both Dawarich and Manager (migration) — `feature/lite/plan-enum`
- [ ] Implement plan-aware feature checks (`pro?` / `lite?` / `self_hoster?` helpers) — `feature/lite/plan-enum`
- [ ] Data migration: set existing active Cloud users to `pro`, self-hosted to `self_hoster` — `feature/lite/plan-enum`

**API gating:**
- [ ] Add write API enforcement for Lite (403 on general write endpoints) — `feature/lite/api-gating`
- [ ] Scope Read API to 12-month window for Lite users — `feature/lite/api-gating`
- [ ] Implement API rate limiting per plan using `rack-attack` — `feature/lite/api-gating`

**Data retention:**
- [ ] Add data retention archival logic (application-level filter by `created_at`) — `feature/lite/data-retention`
- [ ] Implement archived data visual treatment on map (semi-transparent + lock on tap) — `feature/lite/data-retention`

**Archival warnings:**
- [ ] Add archival warning jobs (11-month notification, 11.5-month email, 12-month banner) — `feature/lite/archival-jobs`

**Map & visualization:**
- [ ] Gate map layers in frontend (lock UI for heatmap, fog-of-war, globe, scratch map) — `feature/lite/map-layers`
- [ ] Implement live preview on gated layer click (15-30s timer) — `feature/lite/map-layers`

**Insights:**
- [ ] Implement limited vs full year-in-review — `feature/lite/insights`
- [ ] Add shareable year-in-review card generation (social media optimized) — `feature/lite/insights`
- [ ] Add referral hook in shared cards — `feature/lite/insights`

**Upgrade prompts:**
- [ ] Add upgrade prompts at all trigger points (see Upgrade Trigger Map) — `feature/lite/upgrade-ui`
- [ ] Gate Immich/PhotoPrism integration, public stats sharing — `feature/lite/upgrade-ui`

**Billing:**
- [ ] Set up Lite annual plan in Paddle — `feature/lite/billing`
- [ ] Update Manager to include `plan` in JWT callback — `feature/lite/billing`
- [ ] Update Dawarich to decode and store `plan` from JWT — `feature/lite/billing`
- [ ] Add plan selection UI in Manager dashboard — `feature/lite/billing`
- [ ] Handle upgrade/downgrade flows — `feature/lite/billing`

**Inactive state:**
- [ ] Implement lapsed subscription handling (read-only + export) — `feature/lite/inactive-state`
- [ ] Block tracking ingestion for inactive users — `feature/lite/inactive-state`

### Phase 2 — Test

- [ ] Internal testing on staging with all three plan types (self_hoster, lite, pro)
- [ ] Verify data archival correctly shows semi-transparent archived data on map
- [ ] Verify archived data tap/click shows upgrade tooltip
- [ ] Verify live preview on gated layers (15-30s timer, fade, prompt)
- [ ] Verify archival warnings fire at correct thresholds (11mo, 11.5mo, 12mo)
- [ ] Verify API rate limits (rack-attack) and write API enforcement
- [ ] Verify Read API returns only 12-month window for Lite users
- [ ] Verify export endpoints return ALL data regardless of plan
- [ ] Verify all gated features show appropriate locked state with upgrade prompts
- [ ] Verify upgrade/downgrade flows in Paddle billing
- [ ] Verify self-hosted users have `self_hoster` plan and bypass all checks
- [ ] Test edge cases: user at exactly 12 months of data, plan change mid-billing cycle
- [ ] Test downgrade flow: verify data archival scheduled for end of billing period
- [ ] Test inactive state: verify read-only access + export + blocked ingestion
- [ ] Verify year-in-review card generation and sharing for both plans

### Phase 3 — Launch

- [ ] Update pricing page with two-plan comparison (EUR only, effective monthly rate displayed)
- [ ] Update onboarding flow to present plan choice after 7-day trial (Pro default-selected)
- [ ] Add downgrade friction screen for existing Pro users (concrete loss display)
- [ ] Announce on Patreon first (community preview), then changelog and blog post
- [ ] All plans available to new and existing customers from day one
- [ ] Monitor signup volume, plan split, and conversion metrics

### Phase 4 — Observe

- [ ] Track all metrics from Growth Strategy section (including preview-driven and card-sharing metrics)
- [ ] Collect qualitative feedback on feature gates (too restrictive? too generous?)
- [ ] Evaluate whether a third tier (Family/Team) is warranted
- [ ] Evaluate whether monthly billing should be added for Lite based on demand
- [ ] Adjust retention window if data shows misalignment
- [ ] Monitor inactive account data and refine multi-year cleanup policy

---

## Resolved Questions

1. **OwnTracks/Overland/GPSLogger write paths:** Confirmed — these use separate namespaced controllers (`Api::V1::Owntracks::PointsController`, `Api::V1::Overland::BatchesController`) independent from the general write API (`Api::V1::PointsController`). Tracker ingestion is open on all plans. Write API restriction on Lite only blocks the general `POST/PATCH/DELETE /api/v1/points` endpoints.

2. **Point cap:** Not a user-facing restriction. The existing 10M internal hard limit stays as an infrastructure safeguard. Users approaching the limit will be contacted directly. No cap-based upgrade triggers or FIFO auto-archive.

3. **Trial plan mapping:** 7-day trial mapped to Pro features. Showcases the full product and creates natural desire to retain access to advanced features.

4. **Annual-only for Lite:** Yes. Lite launches as €49/year with no monthly option. Monthly may be added later based on demand.

5. **Speed-colored routes:** Available on Lite. Not a Pro-only feature.

6. **Legacy Map V1:** Deprecated. Not offered to new users on any plan. Will be removed in a future release.

7. **Family sharing on Cloud:** Not available on any Cloud plan. Self-hosted only for now.

8. **Inactive subscription state:** Users retain read-only map access and export capability. Tracking ingestion is blocked. Data removed after multiple years of inactivity with warnings.

9. **Read API scoping:** Lite Read API returns only data within the 12-month searchable window. Export endpoints always return full data.

10. **Payment provider:** Paddle Billing via `pay` gem. Not Stripe.

11. **Plan enum values:** `self_hoster` (0), `lite` (1), `pro` (2) — used in both Dawarich and Manager apps.

## Open Questions

1. **Self-hosted parity:** The self-hosted version has all features with no restrictions. This is fine and expected (self-hosters pay with their own infrastructure and time), but the pricing page should acknowledge this clearly to avoid community friction.

2. **Existing subscriber communication:** Frame as "we added a lighter option for people who want less" rather than "here's a cheaper version of what you have." Emphasize that Pro gained new exclusive features (full year-in-review, public sharing) rather than lost features to a cheaper tier.

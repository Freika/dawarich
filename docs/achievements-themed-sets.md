# Thematic country collections

The thematic part of the six-series achievement expansion (see `achievement-collections.md`): Benelux (BE/NL/LU),
Baltics (EE/LV/LT) and Scandinavia (DK/NO/SE). Each collection requires visits
to all three countries. It does not require completing their subdivisions.

## Definitions and credit

`config/achievements.yml` defines `thematic_set` entries with explicit country
memberships and stable, versioned keys (`thematic_benelux_v1`,
`thematic_baltics_v1`, `thematic_scandinavia_v1`). Future changes to a theme's
membership should use a new versioned key instead of redefining an earned set.
The three existing world tiers remain hidden.

The shared country-dwell calculation and disputed-area policy are unchanged.
`RegionSetChecker` awards a theme from its member country codes; completing a
country's subdivision set is a separate achievement. Theme child cards show
binary visit status and visit dates, while country detail pages continue to
show their subdivision progress. The set completion date follows the last
member's stored visit date, in the user's timezone, as in existing collections.

Migration `20261028110000` enqueues a silent, forced `BulkCheckJob` for eligible
users, including users whose exploration calculation is already current.
Existing earned country codes suffice; no forced history rebuild is requested.
New completions use the existing notification and unlock-deck mechanisms;
silent backfills create no notification or deck event. Existing awards retain
their current non-revocation behavior.

## Collection and artwork

The main page has a thematic section, and desktop/mobile navigation links each
theme. Details reuse existing search, pagination and sharing controls. The
status selector has visited/unvisited outcomes through the existing
unlocked/locked filters; there is no subdivision-based in-progress filter.
The visit criterion is explained beside the collection progress.

Theme silhouettes use one regional coordinate frame. Visited countries retain
the Spectral material; unvisited members have a dark fill and visible outline.
The fallback SVG, hydrated material, enlarged card and OG image preserve this
distinction. Regional artwork framing excludes distant possessions without
changing country membership or visit credit. Missing boundaries remain absent.

All new labels are included in the seven existing achievement locales.
Sharing remains private until explicitly enabled, and uses the existing
per-user public-link enable/disable controls.

## Verification

Relevant Ruby coverage: achievement request suites, service suites and
`spec/migrations/enqueue_thematic_achievements_backfill_spec.rb`.
`npm test` covers the material overlay and preservation across card hydration
alongside the existing JavaScript regression suite. Browser verification uses
synthetic earned dates and public country boundaries in a separate local DB.

The broader product proposal is
`/Users/frey/projects/dawarich/docs/plans/2026-10-28-achievement-series.md`.
Its AFFiNE counterpart is **Dawarich — Achievement card expansion ideas**
(`Xb6wLAA41QcZPRS2Y6IqE`). H3 cities, returns, seasons, nature and geographic
milestones are subsequent work; this change introduces only thematic sets.

# Phoenix geocoding response cache

Phoenix `Dawarich.Geocoding.Search` stores raw provider response bodies through
`Dawarich.Geocoding.ResponseCache` in the existing application-owned `TtlCache`.
The key is `{Dawarich.Geocoding.ResponseCache, Query.build/4's cache key}`.
Entries expire after 86,400,000 monotonic milliseconds. Hits retain the deadline;
empty or nonbinary values are misses. Statuses 200–399 are stored before decoding,
including invalid JSON and provider-error bodies. HTTP 404 still decodes valid
features without caching; configured HTTP errors and timeouts remain uncached.

The table's existing 10,000-entry bound covers all TtlCache consumers. Its eviction
can cause earlier misses. Each BEAM node has an independent population; Rails and
other nodes cannot warm it. No cache migration or dual write occurs. ED-385 and
ED-386 in `app-phoenix/parity/expected_diffs.md` record those two differences.

Every enabled, complete lookup still passes through the shared Redis provider
reservation limiter, including cache hits. Rails' `GEOCODING_SHARED_RATE_LIMIT`
claim prerequisite remains in force. Query construction, provider decoding,
point/place writes, worker registry and `claimable: false` settings are unchanged.

Existing `DAWARICH_RAILS_ROUTES` and `DAWARICH_RAILS_SLICES` continue controlling
route hand-back. This internal cache change adds no route key and activates no
geocoding or visit worker. Handed-back Rails work uses Rails' own Geocoder cache;
it may be cold relative to native work. A native node restart likewise begins
with a cold response population. Both owners retain provider pacing.

## Retained Redis families and retirement owners

Inventory IDs below follow the implementation plan
`2026-10-03-phoenix-a13-remaining-redis-plan.md` in the shared plans directory.
That plan retains exact source/caller lists and follow-up ordering.

| Family | Remaining authority and retirement owner |
|---|---|
| X-L / L | Rails/Phoenix provider reservations: separate bilateral limiter plan before Redis removal. A13c counter windows do not replace future microsecond slots. |
| X-C1–6 | RailsCache interoperability, registration auth/admin/public-home readers and native admin writer, country maps, digest snapshots and fragments: A12d1 cache/page owners; registration T6 switches all readers and Rails/native writers with A5/A11/A13d after one-shot carry. |
| X-B / R5 | Cable PubSub and Rails ActionCable/Turbo producers: A12a producer closure and A13e transport/coexistence decision. |
| X-Client | Command/cache Redix children, Cable clients, dependency and runtime environment: A13f after all consumers retire. |
| R1–3 | Sidekiq queues, cron, retries/dead state, limit_fetch and idle-queue probes: A12d3 owned-job closure/drain. |
| R4 | Rails RedisCacheStore and its T/P callers: owning route/job waves and A12f Rails retirement. |
| R6 / P14 | Rack-attack counters already use PG, but Rails API-token plan lookup still uses Rails.cache: retire with Rails. |
| R7 | Rails Geocoder cache: retained for Rails-owned reverse-geocoding work until its worker/caller retirement. Only Phoenix response GET/SET retire here. |
| R8 | Rails settings notifier PubSub, including Phoenix Admin.InstanceWrites publishing to `dawarich:instance_settings`: retire the coexistence publisher with Puma/Sidekiq processes. |
| R9 | Sidekiq Redis readiness PING: native worker/readiness replacement at A12f/A13f. |
| K1; K2, K5–7, K11–12 | Rails rolling-upgrade lock/claim fallbacks: A13b PG authorities already exist; A12 owners close legacy jobs/callers before deletion. |
| K3–4 | PG geocoded days/cursors already exist; Rails fallback and geocoded-day Redis drain remain until legacy migration/ownership closes at A12d1. |
| K8–9, K13 / T10 | Track range/backoff, session/progress counters and transport event claims: A12d2 algorithms/jobs and tracks UI/API owners. |
| K10 | Achievement pending-check fallback: native revision rows exist; retire Rails caller after its owner switches. |
| T1–4 | Single-use OTP/link/destroy/trial claims, including Phoenix Trial.Welcome consuming Rails-compatible Redis claims through WelcomeClaim: A11/A13d shared authority or route retirement. |
| T5–8 | Manager replay watermark (A4/A13d), registration (A5/A11/A13d), daily import quota (A7/A13d), recalculation/anomaly gates (A12d1/A13d): explicit carry/reset and paired writers/readers. |
| T9, T11–12 | Trip fan-in (trip owner/drain), tile epochs (A6/A13d), mail throttles (A11/A12e/A13d): retain shared correctness authorities. |
| T13–16 | Raw restore values (A12h), boot cache jobs/version banner (A12d1/app_version), permanent poster enqueue claims (A12 poster owner), family mail enqueue claims (A12e mail/bridge). |
| P1–2, P9, P16 | Stats, digest snapshots, countries and ERB fragments/preheat: A12d1 owners with key/version/locale parity. |
| P3–8 | Timeline (visit/timeline invalidation), photos/preview tokens and shared fingerprints (photo/sharing owners), nearby provider results (places), silhouettes/OpenGraph (achievements), trip-day stats (trips). |
| P10–13 | Poster themes (poster page), import downloads (import owner), plan/quota flags (quota authority), supporter lookups (remaining caller retirement). |
| P15, P17 | Ruby DNS initializer (Rails retirement) and AppleID JWKS refresh/validation cache (A11 OAuth owner). |
| Operator/test helpers | Existing registration/country seed helpers switch when their authority changes. |

The slice removes exactly Search's two Redis wrapper calls. Other consumers,
including the integration's registration writer, welcome claims and settings
publisher, plus direct Cable Redix operations remain. All Redix clients and Rails
adapters remain.
Final A13f removal follows A12f, one stable release, and A13e's Redis exit.

## Verification and release boundary

The unchanged tracked Rails corpus is verified by the existing oracle in default
mode. Named real-gem empty-body/status/timeout examples make two calls and pin raw
cache contents. ExUnit uses real ETS and the existing FakeHttp recorder to check
bytes, TTL, eviction, query identity, limiter ordering and Redis independence.
Existing resync/seedrun scripts and relevant Rails specs remain the local gates.
Browser stands, images, worker activation and release/upgrade checks are deferred
to the controller mini lane; these tests grant no Redis service retirement.

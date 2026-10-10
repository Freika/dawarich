# Native milestone 5 prerequisite baseline and contract handoff

Date: 2026-10-10. Governing plan: approved native milestone 5 plan. App source
`5d3f135f534e39833d73105fda7850cb34358761`; E2E source
`ff256e6fd6a8a50f3f05a9e5a1e9656ef5a47b2d`. No runtime implementation is
delivered by this document. C0 is complete under the controller task transfer
of 2026-10-10 11:40. The measurable baseline is retained below; integration
switches and native map activation remain explicit later tasks.

## Approved product defaults

- Independent Points, Stats index/year, Insights and Digests may activate
  before maps. Trips list/form/detail, Stats month and public map routes wait
  for milestone 6 native hosts. Keep their current maps and external callers.
- Preserve 50 Points rows, six owned/six family Trips cards, source timestamp
  tie ordering, owner-local windows, source casts and Lite admission. New
  timeline cursors require lossless tie tests; never truncate an existing API.
- Timeline queries cover at most 31 days, with proposed native row windows of
  100 and retained client windows of 200. Full-range aggregates remain separate
  from cursor pages. Existing Visit bulk selection stays capped at 500.
- Charts retain at most 366 daily or 12 monthly buckets per series; heatmaps
  retain at most 366 cells. Native data cache values have a 1 MiB admission
  cap, with bounded read/paging fallback rather than truncation.
- Summary/month/count TTL remains 24 hours; persisted patterns/day TTL remains
  one hour. Keys include owner/resource, schema/calculation version, input
  revision, zone/unit and locale when localized. Public keys also include
  audience/privacy/share revision; authorize before access and delivery.
- Cold/stale analytics show ready totals and last-ready data with pending,
  retry and failure states. Projection tasks are read-only. Durable automatic
  refresh never sends manual digest mail.
- Every async read run has a 10-second tokened timeout. Timer/result matching
  includes kind, generation, run reference and normalized-filter fingerprint.
  Retry replaces its run reference; cancellation stops only that run.
- Public persisted documents remain HTTP. The authorized direct Insights
  details URL remains supported. Data refusals never redirect to themselves.

## Library and rich-storage baseline

Native assets currently declare only emoji data, emoji-mart and spark-md5.
Neither the chart stack nor Trix is currently a native npm dependency.
`config/importmap.rb` resolves the legacy chart stack to vendored scripts.
Their actual headers identify Chartkick.js **5.0.1**, Chart.js **4.5.1**, and
date-fns adapter **3.0.0**. The Ruby Chartkick gem is **5.2.1**; that is not
the browser vendor version. The ActionText Trix gem is **2.1.19**, and the
root JS manifest requests Trix `^2.1.19`. No package upgrade is authorized.
C2 must preserve the actual current chart values/library behind a lazy
adapter; B4 must use Trix alone without ActionText/ActiveStorage JavaScript.

ActionText/ActiveStorage storage stays canonical. New upload claims bind to
actor receipts; existing embeds on the owned description survive re-edit.
RichContent's existing 2 MiB body and depth-64 limits remain. They are not
upload-file budgets. A synthetic three-PDF corpus was exercised with 1–3 KiB
blob metadata and safe rendered-size/query measurements. No real storage
corpus or source rich-upload maximum was supplied: no new file/count/type
restriction is frozen from those tiny fixtures, and M4's archive limits must
not be copied into rich attachments. Further corpus-based upload limits remain
an explicit B3/M4 integration item; stored descriptions must never be truncated.

## Shared ownership and missing integrations

| Owner | Responsibility | Current state on this branch |
| --- | --- | --- |
| M5 C/controller | C1 DataAccess, NativeDataAuth and DataAsync; C2 charts; route/build/register hot files | Proposed modules absent |
| Assigned A | Points Pages/read UI/actions and Visits timeline/commands | Wait for C1; export events also need M4 |
| Assigned D | Analytics Pages, durable refresh, data cache, Stats/Insights/Digests UI | Wait for C1; chart UI also needs C2 |
| Separate B | Trips/editor tasks | Wait for completed C0 handoff and C1/C2 |
| M4 X | Shared sanitized principal and fresh lifecycle admission | Contract document inspected; implementation not present here |
| M4 A/B/C | Uploads; Exports/Notifications; Families/Sharing | Planned scoped APIs, not integrated implementations |
| M6 | Native map hosts, cookie-auth API and timeline browser host | Approved plan inspected; no host readiness delivered here |

M4's inspected handoff defines `Uploads.reserve/target/claim/cancel`,
`Exports.page/request/delete/subscribe`, `Notifications.page/open/mark_all_read/
delete/unread/subscribe`, and `Sharing.page/change`, all taking account Scope.
Publication shape is `{:domain_changed, owner_or_resource_id, version_or_kind}`:
IDs, versions and closed kinds only. Subscribe before snapshot; re-admit on
every delivery and reconnect. Upload targets are transient authenticated HTTP
responses; LiveView upload metadata carries only uploader and upload reference.
These signatures describe the M4 handoff and do not assert those functions
are callable on this branch.

Existing callable boundaries include `PointExports.parse/1`,
`PointExports.create/4`, `Storage.UploadReceipts.bind!/3` and `owned?/3`,
`SharedLinks.FamilyAudience.trips/3`, and separate Stats/Digests sharing
contexts. They do not substitute for the required shared principal/scoped
M4 facade. Existing `Accounts.Scope` contains user/locale; NativeAuth assigns
it once. Admin.Access supplies a feature-specific original-identity check,
but importing admin-only admission into ordinary data pages is prohibited.

## Dependency adapters

The controller task transfer assigns C1/C2 to this implementer. M4 owns the
shared sanitized principal/proof API and scoped facades, frozen in
`native-m4-contracts.md` at `09a01685a`. That document fixes semantics but
contains no concrete principal function names. One M5 dependency adapter
isolates the current callable functions; the controller replaces its
implementation when M4 merges. No independent session or upload subsystem.

- `Dawarich.NativeM5.Dependencies.principal(scope)` captures actor ID, locale
  and an opaque server-issued identity fingerprint. It delegates identity
  comparison to the existing Accounts/session identity semantics, retaining
  neither the password hash nor its salt in the principal. Principals are
  server-private, have redacted inspection, and never become browser assigns,
  telemetry labels or event replies.
- `Dependencies.admit(principal)` reloads through `Accounts.get/1`, verifies
  the original identity, then rebuilds the existing `Accounts.Scope`. C1's
  DataAccess applies operation-specific settings/active/entitlement rules.
  Full users stay local to synchronous context calls, never async arguments.
- `Dependencies.request_point_export(scope, params, request_id)` consumes
  existing PointExports parsing/publication with server admission/dedupe at
  the native command boundary until M4 Exports.request replaces it.
- Sharing delegates to existing Stats/Digests scoped-owner operations after
  fresh native admission until M4 Sharing.change replaces it. Upload claims
  remain B3's consumption of the existing owned receipt functions until M4.
- Family audience continues through FamilyAudience; M6 native timeline,
  preview, month and public-map hosts remain X1 activation dependencies.

C1 publishes the small async contract `{kind, generation, run_ref,
normalized_filter_fingerprint}`. Tasks receive only a private principal and
normalized scalar owner/resource/period/window/revision inputs. Each task and
its delivery re-admits independently; params replace the generation, cancel
all active runs/timers, and retry replaces run_ref. A timeout never owns a
replacement run. Default timeout is 10 seconds.

Admission-inclusive query accounting permits one actor reload per hook or
context boundary, plus measured entitlement/settings/target reads; no generic
blanket allowance. Page-volume slope must be constant; new projections perform
no heavy calculation or persistence. Approved 50/6 page sizes, 100-row cursor,
200 retained rows, 366/12 chart buckets, 1 MiB cache and 2 KiB eager adapter
stub limits are adopted from the controller defaults. Corpus-based attachment
limits and accurate whole-route browser wire/idle retention measurements move
to their B3/X4/X5 integration tasks; preliminary invalid probes remain excluded.

Refusal table: stale identity goes fully to sign-in after clearing private
state; missing/foreign detail returns proper 404 or its source collection
alert; insufficient entitlement renders the source locked state without
private data; invalid query stays as bounded validation/source default;
unavailable projection offers a generic retryable alert. The web layer owns
translations and destinations; domain contexts return closed typed errors.

Durable refresh identity includes actor/resource, period, input revision and
calculation/settings version. Reuse existing outbox/processed machinery, but
do not call manual Digests.Generation unchanged for automatic refresh: its
published state is period-based and its successful generation publishes mail.
D2 must prove revision-sensitive receipts and mail separation before choosing
whether the existing receipt tables suffice. C0 does not invent a migration.

## Populated domain measurements

All rows are synthetic. Repo telemetry includes the measured call's SQL and
transactions, excludes fixture insertion, other repositories, Redis, storage
network and workers. First-row initialization affects the Points one-row
reading. These figures are observations, not post-migration total-query caps.

| Read | Queries | Writes | Serialized result bytes |
| --- | ---: | ---: | ---: |
| Points one row | 12 | 0 | 1,353 |
| Points 50 of 51 rows | 11 | 0 | 17,131 |
| Points with 61 import options | 11 | 0 | 29,205 |
| Trips one card | 12 | 0 | 493 |
| Trips six cards | 62 | 0 | 2,178 |
| Trips six of 21 cards | 62 | 0 | 2,178 |
| Family six of seven cards | 14 | 0 | 1,698 |
| Timeline one visit | 5 | 0 | 921 |
| Timeline 101 tied visits on Berlin DST day | 5 | 0 | 63,824 |
| Full-month calendar including those 101 visits | 4 | 0 | 6,682 |
| Insights missing stats | 6 | 0 | 518 |
| Insights cold persisted patterns | 51 | 4 | 4,069 |
| Insights ready persisted patterns | 8 | 0 | 4,069 |
| Insights stale persisted patterns | 47 | 2 | 4,069 |
| Cold point counts | 8 | 2 | 34 |
| Ready point counts | 2 | 0 | 34 |
| Rich rendering one PDF | 2 | 0 | 895 |
| Rich rendering three PDFs | 6 | 0 | 2,661 |

Timeline uses explicit zoned start/end bounds on 2026-03-29, not the old
inventory's unsupported `date` shorthand. The separate calendar assertion
counts all 101 visits. Family fixtures include two real synthetic memberships
and seven live family links. Attachment measurement emits neither bodies nor
signed identifiers.

Points static/connected/params Repo counts are **29/15/14**. Ordinary render
observes zero SQL. After patching to page two, serialized socket assigns are
**3,228 bytes**, and owned LiveView process memory is **264,176 bytes**. This
is one snapshot, not long-lived retention or browser memory. The older root
still contains its existing sensitive actor fields; no native privacy fix is
claimed from a small serialized-size measurement.

## Build graph and verification

Production-configured minified esbuild graph: eager **167,238 raw / 51,397
gzip bytes** over app.js and its static shared chunk. Lazy outputs are emoji
module **77,332**, native emoji library **434,064**, demo **3,694** and style
**616** bytes. Neither chart nor Trix is in this native graph yet. The proposed
C2/B4 stub allowance is at most 2 KiB added eager code per adapter, subject to
a recursive-metafile check. Unrelated
shared M4/M6 changes must be itemized separately. This graph is not the
loaded legacy M5 page graph.

Six temporary named measurement tests: RED **0/6**, counter-disabled mutation
**0/6**, GREEN **6/6**, restored targeted batch **66 passed**, seed 404,
warnings-as-errors and exit 0. Temporary source is retained in the external
implementation report and removed from the application test tree. No source
behavior test or fixture was deleted. The controller transfer resolves C0 after these
measurement controls and the dependency boundaries above are recorded.

Browser observations, exact command exits, excluded probe attempts and
remaining handoff items are recorded in the implementation report. No full
suite, RSpec, remote service or lifecycle-guard change belongs to this work.

## Rails bugs fixed (changelog)

none. Query slopes, inline calculation and pre-existing page overflow remain
baseline observations; no Rails defect is fixed by this documentation.

### Implemented Points and Visits read contracts

`Points.Pages.load/3`, `selection/4` and `address/2` take fresh Scope; `Points.Commands.delete/4` and `request_export/5` re-admit under the owner lock. `NativeM5.Dependencies.request_point_export/4` delegates to current PointExports.create with a receipt in the existing outbox; M4 switches this adapter to its export facade.

`Visits.Timeline.load/3` returns bounded `rows` (100), full-range `days` summaries/bounds, `calendar`, `window`, `revision`, `next_cursor`, `stream_limit` (200), `reset` and `restricted`/`redetected` state. `calendar/3` supplies the scoped 42-cell month independently. Cursors bind actor, normalized window, zone and entitlement state; source visit ties use descending ID and tracks retain ascending ID. M6 owns stream/client DOM bounds and route activation. Existing Timeline.Api, MapFrames and VisitStreams retain complete legacy responses until their caller migration.

`Visits.Commands.update/4`, `delete/3`, `bulk_update/3`, `bulk_delete/3` and `merge/3` take Scope and optional now/hosting context. They return `{:ok, %{ids, days, month_revisions, notice, bindings}}` or typed errors. Each operation re-admits under the actor lock, then shares the existing WebUpdate/Delete/Bulk/Merge rules and transactional effects. Selection is capped at 500; invalid bigint IDs refuse before writes. M6 uses returned local days/month revisions to invalidate/reset its window. Legacy HTTP/frame adapters retain the shared Web* rules and original transport until M6 activates its event callers; no transport handler removed in A5.

### Native analytics read contracts

`Stats.Pages.index/3`, `year/3` and `month/3`, `Insights.Pages.overview/3` and `details/3`, and `Digests.Pages.index/3` and `get/3` re-admit Scope and return typed data/errors. Analytics.Period normalizes source Ruby casts, friendly owner zones, units and Lite windows. Projections omit credentials, provider metadata, sharing UUIDs and raw user settings. Index cards/Digest collections page at 50; charts retain source monthly buckets and peak-day bounds. Cold counts and stale/missing patterns return pending without calculation. Restricted and all-time Insights do not query patterns. Existing HTTP/API projection callers retain their source protocol until their activation task. Native command boundaries are completed with D4/D6; revision refresh and cache contracts are D2/D3.

### Automatic analytics refresh

`Stats.PageRefresh.request/4` and `retry/4` take fresh Scope, a server-selected `:insights` or `:counts` resource and normalized page parameters. Restricted/all-time patterns are not requested. Existing Oban jobs, persistent once claims, cursors and processed receipts encode the revision; no new table or receipt framework. Safe client status contains state/receipt/revision; internal job arguments also carry only the actor ID, normalized calculation fields and one-way original identity fingerprint. Never assign internal arguments to a page. Revision includes input stats, owner epoch, settings/calculation version, zone/unit and one-hour pattern or one-day count bucket. Native subscribers re-admit at result delivery; workers re-admit before calculation and atomic persistence, compare current input, then broadcast an owner-scoped ready notification. Automatic refresh uses CalculateMonth/Year attributes and Store without Generation's period-only publication/mail path. Existing manual digest workers are unchanged. Trip day commands retain the B-owned durable interface.

### Native data cache contract

`Cache.Pages.fetch/5` takes Scope/principal, server resource, normalized parameters, an admitted bounded ready reader and internal adapter options. It re-admits before GET, before delivery and before/post SET. Keys bind schema, owner identity, resource/period, input/ready revisions, zone/unit/locale, entitlement and private/public audience. Public consumers must supply a live authorization callback; booleans and missing callbacks refuse, including warm reads. C5 supplies its M4 facade callback at integration. Payloads are data only, at most 1 MiB, no compressed or unsafe external terms, credentials, user/settings/proof, functions or unknown atoms. Summary/count cache lifetime is 24 hours; patterns/day one hour. Oversized entries and adapter/TTL errors bypass; corrupt entries fall back to the bounded domain read. Pending/failed projections bypass to expose completed durable work. Writes inside a DB transaction are bypassed unless an internal after-commit scheduler is supplied; delayed writes compare the current input again. Historical Rails codecs/readers/preheat workers keep their existing consumers.

### Native Stats UI and commands

`Stats.Commands.update/4` takes the original Scope/principal, optional period, server receipt and internal clock/hosting options. It re-admits under the actor lock, binds receipts to normalized source periods, and queues the existing full or monthly producer. A failed transaction remains retryable. `share/4` requires current active/full eligibility and the source 1h/12h/24h policy, delegating through `NativeM5.Dependencies.share_stat/5` to the current sharing implementation for M4 to switch. Upgrade URLs are generated on action, outside retained page state.

Stats index/year are native data-session routes. Stats month has a native query/render/action slice tested directly; its route stays with the existing map page until M6 activation. Index year cards and place dialogs fetch at most 50 rows, keep full aggregate counts, and use explicit URL pagination. Pending point counts request one durable refresh and owner-scoped completion re-reads current parameters. Numeric chart changes renew the library revision within the same selected year.

### Native Insights lifecycle and residency

`InsightsLive.NativePage` owns both `/insights` and `/insights/details` in the native data session. Cheap overview reads preserve source period/totals/heatmap and URL-driven year/month; connected details and residency reads have independent generation/run timers. URL changes cancel both; retries renew only the selected run. Delivery re-admits original identity, current entitlement, cutoff, zone and unit before applying data. Owner-scoped durable refresh completion re-reads the currently selected parameters; reconnect consumes the persisted result without new calculation. Restricted/all-time reads never load full patterns or residency.

`Insights.ResidencyPage.load/3` admits Scope and bounds country rows at 50 with explicit `residency_page` navigation. Full distinct UTC days are counted inside source owner-local year bounds; source dominant-country ties, first-country order, flags, year percentages, 183-day warnings and consecutive periods remain. The annual accessible calendar is bounded by the selected year. `Insights.MonthProjection` narrows source first visits/top locations/comparisons and computes country names outside rendering; native monthly chart uses numeric weekly buckets. Historical map residency frames, API readers and Rails fragment codecs keep their existing callers until the M6/X2 census.

### Native persisted Digest pages and actions

`DigestsLive.NativePage` serves `/digests` and `/digests/:year` in the native data session. Reads do not enqueue or calculate. Persisted source values, title/locale, current-year list exclusion and Lite summary-only columns remain. The page projection retains full country/city/first-visit counts while windowing countries and first-country names at 50, first-city names at 10 and time rankings at five; explicit URL pagination preserves full chart values and progress denominators. Source numeric-string all-time distance uses the original integer cast. Full pattern columns are never selected for Lite.

`Digests.Commands.generate/4` re-admits identity/settings, active/tracked-year/cutoff policy under the actor lock, refuses current/future years and publishes the existing `digests.calculate_year` outbox command with its source producer/worker mail policy. The server request receipt and normalized year share one persistent claim in the same transaction; failed publication rolls back the claim and explicit retry is accepted. `delete/3` selects only the owned yearly digest; native confirmation is tied to the displayed year and resets on navigation/cancel. Missing/foreign reads redirect to `/digests` with the original alert; command errors stay in place. `share/4` preserves current active/source eligibility and 1h/12h/24h expiration via the thin M4 dependency adapter. Opening/reopening the dialog is a read; changing its public settings auto-saves. Public capability links are the intended dialog output; identity/settings/credentials stay out of assigns. Upgrade URLs are generated only on action. Historical HTTP/API/manual-generation/mail/public-share adapters keep their consumers until the controller's X1/X2/M4 integration census.

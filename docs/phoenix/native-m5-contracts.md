# Native milestone 5 prerequisite baseline and contract handoff

Date: 2026-10-10. Governing plan: approved native milestone 5 plan. App source
`5d3f135f534e39833d73105fda7850cb34358761`; E2E source
`ff256e6fd6a8a50f3f05a9e5a1e9656ef5a47b2d`. No runtime implementation is
delivered by this document. C0 remains open until the shared admission and
integration handoff below is resolved. This is baseline evidence, not a
completed-task SHA for the Trips implementer.

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
an explicit C0 handoff item; stored descriptions must never be truncated.

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

C0 must receive or explicitly obtain ownership to implement C1/C2, settle
one shared M4/M5 principal API, and identify the accepted M4 prerequisite
commits before A/D migration. Do not create independent proof/session/upload
contexts to bypass that handoff. No merges or changes to another feature
worktree are authorized by this document.

The shared read contract needs small immutable actor/resource identifiers,
normalized scalar period/window/zone/unit/revision, and a server-issued opaque
identity proof. No User/socket/assigns closure, password hash/salt, API key,
provider settings, phrase or upload capabilities in task names, telemetry or
generic serialized state. Fresh admission must rebuild the current Scope
inside the task and again at delivery; the precise shared proof API is still
a controller integration item.

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
the outstanding controller handoff and a recursive-metafile check. Unrelated
shared M4/M6 changes must be itemized separately. This graph is not the
loaded legacy M5 page graph.

Six temporary named measurement tests: RED **0/6**, counter-disabled mutation
**0/6**, GREEN **6/6**, restored targeted batch **66 passed**, seed 404,
warnings-as-errors and exit 0. Temporary source is retained in the external
implementation report and removed from the application test tree. No source
behavior test or fixture was deleted. C0 is not complete merely because these
measurement controls pass.

Browser observations, exact command exits, excluded probe attempts and
remaining handoff items are recorded in the implementation report. No full
suite, RSpec, remote service or lifecycle-guard change belongs to this work.

## Rails bugs fixed (changelog)

none. Query slopes, inline calculation and pre-existing page overflow remain
baseline observations; no Rails defect is fixed by this documentation.

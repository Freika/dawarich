# A12f-3b native route integration

H01 mounts the merged FAMILY, SHARES and POSTERS seams. `DomainRoutes` declares the family form routes before invitation tokens, gives family pages their own LiveView session with LiveAuth followed by FamilyGate, and mounts track, timeline and supplemental share revoke routes after the share form pipeline. Router changes are limited to imports and macro calls. Existing page declarations remain mounted once; this does not activate the later ADMIN or TRIALHOME packages.

The family form dispatcher retains formatted paths and effective form methods. During coexistence, invitation creation hands back before body consumption when its native mail leaf is source-owned or unreadable. The producer still locks ownership inside its transaction. Standalone operation returns native failures for unavailable leaves; this integration does not change worker ownership or certify delivery readiness.

FamilyRequestAdmission checks malformed query/form percent escapes, body types, override headers and incompatible effective form routes before writes. It retains the original raw body for Rails replay and supplies that same body to the family's existing parser. Compatible overrides still reach native actions. Route snapshot tests assert the dedicated family session and hook order; sharing endpoint tests retain byte-exact replay for incompatible overrides and assert native deletion for accepted DELETE overrides.

Share forms use ShareManagementForm admission after Body and RailsAuth, preserving raw POST replay, JSON support and permitted PATCH/DELETE overrides. Poster forms use PostersGate for authenticated and guest outcomes. Standalone sharing admits Cloud requests and authenticated/family viewers to the existing native handlers; FamilyAudience remains the authority for access. Public HEAD uses GET status and headers with an empty body. Coexistence transport gates and route pins remain in force before effects.

`test/dawarich/a12f3b_h01_test.exs` covers unique executable declarations, literal invitation precedence, native family create/update, all six track/timeline actions, mounted poster create/delete, sharing HEAD, exact pinned method/body/cookie replay with unchanged SQL, source-owned invitation mail handback, validation/CSRF refusals, standalone Cloud pages/actions and family-audience denial. H01a removes track share creation as its mutation; H01b dispatches family creation before Strangler checks ownership. Both must fail and pass after restoration.

Domain handoffs: [FAMILY](a12f3b-family.md), [SHARES](shares-review-handoff.md). Existing AuthTwoFactor owns its four declarations through AuthGate before Strangler; H01 reuses its native tests and the retained Rails 2FA characterization rather than adding another page.

This is route activation, not H02–H04 producer/release closure. Remaining Trek actions stay with their domain owner. SHARES S02 photo transport remains dependent on A4. Unsupported legacy envelopes return native errors in standalone mode under ruling 15. H02 requires finished CACHE/MAIL/CRON and reverse/source handoffs; H03 additionally requires E21 and A12f-3c observations/fences; complete H04 and G42–G49 remain separate acceptance. Ruling 7 rollback pins all owners to Sidekiq, drains accepted native work, stops Phoenix and starts Rails on the same data; no pending-work transfer is introduced.

Shared knowledge counterpart: AFFiNE “Dawarich — A12f-3b native route integration”. Controller reports contain exact command results and mutation evidence; runtime allocations remain outside versioned documentation.

## ADMIN and TRIALHOME mounts

Router invokes `AdminFormRoutes.admin_form_routes/0` after `A10Routes` defines
`:admin_writes`. This adds native `DELETE /settings/users/:id` and
`POST /admin/settings/test_geocoding`. Existing admin pages and write routes keep
their ordering, gate metadata, current-session checks and LiveView authorization.
POST member forms still use the reviewed CSRF-validated `_method=delete` seam.
Missing account destruction capability returns 503 before marking the target;
A11 owns actual enqueue wiring. Cloud/non-admin refusal and operator Basic/grant
requirements remain those of the reviewed ADMIN package.

Router also invokes `TrialHomeRoutes.trial_home_routes/0` after its four pipelines
are defined. The four previous A10 scopes are removed, so root, welcome, upgrade
and resume each have one declaration with the same native handler and gate.
Standalone root guest/member and signed welcome/replay flows use native sessions
and once-claims. Existing trial status and connected authorization remain intact.

`test/dawarich/a12f3b_h01_hot5_test.exs`, selector H01d, checks unique mounts,
pipeline/gate metadata, native admin reads/settings/provider submission, DELETE
and POST deletion, unavailable capability, guest/non-admin/Cloud/CSRF refusal,
root GET/HEAD and mobile/referral markers, welcome sign-in and replay. Removing
either new macro call must fail its route assertions. Existing D01–D05 and admin
and trial authorization tests retain their domain coverage. This mount work does
not close A11 destruction, MAIL delivery, I01 provider parity, independent security
review or the controller's integration/release gates.
The fourth H01 pass uses the already mounted `OnboardingRoutes` demo POST/DELETE declarations and activates `IntegrationFormRoutes` with one import and macro invocation. Its nested settings pipeline serves PATCH/PUT and Rails-style POST overrides. The native Immich/PhotoPrism trigger owns POST `/settings/background_jobs`, replacing the overlapping legacy POST declaration; the existing PATCH and operator page routes retain their owners. The POST route recognizes the retained visit-settings query form before consuming its body and delegates it to the existing background-settings owner with its original gate/admission. Photo triggers then use the integration body parser and native owner. This keeps the source POST-to-PATCH form working during coexistence and self-hosted standalone operation without mounting ADMIN or TRIALHOME packages. Existing Cloud admission for that legacy form remains with its owner.

H01a now imports the bundled demo fixture through Endpoint, renders `/map/v2`, extracts the banner's Delete form and CSRF token, and submits its POST `_method=delete`. It verifies demo rows disappear, a real point survives, and the next map no longer displays the banner. Direct DELETE and CSRF refusal are covered too. This reused test passed before routing changes; no artificial demo RED is claimed. H01d proves unique executable integration declarations, nested settings saves and masked credentials in self-hosted and Cloud modes, exact native photo command payloads, invalid-CSRF/unknown-job errors, source-owned photo refusal and the retained self-hosted visit-settings POST override. H01b retains exact Rails method/body/cookie replay before effects for the newly mounted forms during coexistence.

H01d's new TDD contract starts RED at the missing integration POST declaration. M-H01d removes the integration macro invocation; the selector must fail at that same missing route and pass after restoration. A supplemental demo mutation removes its POST/DELETE declarations from `OnboardingRoutes`; the strengthened H01a must fail before import and pass after restoration. Exact results are recorded in the controller's fourth-pass report and the shared AFFiNE counterpart.

The existing A10b ownership oracle detects shadowing of the visit-settings POST override. A supplemental mutation disables that query-form recognition; the reused ownership test must fail and pass after restoration. The handoff remains native route activation; non-photo integration triggers and later integration tasks remain outside tonight scope.


## H03/H04 producer observation handoff

The plan-E dependency list is present on the H03 integration base, including
SOURCE-RESIDUAL, STATS, INTEGRATIONS (E061/E062), FAMILY, CACHE, IMPORTS,
ARCHIVE, PLACES, MEDIA and TRACKS. E101/E102 reuse import upload/download,
pending cleanup and stale-monitor owner tests. E14A2/E14B/E152 reuse throttled
backfill, generation/boundary and trip-calculation tests. Plan-G E20/E21 reuse
`jobs/drain_status_test.exs` and retained `spec/services/job_drain_spec.rb`.
Missing planned test filenames therefore do not imply missing implementations.

The three producer gaps observed by H03 are now covered by native ownership
adapters and terminal-effect tests:

- R13k05: `RailsEffects.reverse_place/3`, called by `Visits.Suggest.run/5`,
  enqueues `Geocoding.ReversePlaceWorker` under native command ownership or
  standalone mode. Native geocoding preserves the provider result and locked
  place name; Rails-owned coexistence keeps the exact reverse payload.
- R14 helper: `Points.NativeEffects.achievements/2` honours
  `command:achievements.check` during coexistence, preserving the existing
  native notification option and Rails-owned payload.
- R19k04: `ReleaseOperations.NullIsland.flag/2` atomically flags points and
  performs the native follow-up when `command:release.null_island` is native.
  It invalidates tiles, destroys Null Island visits and their dependent rows,
  and schedules distinct affected months and tracks. Month selection uses the
  ambient Rails time zone. Each downstream command retains its ownership
  hand-back; a Rails-owned parent keeps `release_null_island_follow_up` intact.

Named tests in `a12f3b_r13_test.exs`, `a12f3b_r14_test.exs` and
`a12f3b_r19_test.exs` prove zero reverse rows in native coexistence and
standalone, worker terminal effects, Rails hand-back and mutation detection.
The Null Island case also verifies replay, mixed ownership and transactional
rollback on failed follow-up publication. H03a now exercises native place
publication followed by explicit Rails hand-back while retaining every drain
blocker. All 78 closure kinds remain; this scoped producer repair does not
certify the full R01–R20 audit, source drain, any ownership ED or G49.

### H03 closure recheck — R10 progress remains live

The all-R01–R20 recheck runs the existing reverse-effect tests and the reused
export, user-data, place, achievement, integration, family-mail, cache and
release owner tests. The three repaired R13/R14/R19 adapters pass their native
terminal-effect and Rails hand-back cases. This does not close H03 or H04:
R10k01 still publishes `imports.progress` during native-owned coexistence.

The actual publication sites are `Imports.GpxProgress.publish/2`
(`imports/gpx_progress.ex:31`), `Imports.GpxLifecycle.publish/3`
(`imports/gpx_lifecycle.ex:134`) and `Imports.NormalLifecycle.publish/3`
(`imports/normal_lifecycle.ex:154`). They check only standalone mode; they do
not consult the native parent keys `command:imports.process_gpx` and
`command:imports.process_normal`. With every Registry owner Oban, the real
progress helper inserts one reverse row in coexistence; successful GPX and
normal-import lifecycles each insert two. The same native paths publish no
reverse rows in standalone. The progress-only probe rolls back; the lifecycle
probe uses existing synthetic owner fixtures and cleans its private data.

The existing R10k01 test proves standalone publication and then expects a
reverse row after leaving standalone, without testing the native-owned
coexistence branch. Green owner tests therefore cannot certify this missing
branch. RX-IMPORTS must supply native progress publication under the actual
parent ownership, its terminal/subscriber effects and unchanged source-owned
coexistence before H03 all-producer and H04 final ED closure. No producer kind,
ownership ED or accepted source payload is closed over this finding. G49 and
every-mode Cloud lifecycle refusal remain unchanged. Exact commands, current
seed/head results and cleanup belong to the controller closure report.

`Jobs.Drain.status/1` now explicitly identifies `scope: native_sql`, source
status `NOT_OBSERVED`, source certainty `UNKNOWN`, and
`source_inspection_required`. Its G49 field remains `BLOCKED` even when binary
rollback reports `OBSERVED_EMPTY`. These fields also survive SQL read failure.
Native SQL cannot inspect queued, scheduled, retry, dead, busy or reserved
Sidekiq work, source fences, or source Redis read failures. The retained Rails
`JobDrain.status` remains the source observation. Neither result substitutes
for the other. All 78 reverse kinds remain in `RailsCommands.closure_kinds/0`;
all accepted/unknown/dead debt remains durable.

### Routes and producer dispositions

| Surface | Native evidence and retained fate |
| --- | --- |
| Family create/request mail | H01 route journey; E07 real dispatcher/delivery and replay; accepted Rails mail wrappers drain on source. |
| Track/timeline create, unlock, photos, revoke | H01 and S01–S07 real request/privacy tests; sharing permissions and source pins remain authoritative. |
| Poster create/purge | P01/P02, R15 and E13 terminal renderer/storage effects; storage errors retain work and shared blobs. |
| Achievement PNG and notification delete | A01–A04 and N01–N03 real request fixtures; no ownership closure inferred from rendering alone. |
| Settings, Trek and demo | N04–N09, I01–I06 and H01 request/producer tests; accepted integration wrappers remain source work. |
| Cloud job health | Existing operator D01a test reused as `h04_case:H04a`; real GET/HEAD/Basic/grant checks and no Rails proxy. |
| DRAIN rollback | Existing native trip/release terminal test reused as `h04_case:H04b`; all-owner pin, real dispatch/completion and unchanged source Redis. |
| Source observation | H03a/H03b plus E20/E21 owner tests; SQL-only results never certify source emptiness. |

H03 adds two named tests with actual RED at the absent source-observation
fields, then GREEN and failing M-H03a/M-H03b mutations. H04 reuses passing
operator and rollback names, adds assertions and independent `h04_case` tags,
and claims no fabricated RED or new duplicated journey. M-H04a sends successful
Cloud job-health dispatch through RailsProxy; M-H04b falsely reports source
emptiness. Both must fail and pass after restoration. The full seed-404 gate
covers the real domain journeys above; seed 202 remains the integration owner.

### Source inventory, seeds and release gates

The 125 application job classes, 78 reverse kinds and 24 source schedules are
inventories, not closure certificates. The complete source row fates are in
[source disposition](a12f3b-source-disposition.md), the plan-E source payload
table and [the schedule/drain runbook](a12d3-schedules-drain.md). Accepted source
instances and all their children remain on Rails 1.15.3. Native seeds use the
existing CLI/Seeds owners in [the lifecycle/seed runbook](a12h-lifecycle.md); ordinary bootstrap
seeds and destructive e2e reset are separate operations. Retained source
characterization uses `RAILS_ENV=test DATABASE_NAME="$RDB" REDIS_URL="$TEST_REDIS_URL"
asdf exec bundle exec rspec spec/services/job_drain_spec.rb --seed 404`, with
Swagger copied aside and restored. Existing generators remain owner-run; H03/H04
change no generator or golden fixture and require no re-recording. For an
authorized owner re-record, the existing invocation is
`WRITE_PHOENIX_FIXTURES=1 RAILS_ENV=test DATABASE_NAME="$RDB"
REDIS_URL="$TEST_REDIS_URL" asdf exec bundle exec rspec
app-phoenix/scripts/parity/a12e_cli_fixtures_spec.rb --seed 404`; copy/restore
Swagger, run twice and byte-compare the owner-generated seed/CLI corpora, as
described in [fixture recording](fixture-recording.md).

NE-01–NE-17 are decided by rulings 8–12: retain configured integrations/webhooks,
drain dormant mail, unused framework APIs, counter reset and historical release
payloads before retirement. They are accepted-work/disposition conditions for
final removal, not unanswered architecture questions. Ruling 13 preserves
characterized Rails bugs; ruling 16 retains Rails source for rollback. Ruling 17
requires a Rails-fix changelog; this handoff fixes no Rails defect.

G42/G43/G44/G47 image/upgrade gates, G48 same-data rollback rehearsal and complete
G49 remain release-owner acceptance. R1 HTTP envelopes, J1 all source forms,
J2 all reverse producer effects, and L1 Cloud provisioning/lifecycle remain
explicit owner inputs in [the release runbook](a12f-ruby-free-release.md).
Cloud native lifecycle remains refused in every mode pending the external L1
handoff. The A12f-3c fences, source quiescence, graceful stop and post-stop source
inspection remain mandatory. Ruling 7 supersedes transfer/rehome: pin every key
Sidekiq, drain accepted native work, stop Phoenix, then start Rails 1.15.3 on the
same DB/storage. No pending native-to-Sidekiq transfer or source deletion occurs.

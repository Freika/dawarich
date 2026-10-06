# A12f-3b native route integration

H01 mounts the merged FAMILY, SHARES and POSTERS seams. `DomainRoutes` declares the family form routes before invitation tokens, gives family pages their own LiveView session with LiveAuth followed by FamilyGate, and mounts track, timeline and supplemental share revoke routes after the share form pipeline. Router changes are limited to imports and macro calls. The existing achievement, settings, integrations, admin, trial and home declarations remain mounted once.

The family form dispatcher retains formatted paths and effective form methods. During coexistence, invitation creation hands back before body consumption when its native mail leaf is source-owned or unreadable. The producer still locks ownership inside its transaction. Standalone operation returns native failures for unavailable leaves; this integration does not change worker ownership or certify delivery readiness.

FamilyRequestAdmission checks malformed query/form percent escapes, body types, override headers and incompatible effective form routes before writes. It retains the original raw body for Rails replay and supplies that same body to the family's existing parser. Compatible overrides still reach native actions. Route snapshot tests assert the dedicated family session and hook order; sharing endpoint tests retain byte-exact replay for incompatible overrides and assert native deletion for accepted DELETE overrides.

Share forms use ShareManagementForm admission after Body and RailsAuth, preserving raw POST replay, JSON support and permitted PATCH/DELETE overrides. Poster forms use PostersGate for authenticated and guest outcomes. Standalone sharing admits Cloud requests and authenticated/family viewers to the existing native handlers; FamilyAudience remains the authority for access. Public HEAD uses GET status and headers with an empty body. Coexistence transport gates and route pins remain in force before effects.

`test/dawarich/a12f3b_h01_test.exs` covers unique executable declarations, literal invitation precedence, native family create/update, all six track/timeline actions, mounted poster create/delete, sharing HEAD, exact pinned method/body/cookie replay with unchanged SQL, source-owned invitation mail handback, validation/CSRF refusals, standalone Cloud pages/actions and family-audience denial. H01a removes track share creation as its mutation; H01b dispatches family creation before Strangler checks ownership. Both must fail and pass after restoration.

Domain handoffs: [FAMILY](a12f3b-family.md), [SHARES](shares-review-handoff.md). Existing AuthTwoFactor owns its four declarations through AuthGate before Strangler; H01 reuses its native tests and the retained Rails 2FA characterization rather than adding another page.

This is route activation, not H02–H04 producer/release closure. Missing achievement PNG, Trek/onboarding/notification HTTP action seams at this base remain with their domain owners. SHARES S02 photo transport remains dependent on A4. Unsupported legacy envelopes return native errors in standalone mode under ruling 15. H02 requires finished CACHE/MAIL/CRON and reverse/source handoffs; H03 additionally requires E21 and A12f-3c observations/fences; complete H04 and G42–G49 remain separate acceptance. Ruling 7 rollback pins all owners to Sidekiq, drains accepted native work, stops Phoenix and starts Rails on the same data; no pending-work transfer is introduced.

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

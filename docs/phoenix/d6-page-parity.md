# Auth and public shell parity

D6 implementation is in progress. The default self-hosted credential pages now
use the Rails 1.16.0 grid, cards, field markup and icon-led feature lists.
`AuthPagesParityTest` compares five pages in all seven locales against the
Rails request recorder `scripts/parity/auth_pages_fixtures_spec.rb`. OTP uses
its existing settings recorder and `AuthOtp.FormTest`; its challenge fixtures
were refreshed from the current Rails templates, verified against the tag.

Recovery locale navigation accepts the supported locale values while retaining
closed admission for unknown locales, duplicate keys, malformed encoding and
nested parameters. The standalone dispatcher still owns these HTTP forms.
Auth error accessibility and duplicate-submit handling remain native. Recovery
headings keep `min-w-0 [overflow-wrap:anywhere]`: a browser probe of the Rails
German unlock page measured 533 px at a 390 px viewport without this fix.

Public live and timeline pages use `PublicMapShell` for the Rails main section,
heading, status rows and map container. The native scoped map host, readiness,
revocation and expiry handling remain in `PublicMapLive`. Live/timeline pages no
longer expose the native replay launcher, which Rails does not render there.
Trip replay remains where Rails renders it; tracks have no replay launcher. The phrase and unavailable states reuse the existing
Rails-compatible `SharedPages` components; the public HTTP unlock token stays
bound to the link and session.

`SharingParityTest` adds 34 normalized DOM comparisons to the existing behavior
corpus. It also checks the unavailable-state main DOM in existing cases.
Normalization is limited to the native map host id, native auth hook attributes,
and the explicit remember-me label association. These differences, and the
phrase input's accessible name, are recorded in
[the divergence register](visual-parity-divergences.md).

The route/state inventory is [d6-route-parity.json](d6-route-parity.json).
The browser capture manifest adds password edit and unlock request pages.
Auth pages also cover disabled registration, provider-only and credential/provider
combinations, invitations, Cloud signup controls and validation errors across all
seven locales. Confirmation routes are explicitly unavailable, matching Rails'
non-confirmable User. Account-link challenge/alert DOM extends its existing test.
Invitation sign-in stores context through locale navigation and returns valid
credentials to the invitation acceptance route; malformed/duplicate parameters
remain refused. Source provider buttons are shared across auth callers, with
per-action CSRF for the request session.

The eight management routes now have source DOM comparisons alongside their
existing behavior corpus. The controller's parity bench remains
read-only; pixel and request equality acceptance have not been run for this
worktree.

AFFiNE counterpart: Dawarich — D6 auth and public shell parity implementation
(document `9917Tg2C9kvp-BU5-kQj7`).

The Manager `/auth/dawarich` URL is an external handoff, listed separately from
Dawarich routes in the inventory. Poster/video HTTP resources expose create and
destroy; the page DOM belongs to the embedded map/trip studio callers.

OTP keeps bounded input width and heading wrapping at 390 px. The Rails
size-32 large-text input otherwise forces 432–434 px page width in en/de; the
OTP parity test normalizes only these documented resilience classes.

Public month and digest content now reuse their Rails-compatible public components.
The existing stats recorder adds 28 public fixtures (seven locales, full and
partial owners). Native charts mount in the source plot container, with lazy
Chart.js loading and owned teardown. The public month loading overlay follows
map settlement. Both reports use application chrome, as Rails does; its sign-out
action receives the viewer's CSRF without exposing the share owner's account.
Bounded public names retain full country/city totals and more indicators.

Static public trip and track content now reuse `SharedResourcePage` with the
scoped native map host, owned replay controls and authorized day galleries.
The existing sharing recorder adds 28 full/minimal fragments in seven locales,
including a real day note. Day hover/focus and day-color/selection updates live in the lazy map runtime,
with scoped DOM observation and owned teardown; click and keyboard
selection keep server admission. Trip distance factors now use meters per
unit, and public duration uses nominative translations without changing the
shared relative-time helper. Hidden track statistics remain out of its title;
that source privacy difference and replay/gallery wiring are registered. The
source replay button uses the existing scoped native runtime opener; public
sharing journeys verify both opening and closing its panel.
Explicit heading constraints retain 390 px fit for long names. The static CSS
change removes only the retired 70vh map-height utility.


The public achievement test now compares the complete body for every recorded
locale, embed and card state. Its existing source recorder already covers these
pages; no duplicate recorder was added. Trip poster/video studios now reuse the
shared embedded source-shaped controls, compared in all seven locales through
NativeMapStudiosParityTest and the existing posters recorder. Poster dates stay
fixed; the native video runtime keeps its admitted fixed route while using the
source control DOM. Existing gallery, callback and scoped-refusal checks remain.

Missing trip/track resources use the native generic 404, with the existing access
counter effect retained; Rails returns a specialized missing-resource body with
200. An unknown persisted resource enum crashes Rails before its unsupported
partial can render; the native grant stays closed with 404 and no access count.
The existing sharing recorder now records these source results in seven locales,
and SharingParityTest checks the explicit native envelope and data refusal.


Management uses the source modal chrome, creation controls, active cards, hub
panels and report-sharing controls. The existing share-management recorder adds
56 type/state/locale documents and 42 report/achievement fragments. Its existing
parity module adds 196 comparisons across seven locales; the hub compares its
selected panel and omits inactive controls. Date inputs use explicit local-date
inputs in pure fixture comparisons and the viewer timezone in real requests.
Every native manager retains named controls and unique ids.

Month/digest controls autosave on change; their source readonly URL and copy
control replace the extra native link and submit action. Achievement controls
match the source toolbar inside their dedicated native route, retaining its
existing copy action. Native modal closing returns to the fixed resource route;
Escape belongs to its own dialog, so cancelling a confirmation does not close
the underlying manager. Confirmation buttons push the native focus target before
form submission disables them; confirmation removal pops it after cancellation.
Shared-list forms preserve scoped confirmation using a
non-shadowing native row identifier. All actions still revalidate the account
and resource through NativeSharingAuth and the existing contexts.

Phrases remain absent from LiveView state. Initial generation and explicit copy
use the existing authenticated HTTP endpoints; browser-owned readonly fields
and manual-copy status clear on update, disconnect and teardown. Public URL
inputs select locally and own their selection listener. Source label associations,
hidden-checkbox duplicate ids, native confirmations and these request/DOM wiring
contracts are listed in the visual divergence register. Final family browser and
integrated controller-bench acceptance remain pending.

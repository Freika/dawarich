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
Trip/track replay remains. The phrase and unavailable states reuse the existing
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
Provider-only login, invitation variants, full validation-error DOM, account
linking DOM, static trip/track shares, unsupported share types,
all eight management page DOMs and trip studio variants still require completion
or explicit contract differences. Existing behavior coverage is not evidence of
DOM parity for these remaining routes. The controller's parity bench remains
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

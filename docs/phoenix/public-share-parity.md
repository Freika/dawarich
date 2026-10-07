# Public share owner and expiry parity

Public month and digest capabilities load their owner through
`Accounts.public_owner/1`. Login locks do not revoke a capability. NULL settings
retain the source defaults. Deleted or missing owners are refused without an
exception; Rails currently crashes on that case for month and digest pages.
Achievement cards and images also accept NULL owner settings. Track, trip,
timeline and live page loaders do not use login eligibility to load an owner.
The source User model does not enable Devise confirmation.

`SharingExpiry` supplies the month, digest and public month-map expiry guard.
A blank expiration means no expiry. Other expirations require a parseable stored
value; invalid values and times before the request instant are refused. Equality
remains accessible. Parsing uses the guest application timezone or the signed-in
viewer's timezone, as Rails `ApplicationController#set_user_time_zone` does; the
owner's timezone does not determine the expiry instant.

Stored values use the native Ruby date parser and the pinned TZInfo transition
snapshot, including partial dates, local timestamps, numeric and named offsets,
DST gaps/ambiguities, fractional seconds and years beyond 9999. The existing
Unix-to-naive conversion now supports those extended years. TZInfo's finite
transition horizon is retained.

`priv/rails_time_zone_dst.json` complements `rails_time_zones.json` with the
initial period DST flag and the zero-based indices of daylight transitions.
Both snapshots must use the pinned `tzinfo-data` version. Refresh the DST metadata
by enumerating `TZInfo::DataSource.get.data_timezone_identifiers`; obtain each
info object's initial previous offset and transition offsets (or constant offset),
serialize the initial DST flag and the indices whose transition offset is daylight.
Check the main snapshot against the same source initial offset and transitions. Select the Ruby data source.
No Ruby interpreter or host timezone files are needed for expiry parsing.

`test/fixtures/stats/public_share_expiry.json` records 2,475 actual Rails parse
results at its fixed clock, using the input strings and zones of the existing
import preparation corpus plus historical, future and DST cases for all 345
source data zones. Record UTC to six fractional digits and invalid parse
errors. This separate oracle reflects the current Ruby TZInfo source; the earlier
import oracle retains its original source behavior.

Named Endpoint/domain tests cover owner states, both sharing pages, the common
map guard, all expiry oracle cases, viewer timezones and expiry boundaries. Each
new named test has RED, GREEN, a named production mutation failure and restored
GREEN evidence in the controller report. The deleted-owner difference is
ED-FIX-PUBLIC-SHARE-OWNER. No Cloud lifecycle admission is changed.

AFFiNE counterpart: Dawarich — Phoenix A12f-3a Q native stats and digest
implementation (`poskgp6EKQz4qU2XYFUC6`).

Repeated full gates require `JobsCase.reset!` to clear polymorphic Action Text
rows explicitly; their record references have no database foreign keys for the
recursive fixture cleanup to follow. The minimal test-harness seam includes
`action_text_rich_texts` and a deterministic reset regression. This changes no
runtime trip behavior and prevents persisted rich-text rows from colliding with
reused synthetic trip IDs on later suite runs.

## Achievement query admission

Achievement PNGs and public cards ignore unknown query keys after validating the
whole query. Tracking keys, encoded keys, repeated unknown keys and nested
unknown values no longer trigger the closed form allow-list. PNG locale handling
and card locale/embed handling retain their existing admission and effects.
Header admission, HEAD, cache headers and unavailable-share responses are unchanged.
Public month/digest and `/s/:id` viewers already admit ordinary tracking keys.

Real Rails 1.15.3 Rack requests return PNG 200 for tracking keys, including
valueless keys, and 400 for malformed percent encoding, invalid UTF-8, conflicting
scalar/object parameters and nesting at depth 100. Native malformed queries
retain the existing terminal 422 response. Native achievement queries retain
the existing 65,536-byte ceiling and locale duplicate refusal; Rails accepts
queries beyond that ceiling (including a value over 4 MiB in-process) and uses
the last duplicate locale. Validation uses the existing `Api.SourceParams`
parser, whose nesting limit is 32. Public card valueless queries still encounter
the existing page-envelope refusal; this change does not alter that shared gate.
These are retained admission differences, not Rails query-size guarantees for
an HTTP server or reverse proxy. Regression evidence is in
`a12f3b_a02_test.exs` and `a12f3b_a03_test.exs`, tagged `fix_ach_image_params`.

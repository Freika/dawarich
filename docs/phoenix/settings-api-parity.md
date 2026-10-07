# Settings API parity corrections

The post-hoc A12f-2D review identified valid timezone failures in mobile and
area responses, permissive style URL validation, and nullable settings reads.
These corrections retain the Rails 1.15.3 API contract.

Mobile timestamps (seconds) and area timestamps (milliseconds) use
`Dawarich.RailsTimeZone`, backed by `priv/rails_time_zones.json`. The snapshot
contains all 345 data zones and 253 linked identifiers from the pinned
`tzinfo-data` 1.2026.5 dependency. Rails display names use the existing
`TimeZoneName` mapping. Settings timezone admission uses the same snapshot.
Neither admission nor these timestamp paths reads host zoneinfo or PostgreSQL
zone aliases. UTC/UCT abbreviations serialize as `Z`; other zero offsets keep
`+00:00`, matching ActiveSupport. The transition horizon and initial/final
periods match the source TZInfo definitions, including legacy identifiers such
as CST6CDT and southern hemisphere aliases.

To refresh the snapshot when the source dependency changes, select TZInfo's
Ruby data source, enumerate `data_timezone_identifiers`, and serialize each
info object's constant offset or initial transition's previous offset, followed
by all transitions as `[timestamp_value, utc_total_offset, abbreviation]`.
Enumerate linked identifiers separately with `link_to_identifier`. Record the
new dependency version in the JSON and regenerate the ActiveSupport timestamp
corpus. These are build assets; production needs no Ruby interpreter.

Mobile PATCH and area POST/PATCH/PUT keep the entire service write and JSON
encoding inside an ordinary outer transaction (`Api.WriteResponse`). Serialization
exceptions or service error responses roll back the row and relabel outbox
before the response is sent. Successful responses send the already encoded body
after commit. This is a controller-authorized correction of the source's
save-before-render failure behavior; direct service callback semantics remain
unchanged. No savepoint-mode transaction or new job framework is introduced.

Style document validation checks Ruby-compatible ASCII URI path, fragment,
userinfo, host, IP literal, and port syntax. Query-string syntax retains Ruby
URI's behavior. Tile templates still use the source placeholder rule. Invalid
style documents return the source 422 message without changing settings.
Nullable settings containers read as an empty map; a null timezone returns
`TIME_ZONE`, defaulting to UTC.

Standalone mobile and area handler registrations, plus delegation of the
settings GET to `Api.SettingsController`, are the minimum routing seam needed
on this baseline. Existing authentication and actor scoping apply.

Five named Endpoint tests cover the four review findings and failed-response
rollback. The timezone corpus covers 1,544 winter/summer/DST cases across all
TZInfo identifiers and Rails display names; mobile and area writes cover every
case, with mobile reads and area index/show/update also checked on the 96-case
boundary corpus. URI fixtures come from actual Rails settings PATCH requests.
Rollback tests use a regular pool and an independent Postgrex reader, including
create/update and outbox rollback. Each named test has RED, GREEN, mutation, and
restored GREEN evidence in the controller implementation report. The final
seed-404 suite and build/security gates are recorded there.

AFFiNE counterpart: `DwvFxg-nXKvHTWqzEEvt4` (Dawarich — A12f-2D main API
implementation and J handoff).

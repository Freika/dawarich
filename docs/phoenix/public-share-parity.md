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

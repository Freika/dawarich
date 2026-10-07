# Phoenix fixture recording support

Rails parity recorders use `app-phoenix/scripts/parity/fixture_recording.rb` and
RSpec registration in `spec/support/phoenix_fixture_recording.rb`. Production
Rails signing and timezone behavior stays unchanged.

`SyntheticSecret` temporarily installs the committed synthetic fixture contract.
Changing `secret_key_base` alone is insufficient after boot: the application
message-verifier factory, Active Storage verifier, Blob signed-ID verifier,
Turbo stream signer and SignedGlobalID verifier can retain the previous key.
The support rebuilds them together and restores the previous objects and cache
presence after each example, including failures. Cookies, blob URLs, direct
uploads and Action Text attachable SGIDs then use the same synthetic contract.

`CanonicalTimezone` removes ambient `TIME_ZONE` while recording and pins the
safe-settings default to UTC. It pins the Rails recording zone to its unset-env
default, Europe/Berlin, and clears ambient timezone for context capture hooks too. The two map-frame missing-timezone recordings
explicitly require the Berlin default; support metadata selects it locally.
The per-example environment, Rails zone and frozen defaults are restored after
each example; the context environment is restored after its capture hooks.
Recorders that intentionally override timezone inside an example keep doing so.

Digest recordings also pin country latitudes with
`FixtureRecording.canonical_timezone_latitudes`, using the locked `tzinfo-data`
package's canonical IANA country zones. System zoneinfo can include linked names
that the package omits. The recorder supplies the same latitude table to the
Rails calculators and southern-zone export, preserving exact corpus comparisons
without making host tzdata an input.

The southern-zone resource is compiled into native seasonality. Its pinned Ruby
provider table changes 27 linked names from southern to northern seasons to
match Rails' default for raw aliases without country latitude metadata. For
January-only distance, `Africa/Blantyre` therefore returns 100% winter. Forcing
Rails to use system zoneinfo is a different provider contract; a recorder run
that replaces the latitude table does not prove runtime parity with it.

The imports-page recorder pins the imports, blob and attachment sequences before
creating its initial wrapped upload and restores both `last_value` and
`is_called` afterwards, including failed captures. Stats routing-error captures
temporarily clear the mounted ActionCable server's transient subscriber,
event-loop, worker-pool and remote-connection state, then restore it after
rendering. Places cleanup captures pin each batch's input order while
preserving all user IDs and per-user delays.

Serialized source packets compare complete diagnostic bodies, including escaped
source line spans. Changes to recording hooks can invalidate those bytes even
when status and request effects stay identical. Re-record every affected source
packet through its existing recorder and read it back with writing disabled.

The user-data recorder refreshes both E04 packets. Its map-matching restore
oracle takes the old-schema input from the retained `old_v2` restore capture,
so refreshing current export fixtures does not replace the backward-compatibility
input with a current-schema track.

Ordinary `FixtureRecording.verify` remains an exact byte comparison. The map
closure explicitly selects `timeline.body` for parsed JSON comparison because
Rails mode-distance object key order is unspecified (DRB-021 in
`deferred-rails-bugs.md`). Arrays, distances and other opaque bodies still have
to match. Phoenix serializes mode keys in sorted order.

Before an RSpec recording batch, copy `swagger/v1/swagger.yaml` aside and
restore it afterward: the suite's Swagger generation hook writes this file.
Some older recorders write fixtures unconditionally; redirect fixture paths to
scratch copies for read-back verification. If a contract change requires new
fixtures, run the authorized recording twice and compare every byte before
committing the results. A signer-cache repair alone should not regenerate data.

The A8 corpus index enumerates JSON-only visits and video closure captures as
well as paired HTML/JSON recordings. Requiring HTML for every JSON file silently
omits the closure manifests; the census must check the exact names for each
format separately.

Poster coverage also needs the vendor Node install described in
`app-phoenix/scripts/test_partitions.md`.

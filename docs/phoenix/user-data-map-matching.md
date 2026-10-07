# Track map-matching fields in user-data archives

The native user-data export includes the five Track columns added by the
map-matching schema merge: `map_matched_at`, `map_matching_data`,
`map_matching_input_digest`, `map_matching_status`, and `matched_path`.
It uses the existing serializers: millisecond timestamps in the export time
zone, JSONB objects in PostgreSQL key order, and spaced WKT geometry strings.
At the mm-a Rails baseline, status is an integer or null. The later enum in
the unmerged `feat/map-matching` model is outside this baseline.

Restore follows `Users::ImportData::Tracks::IMPORTABLE_ATTRIBUTES` in both
the baseline and `feat/map-matching`: it accepts older archives without these
columns and newer archives with them, but drops all five incoming values.
New tracks retain `original_path` and their segments, with null matched path,
timestamp, digest and status, and empty map-matching data. Existing tracks
keep their existing map-matching state when skipped or refreshed. No new
map-matching scheduling behavior is introduced by this export parity change.

Historical archive fixtures remain unchanged. The source characterization
`app-phoenix/scripts/parity/user_data_map_matching_fixtures_spec.rb` records
the new shape in `app-phoenix/test/fixtures/user_data/map_matching_columns.json`.
The capture covers UTC, Berlin and New York timestamps, null and populated
values, nested JSONB, a multi-line geometry, and monthly/root JSONL restore
of both Track shapes. Export tests merge the new Track member with historical
members through `UserDataSeeds.current_export_entries/1`; restore tests still
read historical input bytes directly.

Archive corpus writes require `WRITE_PHOENIX_FIXTURES=1`, including
`UserDataFixturesSupport.save_entries/2`. Ordinary source checks cannot
silently replace archive fixtures. The new native named test compares complete
ZIP member bytes and restore results with Rails. Its mutations omit JSONB
from export and admit it during restore; both must fail the oracle assertions.

AFFiNE counterpart: **Dawarich — Implementation: A12f-3a E native exports and
backup journey**, document `3jnCJWRTo80DsateIkxcL`.

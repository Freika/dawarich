# Import memory and visit queries

## JSON imports

Records.json, Polarsteps GPS trails and enhanced steps, photo API library dumps,
and mobile photo library exports use `Imports::JsonStream`. The reader scans the
local file twice: first to validate JSON and collect root metadata, then to yield
entries. Storage downloads use a verified temporary file, removed after success
or failure. Malformed JSON and invalid mobile-library metadata fail before any
points are inserted, even when metadata follows the points array.

The Oj SAJ handler retains one entry, including its nested objects and arrays,
and discards unrelated root collections. It scrubs invalid UTF-8 strings and
keys before handing them to importers. A nested activity timestamp remains part
of its parent location; it never becomes an additional fix. Records batches
contain 1,000 locations and retain the existing zero-based progress offsets.
Polarsteps and photo API imports batch valid points; mobile libraries batch raw
entries and retain rejected-entry accounting.

Memory scales with the largest entry plus a batch, rather than the entire JSON
file. Validation adds a sequential scan in exchange for preserving rejection
before writes. No enclosing transaction or change to bulk-insert deduplication
is introduced.

Google semantic-history importers and the enhanced semantic-history adapter
still parse monthly files whole: those files are bounded by a calendar month.
Google Photos imports also retain whole-document parsing because each JSON
sidecar describes one photo. The enhanced base adapter retains its general
whole-document helper for the monthly semantic adapter; Polarsteps no longer
uses it. Phone Takeout and GeoJSON already have streaming readers.

Regression coverage: `spec/services/imports/streaming_json_spec.rb` compares all
persisted point fields for 2,003 Records locations with the direct importer,
checks progress offsets, invalid bytes and malformed tails, and forbids
`Oj.load` and `File.read` for the converted paths. Neighboring importer specs
cover downloads, integrity checks, rejected entries and duplicates.

# Supplemental Rails terminal captures

These complete source captures replace the incomplete historical entries for the Places and Ingest API golden readers. The externally owned fixture corpus remains unchanged. Both readers merge cases by name; Places also merges the recorded setups and sequences.

Only Rails emitters produce the JSON files. Set `API_GOLDEN_CASES` to the affected comma-separated names and `API_GOLDEN_OUTPUT` to the relevant file here. Run the emitter with the detected Ruby environment, `RAILS_ENV=test`, an inline private `DATABASE_NAME` and private `REDIS_URL`. Ingest also requires `WRITE_PHOENIX_FIXTURES=1`. Copy Swagger aside before each RSpec batch and restore it afterwards. Do not run an unrestricted emitter against the external fixture symlink.

The emitters enable production exception handling and disable detailed exceptions, use synthetic cookie secrets and frozen clocks, and retain terminal bodies and headers under the existing harness normalization. Every case records database after-state. Ingest additionally preserves its normalized point rows, counter and arrival commands; its raw snapshot records all source tables. Comparisons retain the existing point-ID/source-digest/fresh-timestamp contract and also check unaffected users/families/memberships, source dimensions and other users' points. The intentional OwnTracks table-rename fault is checked through its renamed relation.

Cookie ciphertext remains redacted under the existing volatile-header rule. The readers additionally verify cookie names/attributes, empty expiry cookies, and decoded session payloads against Rails' captured session state. Generated session IDs are validated as 32 hexadecimal characters.

Three existing safer native refusals are asserted separately from the unmodified Rails captures: scalar Place parameters, null latitude updates and invalid ingest coordinate text. Their FRB-NATIVE-S2GA and ED-NATIVE-S2GA entries document the complete source defect and the explicit native difference. No capture is derived from a native response.

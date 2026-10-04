# A6 slice 4 map web mutations

Implementation plan: `/Users/frey/projects/dawarich/superpowers/plans/2026-10-03-phoenix-a6-slice4-map-writes-plan.md`.

Supported signed-in tag create/update/delete, segment override/reset and point-list bulk deletion are implemented. Tag numericality compares the submitted radius using Rails numeric whitespace and fifteen-significant-digit rounding; integer storage remains a separate cast. Unicode blank radius still casts to nil.

`tags`, `tracks` and `points` independently return reads and writes to Rails through `DAWARICH_RAILS_ROUTES`; `map` alone leaves these mutations native. Unsupported requests replay before writes or after rollback. Point deletion, counters and follow-up intent are atomic; residual Rails cache/job/broadcast effects arrive through the existing durable bridge after commit. Unchanged nonnil segment mode still emits callback intent, while no selected mode emits none.

Expected differences are ED-380 through ED-384 in `app-phoenix/parity/expected_diffs.md`; slice-3 read differences remain. Unchanged tag-validation and segment-stream sessions retain their existing cookie rather than re-encrypting it. Changed session contents still require a cookie.

Browser, stand and image checks are deferred to the release tier, including missing point-list, tag CRUD and segment frame roundtrip journeys. Local tests do not establish this acceptance. This completes bounded web mutation implementation, not all A6: API ownership remains A4, media A8, sharing A9, channels A12a, and the residual bridge/Rails retirement A12.

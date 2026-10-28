# Legacy Area to Place backfill

`DataMigrations::BackfillAreasIntoPlacesJob` runs on `data_migrations` and calls
`Places::AreasBackfill`. Lazy resolution through `Places::LegacyAreaAdapter`
uses the same migration for an existing unmapped Area.

Legacy Area names can exceed Place's 255-character limit. The backfill copies
only the first 255 characters into a created or promoted Place, without adding
an ellipsis. Ruby character slicing preserves valid multibyte strings. Names
of 255 characters or fewer are copied unchanged. If the first 255 characters
are all whitespace, leading whitespace is removed before taking the prefix so
the Place name remains nonblank. The original Area row keeps
its full name; no schema migration or public API validation change is needed.

Matching still compares the full normalized Area name (trimmed and lowercased)
and requires a Place within 50 metres. It does not compare truncated prefixes:
different long names sharing their first 255 characters get separate Places.
A Place already mapped from a long Area is excluded when that original
normalized identity differs from the incoming Area, including when the incoming
name equals the truncated prefix. This protects either migration order.
A full normalized match may promote an existing Place, subject to the existing
ambiguity and note-date collision checks.

The stable `LegacyAreaPlaceMapping` makes a completed backfill restartable.
Area notes move to the mapped Place with their contents intact. Area-only
visits retain their IDs and gain the Place association; existing label,
ownership and visit-conflict rules still apply. The legacy Area remains.

After upgrading to code containing this fix, a failed long-name backfill can
be retried from Sidekiq's Retry or Dead set. If the job is no longer present,
an operator can enqueue `DataMigrations::BackfillAreasIntoPlacesJob.perform_later`
in the application's Rails console. Completed mappings are skipped; genuinely
invalid Areas are still reported and cause a retry after other Areas migrate.
Do not delete legacy Areas or mappings as a retry workaround.

Regression coverage: `spec/regressions/area_backfill_truncates_long_names_spec.rb`
exercises 255/256/300 characters, multibyte names, shared prefixes, promotion,
lazy resolution, preserved notes/visits and repeat runs. Existing service specs
cover ambiguous matches, note-date conflicts and invalid-record reporting.

Related issue: [#3930](https://github.com/Freika/dawarich/issues/3930).

Shared implementation and verification record:
[Dawarich — Legacy Area to Place backfill](https://affine.dwri.xyz/workspace/c309ded7-e11e-4e72-ba6f-aec8a31a740b/ATqJzjEbcMRbYpmCtzllC).

Implementation: [OneDev PR #260](https://onedev.dwri.xyz/dawarich/~pulls/260), targeting `dev`.

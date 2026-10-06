# Source users, release jobs and framework disposition

Last updated: 2026-10-06. Scope: producer plan G, E16–E21. This document versions the implementation contracts; the shared AFFiNE entry is titled **Dawarich — Phoenix source users, release and framework disposition**.

## Accepted source work

Accepted Rails job instances stay on the retained Rails 1.15.3 source application through every child, delayed continuation, retry and terminal effect. Native workers consume typed commands; they do not deserialize Sidekiq wrappers, GlobalID, Ruby symbols or Marshal. A successful native replacement does not dispose of already accepted source work.

Unknown, retired, dead or unreadable accepted payloads remain transition debt. Housekeeping preserves them. Drain results describe an observation, not proof that no producer can enqueue later. Source fences and final G49 observation belong to the release controller.

Binary rollback pins every owner to Sidekiq, drains native outbox, Oban jobs, release operations and generations to zero, then stops Phoenix before Rails starts against the same database and storage. It does not transfer pending native jobs into Sidekiq.

## Users

`Users::ExportDataJob` and `Users::ImportDataJob` use the existing native user-data export/import owners for new typed work. Archive discovery publishes the restore command and processed marker together; a publication failure keeps discovery retryable. Existing counter correction and recalculation owners retain their source arguments and effects.

`Dawarich.Mail.UserCallbacks.enqueue/4` is a producer seam for welcome, explore-features, archival-approaching, OAuth-link and destruction-confirmation mail. It validates each existing worker's payload, locks command ownership and publishes an outbox record with the supplied event identity and due time. Sidekiq ownership returns `:not_owner` so the calling domain keeps its existing source path during coexistence. This helper does not mount a new caller or activate an owner.

The four no-op trial email APIs return `:retired` for new helper calls. Dormant Confirmable mail and `FamilyMailer.member_joined` drain accepted wrappers before physical API/template removal. `Users::ResetPointsCounterJob` likewise remains available for accepted source completion; native counter correction is the new-work owner. No source classes or templates are removed by this package.

## Release operations

Existing native operations retain point-dimension DDL, places ownership, legacy-coordinate removal, motion/altitude/onboarding/name-lock/null-island/transportation repairs, point dimensions and countries, anomaly/per-tracker recalculation, orphan cleanup, route opacity and silent achievement publication. Parent checkpoints and child jobs stay transactionally coupled. Parent completion alone does not clear unfinished child debt.

Cloud family-plan backfill now decodes to `Dawarich.ReleaseJobs.FamilyBackfill`; self-hosted execution remains skipped. It publishes eligible users to the existing `Families.AutoCreateWorker` in ascending-ID pages of 500. Entitlement synchronization visits families in pages of 200 with `notify: false`, using the existing `Families.MemberSync`. Each family's changes commit independently, matching Rails when a later family fails. The operation checkpoint advances only after the page succeeds. Continuations retain operation identity and captured time zone.

HOT owns `jobs/release_entries.ex`. It must register `{"release.family_backfill", Dawarich.ReleaseJobs.FamilyBackfill}` as a release command before default CLI resume can resolve this worker. The worker executes and continues directly without that mapping; registration is a controller handoff, not a domain edit to the shared file.

Historical country-name, unique-index track dedupe, places-lonlat migration, counter-cache prefill, set-country-IDs, set-reverse-geocoded-at and start-settings-country-IDs classes remain refused by the native release decoder. Refusal cannot record a completed release version or commit earlier version effects. Accepted instances finish on Rails; unrecoverable instances block transition. The approved drain-then-retire disposition permits removal only after their accepted work is resolved, not immediate deletion or a catch-all successful skip.

## Framework census and storage

The retained runtime census resolves `ActionMailer::MailDeliveryJob` and ActiveStorage Analyze, Purge, Mirror and Transform jobs. `ActionMailer::DeliveryJob` is absent from the current runtime and remains unknown debt if encountered. Both current and historical Sidekiq ActiveJob wrapper names are counted without exposing their arguments.

The repository configures Disk for test/local storage and conditional S3. Mirror configuration is commented out and the variant processor is disabled. This package creates no Mirror/Transform producers. Historical accepted instances must drain before unused APIs can retire. Newly configured services or variants require their own producer/effect characterization.

Native storage owners retain analyzed/identified metadata, adapter identity, recoverable cleanup on object-delete failure and shared-blob reference checks. Retrying a purge after another attachment appears must preserve that attachment and blob for both Disk and S3.

Source JobDrain counts queued, scheduled, retry, dead, busy and reserved/unreadable work. Missing busy payloads, stale process heartbeats, queue changes during reads and Redis failures block the observation. Native SQL observation includes legacy schedulers, reverse debt and quarantine, but cannot establish absence of Sidekiq work.

## Verification ownership

Existing owner tests are strengthened where the baseline already implements the contract, as allowed by the plan's reuse convention. New user-callback and Cloud-family contracts have actual RED evidence, GREEN implementations and failing named production mutations. Every reused selector also has a failing mutation and restored GREEN evidence. The executor report carries exact commands, logs, task commits and feature gates; seed 202 and final release rehearsals remain controller gates.

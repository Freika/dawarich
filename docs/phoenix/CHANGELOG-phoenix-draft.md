# Phoenix release changelog — DRAFT

Compiled 2026-10-07. Each item links to the [evidence register](fixed-rails-bugs.md). This is a review draft, not a release announcement: some fixes remain on feature branches, deployment acceptance is pending, and fixes apply to the native paths listed in the register. Retained Rails-owned consumers are not covered automatically. Cloud lifecycle remains deferred.

## Security

- Prevent photo and integration redirects from sending credentials to another host. [FRB-011](fixed-rails-bugs.md#frb-011--provider-redirects-disclose-credentials)
- Bind import uploads to the account that created them. [FRB-003](fixed-rails-bugs.md#frb-003--an-upload-can-be-claimed-by-a-different-account)
- Prevent an old upload capability from recreating a file after it has been purged. [FRB-007](fixed-rails-bugs.md#frb-007--an-old-upload-capability-can-recreate-purged-storage)
- Limit photo and integration response sizes so oversized provider replies cannot grow memory without a bound. [FRB-012](fixed-rails-bugs.md#frb-012--provider-replies-grow-memory-without-a-bound)

## Privacy

- Stop serving shared trip thumbnails after a trip boundary edit excludes them, including requests forwarded to Rails. [FRB-001](fixed-rails-bugs.md#frb-001--shared-trip-thumbnail-authorization-survives-a-boundary-edit)
- Revoke native prepared-import downloads when the import is deleted. Previously issued external storage links remain subject to deletion or expiry. [FRB-004](fixed-rails-bugs.md#frb-004--import-deletion-leaves-a-prepared-download-usable)
- Keep failed native media deletion retryable until eligible files are physically removed. Rails-owned cleanup retains its existing limitation. [FRB-002](fixed-rails-bugs.md#frb-002--failed-physical-media-deletion-loses-its-retry-target)
- Keep provider-supplied credentials out of enrichment error messages. [FRB-013](fixed-rails-bugs.md#frb-013--provider-error-text-reflects-credentials)
- Omit initial account credentials from native installation logs. [FRB-017](fixed-rails-bugs.md#frb-017--bootstrap-credentials-are-written-to-logs)

## Data integrity

- Prevent completed extraction retries from repeating their saved effects. [FRB-005](fixed-rails-bugs.md#frb-005--legacy-extraction-replay-repeats-terminal-effects)
- Prevent an older extraction-removal retry from deleting a newer extraction. [FRB-006](fixed-rails-bugs.md#frb-006--an-old-removal-retry-can-remove-newer-extraction-data)
- Keep another account’s demo tags unchanged when importing a visit into inconsistently linked demo data. [FRB-009](fixed-rails-bugs.md#frb-009--demo-adoption-changes-another-accounts-tag)
- Retain tile-cache refresh work through a cache outage when restoring points with native cache-invalidation ownership. [FRB-015](fixed-rails-bugs.md#frb-015--a-restore-loses-tile-invalidation-during-a-cache-outage)
- Reject unsupported area response formats before saving changes or scheduling follow-up work. [FRB-016](fixed-rails-bugs.md#frb-016--an-unsupported-response-format-commits-an-area-write)

## Correctness

- Avoid duplicate failure notifications when retrying an accepted failed GPX import. [FRB-008](fixed-rails-bugs.md#frb-008--failed-gpx-retries-repeat-failure-notifications)
- Keep Google Takeout import progress from going backwards when an older continuation finishes late. [FRB-010](fixed-rails-bugs.md#frb-010--a-late-takeout-continuation-lowers-import-progress)
- Validate photo and integration base URLs before requesting an asset, avoiding the wrong resource or an incorrect verification result. [FRB-014](fixed-rails-bugs.md#frb-014--malformed-provider-bases-fetch-the-wrong-resource)
- Display apostrophes correctly in translated document titles. [FRB-018](fixed-rails-bugs.md#frb-018--localized-titles-double-escape-apostrophes)

## Deferred behavior and release decisions

These are preserved defects/policies, not release fixes. See the register’s [deferred section](fixed-rails-bugs.md#deferred-rails-defects-and-retained-policies) for the complete ID mapping and source evidence.

- **Needs Eugene decision:** valid signed backup/export links remain bearer links; possession can grant download access without owner authentication (DRB-027).
- Legacy optional mobile-login nonce behavior remains (DRB-001); tightening it needs a coordinated policy/client decision.
- Rails-owned media purge and prepared-import download revocation retain their asynchronous cleanup defects (DRB-025/029). Rails-owned tile invalidation can still lose refresh work during a cache outage (DRB-028).
- Malformed input/data failures, invitation/sharing partial effects, duplicate digest-mail risk, unspecified ordering, blank-name video retention and area-radius casting quirks remain deferred (DRB-002–018, DRB-020–022, DRB-024/026).
- The shared-thumbnail leak and title escaping defect are fixed in native paths (DRB-023/019); their presence in a deferred Rails register does not mean Phoenix deliberately preserves them.

Older intentional-difference candidates (FRB-019–032, FRB-042–044) and proposed Rails map-matching comparisons (FRB-033–041) are held out of the user-facing release list pending the verification/acceptance described in the register. They must not be advertised as shipped Rails 1.15.3 fixes without that review.

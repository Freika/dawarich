# Phoenix release changelog — DRAFT

Compiled 2026-10-07 from integrated fixes at `3a20a0279`. Each item links to one final [FRB evidence entry](fixed-rails-bugs.md). Native fixes do not automatically repair retained Rails-owned consumers. Proposed map-matching comparisons below refer to the Rails feature branch, not Rails 1.15.3. This is a review draft; native Cloud lifecycle remains refused pending external L1 handoff.

## Security

- Bind import uploads to the account that created them. [FRB-003](fixed-rails-bugs.md#frb-003--an-upload-can-be-claimed-by-a-different-account)
- Prevent an old upload capability from recreating a file after it has been purged. [FRB-007](fixed-rails-bugs.md#frb-007--an-old-upload-capability-can-recreate-purged-storage)
- Prevent photo and integration redirects from sending credentials to another host. [FRB-011](fixed-rails-bugs.md#frb-011--provider-redirects-disclose-credentials)
- Limit photo and integration response sizes so oversized provider replies cannot grow memory without a bound. [FRB-012](fixed-rails-bugs.md#frb-012--provider-replies-grow-memory-without-a-bound)
- Refresh rate-limit plans reliably after a subscription changes. [FRB-047](fixed-rails-bugs.md#frb-047--accepted-subscription-changes-lose-rate-plan-eviction)
- Require an administrator to send test email, including jobs queued before demotion. [FRB-049](fixed-rails-bugs.md#frb-049--non-admin-users-can-queue-test-email)
- Prevent an in-flight lookup from restoring a retired API key’s cached rate-limit plan. [FRB-054](fixed-rails-bugs.md#frb-054--retired-api-keys-retain-stale-rate-limit-classification)
- Use the socket identity for untrusted direct clients so forged forwarding headers cannot reset IP limits or sign-in attribution. [FRB-055](fixed-rails-bugs.md#frb-055--forged-forwarding-headers-override-an-untrusted-direct-peer)
- Keep untrusted Forwarded and X-Real-IP headers from changing IP limits or sign-in attribution. [FRB-061](fixed-rails-bugs.md#frb-061--rfc-forwarded-headers-bypass-an-ingress-written-client-identity)
- Fall back to the socket identity for malformed forwarding headers instead of skipping IP-only limits. [FRB-062](fixed-rails-bugs.md#frb-062--malformed-forwarding-headers-bypass-ip-only-limits)

## Privacy

- Preserve other accounts' records and references when account deletion encounters shared places or foreign dependent associations. [FRB-067](fixed-rails-bugs.md#frb-067--account-deletion-changes-another-accounts-dependent-records)
- Stop serving shared trip thumbnails after a trip boundary edit excludes them, including requests forwarded to Rails. [FRB-001](fixed-rails-bugs.md#frb-001--shared-trip-thumbnail-authorization-survives-a-boundary-edit)
- Keep failed native media deletion retryable until eligible files are physically removed. Rails-owned cleanup retains its existing limitation. [FRB-002](fixed-rails-bugs.md#frb-002--failed-physical-media-deletion-loses-its-retry-target)
- Revoke native prepared-import downloads when the import is deleted. Previously issued external storage links remain subject to deletion or expiry. [FRB-004](fixed-rails-bugs.md#frb-004--import-deletion-leaves-a-prepared-download-usable)
- Keep provider-supplied credentials out of enrichment error messages. [FRB-013](fixed-rails-bugs.md#frb-013--provider-error-text-reflects-credentials)
- Omit initial account credentials from native installation logs. [FRB-017](fixed-rails-bugs.md#frb-017--bootstrap-credentials-are-written-to-logs)
- Revoke native poster download capabilities while deferred purge retries wait. [FRB-029](fixed-rails-bugs.md#frb-029--deferred-poster-purges-leave-old-native-downloads-usable)
- Keep demo removal from changing another account's records, even when existing data contains cross-account references. [FRB-031](fixed-rails-bugs.md#frb-031--demo-removal-can-alter-another-accounts-dependent-records)
- Show an unavailable-share response when a public month or digest owner has been deleted. [FRB-053](fixed-rails-bugs.md#frb-053--public-month-and-digest-pages-crash-for-a-deleted-owner)

## Media

- Refuse adopting another account's attached route-video media. [FRB-028](fixed-rails-bugs.md#frb-028--a-signed-route-video-upload-can-be-adopted-across-accounts)
- Fence accepted Rails poster generation during native job ownership handoff. [FRB-030](fixed-rails-bugs.md#frb-030--accepted-rails-poster-jobs-bypass-the-native-handoff-fences)

## Imports and data integrity

- Prevent completed extraction retries from repeating their saved effects. [FRB-005](fixed-rails-bugs.md#frb-005--legacy-extraction-replay-repeats-terminal-effects)
- Prevent an older extraction-removal retry from deleting a newer extraction. [FRB-006](fixed-rails-bugs.md#frb-006--an-old-removal-retry-can-remove-newer-extraction-data)
- Keep another account’s demo tags unchanged when importing a visit into inconsistently linked demo data. [FRB-009](fixed-rails-bugs.md#frb-009--demo-adoption-changes-another-accounts-tag)
- Keep Google Takeout import progress from going backwards when an older continuation finishes late. [FRB-010](fixed-rails-bugs.md#frb-010--a-late-takeout-continuation-lowers-import-progress)
- Retain tile-cache refresh work through a cache outage when restoring points, including the durable command processed by Rails during coexistence. [FRB-015](fixed-rails-bugs.md#frb-015--a-restore-loses-tile-invalidation-during-a-cache-outage)
- Reject unsupported area response formats before saving changes or scheduling follow-up work. [FRB-016](fixed-rails-bugs.md#frb-016--an-unsupported-response-format-commits-an-area-write)
- Wait for ZIP member imports to finish before settling or removing their parent. [FRB-035](fixed-rails-bugs.md#frb-035--zip-parents-settle-before-their-children-finish)
- Keep accepted ZIP members processing when a later archive member fails validation. [FRB-036](fixed-rails-bugs.md#frb-036--a-partial-zip-failure-strands-already-accepted-members)
- Emit one no-points notice per successful empty import across interrupted processing and retry. [FRB-037](fixed-rails-bugs.md#frb-037--empty-successful-import-retries-repeat-no-points-notifications)
- Commit anomaly flags and their track, statistics and achievement rebuilds together, including restored points. [FRB-042](fixed-rails-bugs.md#frb-042--anomaly-flags-commit-without-their-derived-rebuilds)
- Keep point deletion, counters and derived-data rebuild work consistent when a follow-up fails. [FRB-043](fixed-rails-bugs.md#frb-043--point-deletion-commits-without-counters-or-rebuilds)
- Roll back mobile settings, area changes, digest deletion and follow-up work when response preparation fails. [FRB-052](fixed-rails-bugs.md#frb-052--a-failed-settings-or-area-response-leaves-changes-committed)

## Visits and caches

- Retry failed nightly cache cleanup instead of leaving countries and cities stale after a transient Redis timeout. [FRB-032](fixed-rails-bugs.md#frb-032--nightly-reverse-cleanup-acknowledges-a-failed-cache-deletion)
- Refresh calendar counts after demo visit edits or deletion, including import and null-island cleanup. [FRB-033](fixed-rails-bugs.md#frb-033--null-island-cleanup-leaves-restored-demo-visit-counts-cached)
- Preserve newer visit duration and point associations when suggestions execute concurrently or detection settings change during a run. [FRB-034](fixed-rails-bugs.md#frb-034--stale-concurrent-suggestions-truncate-newer-committed-visits)
- Keep track tiles current and retry invalidation after failed cache writes. [FRB-038](fixed-rails-bugs.md#frb-038--track-tile-epoch-write-failure-is-ignored)
- Keep statistics caches valid on rollback and refresh them after a committed empty-month reset. [FRB-039](fixed-rails-bugs.md#frb-039--empty-month-reset-evicts-before-commit)
- Retry failed digest cache eviction after source data changes. [FRB-040](fixed-rails-bugs.md#frb-040--digest-cache-eviction-is-lost-during-an-outage)
- Retry failed statistics calculations instead of leaving stale results. [FRB-041](fixed-rails-bugs.md#frb-041--a-failed-statistics-calculation-is-acknowledged)
- Retry cache refreshes after demo data is imported. [FRB-045](fixed-rails-bugs.md#frb-045--demo-import-loses-cache-eviction-after-an-outage)
- Retain statistics rebuilds and cache refreshes after demo data is removed. [FRB-046](fixed-rails-bugs.md#frb-046--demo-removal-loses-its-rebuild-or-cache-eviction)
- Retry calendar cache invalidation after a successful visit write instead of leaving old counts until expiry. [FRB-063](fixed-rails-bugs.md#frb-063--visit-cache-invalidation-failure-is-swallowed)
- Prevent old in-flight calendar cache fills from overwriting counts after a committed visit change. [FRB-064](fixed-rails-bugs.md#frb-064--an-in-flight-visit-cache-fill-resurrects-stale-aggregates)
- Refresh calendar counts after bulk visit confirmation or decline, including during cache outages. [FRB-065](fixed-rails-bugs.md#frb-065--bulk-visit-status-updates-omit-cache-invalidation)
- Preserve other accounts’ records and all visit references through area deletion and scheduled orphan-place cleanup. [FRB-066](fixed-rails-bugs.md#frb-066--area-deletion-removes-another-users-linked-records)

## Correctness

- Avoid duplicate failure notifications when retrying an accepted failed GPX import. [FRB-008](fixed-rails-bugs.md#frb-008--failed-gpx-retries-repeat-failure-notifications)
- Validate photo and integration base URLs before requesting an asset, avoiding the wrong resource or an incorrect verification result. [FRB-014](fixed-rails-bugs.md#frb-014--malformed-provider-bases-fetch-the-wrong-resource)
- Display apostrophes correctly in translated document titles. [FRB-018](fixed-rails-bugs.md#frb-018--localized-titles-double-escape-apostrophes)
- Retry failed live point broadcasts without treating an unsuccessful publication as delivered. [FRB-044](fixed-rails-bugs.md#frb-044--a-failed-live-point-update-is-permanently-suppressed)
- Keep accepted family subscriptions linked to durable family creation and member synchronization. [FRB-048](fixed-rails-bugs.md#frb-048--a-paid-family-subscription-loses-its-family-follow-up)
- Suppress duplicate successful test emails when the same accepted job is redelivered. [FRB-050](fixed-rails-bugs.md#frb-050--successful-test-email-redelivery-sends-another-message)
- Use default settings instead of crashing map, photo, family-sharing, locale and settings flows when the settings container is NULL. [FRB-051](fixed-rails-bugs.md#frb-051--null-user-settings-crash-default-readers-and-settings-writes)
- Choose a stable dominant transportation mode when segment distances or durations tie. [FRB-056](fixed-rails-bugs.md#frb-056--dominant-transportation-mode-changes-on-an-exact-tie)
- Keep tied top-visited-place rankings and their top-five cutoff stable. [FRB-057](fixed-rails-bugs.md#frb-057--tied-visit-rankings-change-top-five-membership)
- Keep tied digest and residency country rankings stable. [FRB-058](fixed-rails-bugs.md#frb-058--tied-country-rankings-depend-on-aggregation-order)
- Choose consistent location-search coordinates when point timestamps and accuracy tie. [FRB-059](fixed-rails-bugs.md#frb-059--tied-location-points-change-representative-coordinates)
- Choose consistent photo-enrichment coordinates when GPS timestamps tie. [FRB-060](fixed-rails-bugs.md#frb-060--tied-photo-scan-points-change-nearest-coordinates)

## Map matching reference branch

These comparisons are with the proposed Rails map-matching branch and are not Rails 1.15.3 release claims.

- Limit Atlas responses to prevent oversized replies from exhausting memory. [FRB-019](fixed-rails-bugs.md#frb-019--atlas-responses-can-exhaust-memory)
- Bound the total time spent waiting for an Atlas reply, including drip-fed responses. [FRB-020](fixed-rails-bugs.md#frb-020--atlas-drip-replies-can-run-indefinitely)
- Store only numeric allowlisted map-matching diagnostics. [FRB-021](fixed-rails-bugs.md#frb-021--provider-diagnostics-retain-arbitrary-strings)
- Commit map-matching claims and processing jobs together. [FRB-022](fixed-rails-bugs.md#frb-022--a-matching-claim-commits-without-its-job)
- Capture map-matching input under the track lock so concurrent edits cannot claim stale input. [FRB-023](fixed-rails-bugs.md#frb-023--matching-claims-fingerprint-stale-input)
- Keep skipped map-matching publication from overwriting a concurrent result. [FRB-024](fixed-rails-bugs.md#frb-024--skipped-matching-overwrites-a-concurrent-result)
- Recover abandoned map-matching claims automatically. [FRB-025](fixed-rails-bugs.md#frb-025--abandoned-matching-claims-require-manual-recovery)
- Keep map-matching demo controls clear of attribution on narrow screens. [FRB-026](fixed-rails-bugs.md#frb-026--narrow-demo-controls-overlap-attribution)
- Keep optional map matching from delaying an already completed track operation. [FRB-027](fixed-rails-bugs.md#frb-027--optional-map-matching-delays-a-completed-track-operation)

## Deferred behavior and release decisions

See the [DRB status register](deferred-rails-bugs.md) for preserved behavior and native-only corrections. Signed backup/export bearer policy (DRB-027), trusted-ingress pass-through (DRB-036), optional mobile nonce policy (DRB-001), digest sent-marker ordering (DRB-013), malformed-data parity and Rails-owned physical purge remain outside these native fixes. Older ED candidates with incomplete provenance remain in the [evidence appendix](fixed-rails-bugs.md#older-ed-candidates-requiring-provenance).

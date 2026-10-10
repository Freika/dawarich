# Native milestone 4 frozen contracts

Date: 2026-10-10. Approved defaults O1–O10; governing ADR-0017. This handoff supplements `native-m4-inventory.md`. Controller integrates the family/sharing track and performs the final full gate.

## Product and transport decisions

- Imports keep atomic batch claim and whole-ready-batch repair/retry. No partial publication or automatic retries after an unknown commit. Existing duplicate-name behaviour stays.
- Configurable transport defaults: 20 entries, 50 GiB per entry and aggregate; account restore remains one ZIP, 50 GiB. Legacy trial remains 11 MiB and five non-demo imports; active-until and the Cloud ten-million-point boundary remain business admission facts checked again at claim.
- Preparation runs one file at a time, at most 64 MiB buffered working set; originals above 256 MiB use raw fallback with a localized notice. Checksum chunks remain 2 MiB. Reservation expires after 24 hours; inactivity timeout is 120 seconds reset only by actual progress. Durable sweep takes at most 100 rows per batch. Entry, original, aggregate and preparation budgets are independent.
- Upload cancellation is always available. Running import cancellation uses fenced deletion; extraction cancellation uses fenced removal. Export deletion is its fenced cancellation path; no additional cancel action.
- Public shared GET/unlock and invitation landing/acceptance remain HTTP. Anonymous connected reads use a separate read-only session with signed bootstrap, bounded by link/unlock/session expiry and 30 minutes. Reconnect and every delivery recheck owner, audience, phrase/revocation version and exact expiry. No extra connected view count.
- Month/digest/achievement hosts link to native sharing controls and safely back until M5. Main map/studios remain M6. Native pages use no Turbo, Stimulus or ActionCable browser consumer. Retain independent protocols and deferred host consumers.
- Owner secret reveal uses scoped HTTP and transient hook DOM erased on patch/close/destroy. No raw phrase, upload target, signed blob id, password hash or provider credentials in socket/principal/metadata/logs.

## Domain and web seams

All authenticated entrypoints take `Accounts.Scope`; reload the actor/session and target admission. Result vocabulary: `{:ok, value}` or `{:error, reason}`, where reasons are closed atoms (`:stale_session`, `:unauthorized`, `:not_found`, `:invalid_input`, `:expired`, `:claimed`, `:cancelled`, `:limit`, `:unavailable`) or a validation DTO containing field errors without secrets. Web adapters own translated notices and safe refusal destinations. Domain modules never depend on DawarichWeb/Plug/socket.

- `Uploads.reserve(scope, entry, policy)` returns an owner-bound non-authorizing reference. `target(scope, ref, attrs)` returns a transient PUT URL/headers only to authenticated same-origin CSRF-protected bounded HTTP. `claim(scope, refs, operation)` verifies actual stored bytes/checksum, ownership, expiry and current entitlement atomically. `cancel(scope, ref)` is idempotent and arbitrates with claim under the same lock. Account archive restore retains its existing owned-export exception; cleanup never purges attached exports.
- External LiveView metadata contains only `uploader` and `upload_ref`. No framework upload-config mutation or signed capability. Claims resolve references server-side. Pending rows have owner/state/expiry and durable purge intent; tombstones refuse late PUT and restart sweep is bounded.
- `Imports.page/get/create/update/delete/extract/remove_extraction/request_provider/subscribe` own admission and existing durable jobs. `Exports.page/request/delete/subscribe` reuse worker claim/complete/fail contracts and exact download bytes. IDs and format/source payloads are untrusted.
- `Notifications.page/open/mark_all_read/delete/unread/subscribe` preserve 20-row paging, unread-offset and timestamp semantics. Worker `create!` remains; every write records durable owner invalidation in the same transaction, including deletes. Native events never render Turbo HTML.
- `Families.page/locations/create/update/delete/invite/cancel_invitation/accept_invitation/remove_member/request_location/respond_location/set_sharing/subscribe` and `Sharing.page/change` follow the approved plan. Family indicator invalidation carries owner identity only; B reloads an authorized indicator, C owns membership/consent and public read admission.
- Invalidation messages are `{:domain_changed, owner_or_resource_id, version_or_kind}`; ID/version/closed kind only. No emails, title/content, coordinates, phrases or credentials. Subscribe before snapshot; replay/reconnect converges to authorized DB state. Timers have generation tokens and teardown cancels them.
- X1 establishes sanitized job principals and fresh params/event/info/async hooks before A/B page migration. Native refusal clears private snapshots before sign-in or an owned safe destination. Family/public sessions remain separate C integration seams; no same-URL refusal loops.

## Ownership and independent consumers

A owns Uploads, storage lifecycle/migration, Direct uploader/checksum/preparation and Imports. B owns Exports, Notifications, navbar/session and owner relay. C owns Families/Sharing, public admission and family/shared map hooks. X owns minimal route macros, shared principal/redaction/hook registration, structural gates/registers and browser integration. Each track supplies append packets and uses its assigned private runner; no shared database or Redis. Controller scripts and other plan files stay read-only.

Retained `/cable` consumers: deferred main-map/browser modules under `app/javascript/channels`, supported separately built Rails frontend, and Phoenix wire tests (`cable/*`, `cable_wire*`). No production external-client census establishes that all wire consumers can be retired; retain the explicit compatibility adapter. M4 native notifications/family/public hooks cease consuming it. Retained HTTP: storage PUT/blob/representation, import/downloads, API family/shared, public unlock and invitation acceptance, point/trip export and hybrid Points POST `/exports`. Provider shared POST `/settings/background_jobs` retires after A6 caller census. No release/lifecycle/Cloud admission changes.

## Budgets and reproducible baseline

App baseline is inventory commit `96837848a`, E2E `ff256e6`. Telemetry counts only `[:dawarich,:repo,:query]`, excludes Redis, job repo, workers, storage/network/assets and migrations. Synthetic dataset: one owner family and request from the existing recorded fixtures, one ordinary user with 61 imports and exports, 61 notifications, active import/extraction, public link fixtures, empty public month/digest/achievement. No real data.

| Variant | Static | Connected |
| --- | ---: | ---: |
| Imports populated | 6 | 5 |
| New import | 5 | 5 |
| Active import/extraction show | 12 | 7 |
| Active import edit | 10 | 5 |
| Exports populated | 5 | 5 |
| Notifications populated | 7 | 7 |
| Notification detail | 6 | 5 |
| Family owner | 19 | 10 |
| Family edit | 17 | 9 |
| Invitations | 11 | 6 |
| Family outsider new | 9 | 5 |
| Location-request target | 11 | 6 |

Import page patch: 4. Old navbar tick: 1 on every view. Cloud family owner/outsider new HTTP: 19/9. Manager hub/live/timeline/trip HTTP: 11/11/12/13. Public unlocked trip: 12 with resource, 3 absent; track/timeline/live fixture documents: 3; month/digest/achievement: 5/4/4; phrase prompt: 2. Empty/missing public resources are explicitly included; these figures are not populated map capacity guarantees.

New page caps are baseline plus itemized actor/session (one actor read per hook/context boundary), entitlement (one additional current user/count read where required), and target/membership reads measured for the relevant context. No unexplained blanket allowance: task evidence must list actual admission reads and totals. Native navbar periodic queries: zero. Durable relay infrastructure remains singleton: current idle 1 second, failure backoff 5 seconds; native batch bounded at 100 intents.

Production esbuild minified eager graph: `app.js` 166,694 raw / 51,060 gzip bytes; static shared chunk 544 / 337; total 167,238 / 51,397. Lazy emoji/module/demo/style chunks excluded and itemized by the manifest. Common added eager overhead cap: 5 KiB gzip over this baseline, maps/ZIP/gallery always lazy. Root-dependent legacy page graph remains pre-migration and is replaced page by page; X4 records actual transferred graphs from the production stand.

Synthetic 8 MiB original `File.arrayBuffer()` observation: 8 MiB returned original buffer, 16 MiB array-buffer allocation growth in Node; excludes ZIP worker/output/browser/GPU. Rails preparation reads the entire original (`app/javascript/services/zip_file.js:3-13`), so this is a lower-bound memory observation, not a browser peak. The chosen bounded streaming preparation budget must be measured and enforced in A2/X4 before acceptance. Account cleanup baseline: completed/cancelled entry tests pass but no owned pending cleanup occurs before A1/A2; the existing metadata capability gap is a Phoenix defect, not a proven Rails changelog fix.

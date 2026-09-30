Date: 2026-09-30
Repository: https://github.com/Freika/dawarich
Selection: next five open issues by creation time after #3756, #3755, #3754, #3752, #3751.
Worktree: /Users/frey/projects/dawarich/issue-fixes-20260930
Branch: fix/issues-3751-3752-3754-3756
Base: 90c4e9c915022eef6368d2d205ea34891e6bf2f3
Implemented on the review branch; previous four fixes preserved; #3755 excluded.

## Results

- [#3748](https://github.com/Freika/dawarich/issues/3748), names on the family map: confirmed implementation limitation by inspection. Families::Locations returns email and email_initial; FamilyLayer chooses email first. Existing first_name/last_name are not editable in the account form. This is a feature request requiring profile editing and coordinated API/map/list/realtime labels, not a small isolated bug. No change made.
- [#3747](https://github.com/Freika/dawarich/issues/3747), satellite imagery: no dedicated Satellite preset in Maps V2. Custom basemap URL already accepts raster XYZ images or a style JSON document. Use map panel → Settings → Appearance → Custom basemap URL with a suitable provider URL. Existing tests classify hybrid JPG tiles as raster and construct the raster source/layer. No provider credentials or real imagery rendering tested; no provider preset added.
- [#3746](https://github.com/Freika/dawarich/issues/3746), misleading SMTP test: reproduced with request regression, initially no ActionMailer::MailDeliveryJob enqueued because delivery occurred synchronously in the web process. Changed to deliver_later, the same worker path as system mail. Notice explicitly says queued rather than sent. Worker test messages force delivery errors to surface even when normal configuration suppresses them. Verified worker delivery, worker SMTP failure, enqueue failure and unauthorized requests. Synthetic Mail::TestMailer used, no real email sent.
- [#3745](https://github.com/Freika/dawarich/issues/3745), iOS history Pro gate: Rails self-hosted plan request tests confirm features.data_window is null and full features remain available. Cannot reproduce the reported iOS 2.6 behavior without that client build/device; local multiplatform source is not evidence of that released client behavior. No server entitlement workaround or mobile edit made.
- [#3740](https://github.com/Freika/dawarich/issues/3740), archived Immich photos: reproduced using actual RequestPhotos with paginated WebMock responses, archived records returned and no filter sent. Added isArchived:false for legacy API and visibility:timeline for current API on every page. Also rejects returned assets marked isArchived:true or visibility:archive. Photo API and trip-search cache keys now use v2 to ignore old cached results; integration cache refresh clears search caches too. Tests cover both archive response shapes, request filter on each page and old caches. No live Immich server tested.

## Immich compatibility evidence

Current and v2.5.6 Immich search DTOs expose visibility, not isArchived. v2.5.6 validation uses whitelist:true without forbidNonWhitelisted, so obsolete/unknown fields are stripped. The request retains both legacy and current fields; application tests exercise the HTTP boundary but do not run multiple Immich server versions.
Sources:
https://github.com/immich-app/immich/blob/v2.5.6/server/src/dtos/search.dto.ts
https://github.com/immich-app/immich/blob/v2.5.6/server/src/app.module.ts
https://github.com/immich-app/immich/blob/main/server/src/dtos/search.dto.ts

## Verification and support notes

205 RSpec examples passed across Immich, photos, general/integration settings, UsersMailer, plan API and family locations. 33 JavaScript basemap classification/fallback tests passed.
Regression tests were observed failing before the two application fixes. RuboCop checks the 11 Ruby files changed in this sweep; git diff --check checks all accumulated changes.
Tests use a dedicated PostgreSQL/PostGIS database and Redis, synthetic fixtures and stubbed upstreams. No SSH, real mail, production data, commits, pushes or GitHub comments.

After clicking Send test email, successful enqueue does not guarantee delivery. Check the recipient inbox and Sidekiq mailer failure/retry entries; SMTP configuration must be present in the worker container.
Archived Immich photos are intentionally excluded from the common RequestPhotos service, including map/trip display and geodata-import callers.

Repository counterpart: docs/issue-sweep-20260930-next-five.md
Earlier work: docs/adr/20260930-family-trip-audience.md and docs/adr/20260930-geocoding-claims.md.

## Follow-up: #3748 implementation and #3745 mobile inspection

Date: 2026-09-30. Implemented #3748 in the same Rails worktree.

Account settings now expose editable first_name and last_name. Devise permits these only for account updates; existing password-account verification and OAuth update rules remain intact. User#display_name joins trimmed nonblank name parts and falls back to email. A lone first or last name is supported; clearing both restores email labels.

Family location/history JSON, family member serialization, Point callbacks and bulk-ingest live broadcasts add a name field using display_name. Email fields remain compatible. Both family map controllers, the Maps V2 member list, popup/label data and realtime marker updates prefer name over email. Existing escaping/textContent handling remains intact.

Verification: 201 RSpec examples and 507 JavaScript tests passed. RuboCop checked 10 changed Ruby files without offenses. Browser saved Ada Lovelace as Grace Hopper, then reloaded account settings and confirmed both persisted. Family initial/realtime labels, email fallback, partial/blank names, password failure, OAuth edits and location/history payloads have regression coverage. No migration or commit.

For #3745, inspected /Users/frey/projects/dawarich/multiplatform-app at HEAD 983116a with existing uncommitted MapsScreen/dayMetrics changes. No mobile files were changed by this task. MapsScreen.tsx fixes JUMP_MONTHS_BACK to 11, uses it for daily-count queries and the month list; JumpToDateModal clamps year navigation to the supplied list. This yields a 12-month calendar for every account, independent of Pro/self-hosted status. There is no subscription/paywall branch in the current jump-date selection path; handleJumpSelectDate simply selects the day. The plan data_window is not used to choose this calendar window. This confirms a hardcoded history-navigation limit in current sources, but not the reported App Store paywall behavior of released iOS 2.6.

Ran the exact JumpToDateModal Jest suite: 17 tests passed. The component supports older years when supplied in its months list; the screen is what restricts that list. An initial broad Jest path pattern also scanned other worktrees and failed in one unrelated checkout, so the exact --runTestsByPath run is the relevant result. A native iOS 2.6 device/build was not exercised.


## Combined PR verification

Full clean-database RSpec: 10,684 examples, zero failures. JavaScript: 507 tests passed. Playwright E2E: 11 tests passed using installed Chrome and an isolated demo fixture with onboarding completed. RuboCop: 39 changed Ruby files, zero offenses. New strings cover all seven supported locales. No live SMTP or Immich server and no native iOS 2.6 build were exercised. Screenshots are in docs/images/.

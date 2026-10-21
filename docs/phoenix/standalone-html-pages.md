# Standalone HTML GET route parity

The Rails points search form sends `commit=Search` alongside date filters and an empty `import_id`. The native list existed, but its query admission rejected `commit`, so standalone returned a native-gate 500. The list and signed bulk-delete request now accept that scalar form field. Pagination and redirects retain Rails filter behavior; user scoping and CSRF enforcement remain in the existing native implementations.

The Rails characterization script `app-phoenix/scripts/parity/standalone_html_pages_spec.rb` enumerates application GET declarations and captures HTML status plus GET-form submissions using synthetic signed-in fixtures. API endpoints and Rails internal asset/storage infrastructure are excluded from the HTML inventory. Mounted Swagger/operator pages and a public track share are explicitly included. The fixture is `app-phoenix/test/fixtures/standalone/html_pages.json`; `StandaloneHtmlPagesTest` requests every entry through the native Endpoint with `DAWARICH_RAILS=off`.

The inventory contains 97 requests: 87 declarations, five captured form submissions, and five explicit mount/resource requests. Rails returned HTML 200 for 67 requests. Those must render natively, with the already approved Sidekiq redirect to native background-job health treated as 302. This is a server-rendered route gate, not a browser interaction or exhaustive data-state census.

The sweep also closed standalone gaps for scalar tags pagination, admin users with tied creation timestamps, trips whose countries have not been calculated, and public trip/track pages. Shared resources use the existing grant, visibility, photo ACL and privacy implementations. Coexistence retains the existing Rails hand-back for public trip/track pages and ambiguous admin ordering.

The synthetic import has no uploaded file, so its download action raises in Rails and is outside the HTML-200 class. Signed-in Devise redirects, trial routes requiring a token, disabled/self-hosted product routes, JSON/images and retired operator pages are also recorded but do not establish a Rails HTML-200 contract. The sweep does not claim that every redirected or unsuccessful source route succeeds natively.

## Shared-page response and gallery parity

Family-audience shared links use `Cache-Control: private, no-store` after access is authorized, including successful trip, track, timeline and live HTML, missing-resource pages, phrase prompts and unlock responses. Public shares retain their existing cache policy. Family pages render the application root and navigation with the signed-in viewer's theme and navbar context, retaining the shared title and social metadata; public shares retain the public marketing layout. Membership, grant and phrase checks remain in place.

Trip HTML galleries use the complete privacy-filtered photo collection for the grant's owner and date range, matching Rails `SharedLinks::TripPhotos` (`Photos::Mappable` with `max: nil`). There is no HTML gallery limit or pagination. The shared JSON photo API retains its 100-photo cap. Thumbnail authorization continues to use the grant-scoped collection and privacy zones, including photos beyond the JSON cap.

The three named review regressions in `StandaloneHtmlPagesTest` cover a family member across all four shared types, viewer theme, public layout/cache preservation, missing-resource and unlock policies, loss of family membership, and a 101-photo gallery with a later-day photo. The gallery regression also checks JSON limits and refusal of private, unmappable and unknown photo IDs. Each regression fails when its original cache, layout or API-gallery behavior is restored.

The shared AFFiNE counterpart is “Dawarich — Standalone journey sweeps and native confirmation” (document `yOmZHafRYnvfFikBv_3K0`), under the standalone HTML review corrections record.

## Route inventory

Status is the retained Rails response. `error` denotes a source fixture exception. Form values and concrete synthetic identifiers are retained in the JSON fixture rather than repeated here.

| Rails GET declaration / form | Rails status | HTML |
| --- | --- | --- |
| `/admin/settings` | 200 | yes |
| `/sidekiq` | 200 | yes |
| `/settings/general` | 200 | yes |
| `/settings/integrations` | 200 | yes |
| `/settings/trek_sources/:id/select_trips` | 302 | yes |
| `/settings/background_jobs` | 200 | yes |
| `/settings/visits` | 200 | yes |
| `/settings/users/export` | 302 | yes |
| `/settings/users` | 200 | yes |
| `/settings/users/:id/edit` | 200 | yes |
| `/settings/users/:id` | 200 | yes |
| `/settings/two_factor` | 302 | yes |
| `/settings/theme` | 302 | yes |
| `/auth/account_link` | 302 | yes |
| `/auth/account_link/challenge` | 302 | yes |
| `/users/me/destroy/confirm` | 302 | yes |
| `/trial/upgrade` | 302 | yes |
| `/trial/resume` | 302 | yes |
| `/trial/welcome` | 302 | yes |
| `/imports/:id/download` | error | no |
| `/imports` | 200 | yes |
| `/imports/new` | 200 | yes |
| `/imports/:id/edit` | 200 | yes |
| `/imports/:id` | 200 | yes |
| `/tracks/:track_id/segments` | 200 | yes |
| `/tracks/:track_id/share_link/new` | 200 | yes |
| `/visits` | 302 | yes |
| `/places/nearby` | 200 | yes |
| `/places` | 200 | yes |
| `/places/:id` | 302 | yes |
| `/exports` | 200 | yes |
| `/trips/:trip_id/share_link/new` | 200 | yes |
| `/trips` | 200 | yes |
| `/trips/new` | 200 | yes |
| `/trips/:id/edit` | 200 | yes |
| `/trips/:id` | 200 | yes |
| `/share_links/hub` | 200 | yes |
| `/share_links/timeline/new` | 200 | yes |
| `/share_links/live/new` | 200 | yes |
| `/tags` | 200 | yes |
| `/tags/new` | 200 | yes |
| `/tags/:id/edit` | 200 | yes |
| `/s/:id` | 200 | yes |
| `/family/invitations` | 200 | yes |
| `/family/invitations/new` | 404 | yes |
| `/family/invitations/:id` | 200 | yes |
| `/family/location_requests/:id` | 200 | yes |
| `/family/new` | 302 | yes |
| `/family/edit` | 200 | yes |
| `/family` | 200 | yes |
| `/invitations/:token` | 200 | yes |
| `/points/:id/address` | 200 | yes |
| `/points` | 200 | yes |
| `/notifications` | 200 | yes |
| `/notifications/:id` | 200 | yes |
| `/stats` | 200 | yes |
| `/achievements` | 200 | yes |
| `/achievements/:key` | 200 | yes |
| `/insights/details` | 200 | yes |
| `/insights` | 200 | yes |
| `/stats/:year` | 200 | yes |
| `/stats/:year/:month` | 200 | yes |
| `/shared/month/:uuid` | 200 | yes |
| `/shared/achievements/:uuid/og.png` | 200 | no |
| `/shared/achievements/:uuid` | 200 | yes |
| `/digests` | 200 | yes |
| `/digests/:year` | 200 | yes |
| `/shared/digest/:uuid` | 200 | yes |
| `/` | 302 | yes |
| `/auth/ios/success` | 200 | no |
| `/users/auth/apple` | 404 | yes |
| `/users/sign_in` | 302 | yes |
| `/users/password/new` | 302 | yes |
| `/users/password/edit` | 302 | yes |
| `/users/cancel` | 302 | yes |
| `/users/sign_up` | 302 | yes |
| `/users/edit` | 200 | yes |
| `/users/unlock/new` | 302 | yes |
| `/users/unlock` | 302 | yes |
| `/map/v1` | 301 | yes |
| `/map/v2` | 200 | yes |
| `/map/timeline_feeds/:id/track_info` | 200 | yes |
| `/map/timeline_feeds/calendar` | 200 | yes |
| `/map/timeline_feeds` | 200 | yes |
| `/map/residency` | 200 | yes |
| `/map` | 200 | yes |
| `/maps/v2` | 301 | yes |
| `/settings/users (captured form)` | 200 | yes |
| `/points (captured form)` | 200 | yes |
| `/achievements/:key (captured form)` | 200 | yes |
| `/map/v2 (captured form)` | 200 | yes |
| `/map (captured form)` | 200 | yes |
| `/api-docs` | 301 | no |
| `/api-docs/index.html` | 200 | yes |
| `/sidekiq` | 200 | yes |
| `/admin/flipper` | 302 | no |
| `/s/:id (track)` | 200 | yes |

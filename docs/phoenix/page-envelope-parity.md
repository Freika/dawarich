# Standalone page request envelopes

When `DAWARICH_RAILS=off`, `DawarichWeb.PageEnvelope` normalizes successful Rails page envelopes before Strangler admission. Coexistence keeps its existing handback rules and Turbo visit reload. Cloud native lifecycle refusal is unchanged.

HTML suffixes and `format=html` select the existing native handler, with suffix precedence over the query format. The format query key is removed before existing query gates run. Authentication stores the original target, including its suffix and query.

XHR with an HTML Accept header renders the ordinary document. A JavaScript, absent or empty XHR Accept header uses Rails' JavaScript-to-HTML template fallback without a layout; the calendar action retains its Rails 406 because it explicitly negotiates formats. Unauthenticated HTML XHR receives the Rails 401 message rather than a sign-in redirect.

Turbo-only requests preserve successful redirects and the calendar Turbo stream. Ordinary HTML-only templates retain Rails' 406; the residency and nearby-place partial requests retain Rails' missing-template failure. Turbo frame pages use the minimal frame layout; map pages retain their explicit map layout, and share creation forms remain fragments. Turbo document visit headers keep standalone pages native.

The three historical navigation actions return the exact turbo-rails HTML text, including for formatted requests and HEAD. They are bound only in standalone mode; coexistence hands them back.

## Verification

`test/fixtures/page_envelopes/routes.json` records the 62 assigned audit rows. `scripts/parity/page_envelopes_fixtures_spec.rb` records Rails status, media type, redirects, template identifiers, document shape, flash and job classes for nine request variants and the three historical actions. `test/dawarich_web/page_envelopes_test.exs` verifies envelope classes, route selection, authentication, layout exceptions, Turbo streams, refusals and coexistence. Each envelope class has a named mutation.

## Covered GET/HEAD routes

- `/` (R0202)
- `/admin/settings` (R0010)
- `/digests` (R0196)
- `/digests/:year` (R0198)
- `/exports` (R0101)
- `/family` (R0164)
- `/family/edit` (R0163)
- `/family/invitations` (R0151)
- `/family/invitations/:id` (R0154)
- `/family/invitations/new` (R0153)
- `/family/location_requests/:id` (R0160)
- `/family/new` (R0162)
- `/imports` (R0067)
- `/imports/:id` (R0071)
- `/imports/:id/download` (R0064)
- `/imports/:id/edit` (R0070)
- `/imports/new` (R0069)
- `/insights` (R0188)
- `/insights/details` (R0187)
- `/invitations/:token` (R0169)
- `/map` (R0232)
- `/map/residency` (R0231)
- `/map/timeline_feeds` (R0230)
- `/map/timeline_feeds/:id/track_info` (R0228)
- `/map/timeline_feeds/calendar` (R0229)
- `/map/v2` (R0227)
- `/notifications` (R0174)
- `/notifications/:id` (R0175)
- `/places` (R0095)
- `/places/:id` (R0097)
- `/places/nearby` (R0094)
- `/points` (R0173)
- `/points/:id/address` (R0172)
- `/s/:id` (R0149)
- `/settings/general` (R0014)
- `/settings/integrations` (R0018)
- `/settings/theme` (R0053)
- `/settings/users/export` (R0033)
- `/settings/visits` (R0028)
- `/share_links/hub` (R0128)
- `/share_links/live/new` (R0139)
- `/share_links/timeline/new` (R0133)
- `/shared/achievements/:uuid` (R0194)
- `/shared/achievements/:uuid/og.png` (R0193)
- `/shared/digest/:uuid` (R0200)
- `/shared/month/:uuid` (R0192)
- `/stats` (R0180)
- `/stats/:year` (R0189)
- `/stats/:year/:month` (R0190)
- `/tags` (R0142)
- `/tags/:id/edit` (R0145)
- `/tags/new` (R0144)
- `/tracks/:track_id/segments` (R0075)
- `/tracks/:track_id/share_link/new` (R0081)
- `/trial/resume` (R0062)
- `/trial/upgrade` (R0061)
- `/trial/welcome` (R0063)
- `/trips` (R0120)
- `/trips/:id` (R0124)
- `/trips/:id/edit` (R0123)
- `/trips/:trip_id/share_link/new` (R0117)
- `/trips/new` (R0122)
- `/recede_historical_location`
- `/resume_historical_location`
- `/refresh_historical_location`

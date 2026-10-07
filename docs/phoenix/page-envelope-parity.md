# Standalone page request envelopes

When `DAWARICH_RAILS=off`, `DawarichWeb.PageEnvelope` normalizes successful Rails page envelopes before Strangler admission. Coexistence keeps its existing handback rules and Turbo visit reload. Cloud native lifecycle refusal is unchanged.

HTML suffixes and `format=html` select the existing native handler, with suffix precedence over the query format. Explicit HTML also overrides the implicit XHR fragment layout. The format query key is removed before existing query gates run. Authentication stores the original target, including its suffix and query.

`DawarichWeb.PageAccept` follows the pinned Rails MIME negotiation: parameters and quoted commas are parsed independently, qualities sort descending with stable ties, aliases and wildcards use Rails' MIME registration order, and browser-like headers retain Rails' HTML fallback. Ordered alternatives remain available to template lookup; a mixed Turbo/HTML header can still render an HTML-only page. The parser ports Rails' single-entry and comma-list branches, MIME validation before unknown-type filtering, XML ordering and Ruby numeric coercion, including leading decimals, numeric prefixes, dotted exponents (`1.e-1` becomes `0.1`) and underscores. Zero-quality entries remain available, and ties use Rails' integer quality precision. Malformed MIME alternatives in negotiated lists return a halted 406 before frame-header normalization; valid unregistered types are filtered only after the entire list has been validated. Browser-like fallback applies only to non-XHR requests.

XHR with an HTML alternative renders the ordinary document, even when JavaScript has higher quality. Only a sole JavaScript format (including parameterized MIME types), absent or empty XHR Accept header uses Rails' JavaScript-to-HTML template fallback without a layout; the calendar action retains its Rails 406 because it explicitly negotiates formats. Unauthenticated HTML XHR receives the Rails 401 message rather than a sign-in redirect.

Turbo-only requests preserve successful redirects and the calendar Turbo stream. Ordinary HTML-only templates retain Rails' 406; the residency and nearby-place partial requests retain Rails' missing-template failure. Accessible shared monthly and digest pages explicitly render named templates, so source-refused Turbo requests retain Rails' `ActionView::MissingTemplate` status of 500; missing shared records still redirect. All shared stats document rendering passes through the same envelope layout seam. Turbo frame pages use the minimal frame layout; map pages retain their explicit map layout, and share creation forms remain fragments. Turbo document visit headers keep standalone pages native.

The three historical navigation actions return the exact turbo-rails HTML text, including for formatted requests and HEAD. They are bound only in standalone mode; coexistence hands them back.

## Verification

`test/fixtures/page_envelopes/routes.json` records the 62 assigned audit rows. `scripts/parity/page_envelopes_fixtures_spec.rb` records Rails status, media type, redirects, template identifiers, document shape, flash and job classes for nine request variants and the three historical actions, plus raw, unauthenticated and formatted XHR probes. `test/dawarich_web/page_envelopes_test.exs` verifies envelope classes, route selection, authentication, layout exceptions, Turbo streams, refusals and coexistence. Each envelope class has a named mutation. `scripts/parity/page_envelope_review_fixtures_spec.rb` and the `f1`–`f4` fixtures add successful shared monthly/digest records, parameterized JavaScript XHR, calendar quality/tie cases, mixed-header HTML fallbacks and explicit-template errors. The native F1–F4 tests replay those source contracts and compare MIME-format ordering directly with Rails, including quoted qualities, zero qualities, wildcard expansion and unknown types. `scripts/parity/page_accept_fixtures_spec.rb` generates 526 distinct Accept headers and runs the Rails formats and calendar negotiation oracle for both XHR and non-XHR (1,052 probes). It includes browser defaults, Turbo, curl, JavaScript, malformed MIME lists, quality coercion, quoted parameters, aliases and XML ordering. `test/dawarich_web/page_accept_test.exs` replays every ordered format list, malformed-type refusal and calendar selection. The F5–F7 source and endpoint tests separately verify both leading-decimal calendar directions, mixed malformed/unknown types, and full tags layout plus successful calendar rendering for mixed JavaScript/HTML headers. F8 replays both dotted-exponent calendar directions with and without XHR, alongside leading-decimal and garbage numeric prefixes. F9 replays the place and share-hub malformed-MIME refusals with and without frame headers and asserts exactly one send.

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

# Open Graph previews for public shares — feasibility analysis

Last updated: 2026-09-23

## Current behavior

| Public URL | Content | Current preview |
| --- | --- | --- |
| `/s/:id` | Trip, track, timeline, live | `og:image` points to the same 512×512 `og_default.png` for every link. |
| `/shared/month/:uuid` | Monthly statistics | No page-specific Open Graph tags. |
| `/shared/digest/:uuid` | Yearly digest | No page-specific Open Graph tags. |
| `/shared/achievements/:uuid` | Achievement card | Dedicated 1200×630 PNG card at `/shared/achievements/:uuid/og.png`. |

The maps and charts on these pages are client-rendered. A link preview therefore needs a separate, publicly retrievable image URL; pointing `og:image` to the HTML page cannot capture the rendered map. `/s/:id` already sets `og:title`, `og:description`, and `twitter:card`, so its metadata is a simple integration point.

## Feasible approach

Generate a dedicated landscape image for each public share, combining the permitted map or card with a short title and summary. Use a stable image endpoint and include its absolute URL, dimensions, type, and alt text in the page metadata. Generate asynchronously when the share is created or first requested, and return a generic fallback while rendering is pending. Keep serving the generated image through an endpoint that rechecks the share's active and access state, rather than exposing an unrevocable storage URL.

Trip, track, and timeline maps are feasible with the existing `vendor/poster_renderer` MapLibre Native renderer, but it requires an OG-sized layout and a public-share-specific data adapter. The existing `Posters::TrackBuilder` reads raw user points and must **not** be reused for this purpose. Public points currently pass through `Api::V1::Shared::PointsController`, which excludes privacy zones and caps data at 10,000 points. The image pipeline must apply equivalent filtering before rendering, and must also respect `SharedLinkContext` flags such as `show_route?` and `show_stats?`. It should not call the public HTTP endpoint from inside the worker merely to obtain the points.

Monthly stats, yearly digests, and achievements are better represented as purpose-built summary cards. A literal screenshot would involve a browser and asynchronous maps/charts; it would be more brittle and operationally expensive. Live location should use a non-location-specific card because social platforms cache previews and a public image can outlive the current location or a revoked share.

## Achievement card implementation

The public achievement page now supplies an absolute PNG URL, dimensions, MIME type, alt text, canonical page URL, and large Twitter card metadata. `Shared::AchievementsController#image` uses the same share authorization and owner locale as the HTML page. It returns 404 when sharing or the achievement feature is disabled, and sends `Cache-Control: private, no-store` so an intermediary does not continue to serve a revoked card. The PNG is generated from `Achievements::SetPresenter` with the same region silhouette, title, rarity, and progress data as the visible card. A one-hour internal cache key includes the progress ID, achievement key, owner locale, and digest of the current exploration state; each request checks authorization before looking up that cache.

`Achievements::OgImage` renders an SVG template through `rsvg-convert`. The runtime image installs `librsvg2-bin`, DejaVu fonts, and Noto CJK fonts. Local development needs `rsvg-convert` on `PATH` (for example, `brew install librsvg` on macOS). Verify with `bundle exec rspec spec/services/achievements/og_image_spec.rb spec/requests/shared/achievements_spec.rb`. The generated PNG is a purpose-built social layout rather than a literal screenshot of the interactive CSS card.

Representative output with synthetic progress: [achievement OG preview](../screenshots/achievement-og-preview.png).

## Access and freshness constraints

- Phrase-protected shares must get a generic image. Image crawlers will not carry the viewer's unlock cookie, and exposing a map via the image endpoint would bypass the phrase.
- Revoked, expired, disabled, and deleted resources must stop serving their custom image. The `/s/:id` HTML already checks active links; the image endpoint needs the same check. Monthly and yearly shares use `public_accessible?` instead.
- Changes to share settings, route data, and privacy zones must invalidate or regenerate the image. A privacy-zone change is security-sensitive; serving an older image can continue to expose previously visible locations.
- Social platforms may cache both page metadata and images outside Dawarich. Dawarich cannot guarantee immediate removal of a preview already fetched by a third party. Avoid live coordinates and sensitive details in OG cards, even for ordinary public shares.
- The native renderer relies on a tile service and is installed only on x64 and arm64 container builds. Other architectures need a simpler image fallback or a different renderer.
- Put generation on a worker queue with timeouts and rate limits; do not render maps during page or image requests. Avoid writing personal location data into job logs or temporary artifacts beyond the controlled renderer lifecycle.

## Suggested rollout and verification

1. Add a public-share image endpoint, a generic fallback, correct Open Graph metadata, and request tests for authorization and revocation.
2. Render trip/track/timeline route cards from the same privacy-filtered source as the public viewer; test disabled route, privacy zones, phrase protection, expiry, and missing resources.
3. Add monthly/yearly summary cards. Achievement cards are implemented; keep live shares generic.
4. Verify generated images with representative long and empty routes, both container architectures, external preview debuggers, and image-request cache behavior.

**Rough effort:** about 3–5 engineering days for route-card MVP, then about 4–8 more days for all share types, invalidation, cross-platform fallback, and validation. These are planning estimates, not measured implementation times.

## Relevant code

- `app/views/shared/links/show.html.erb`
- `app/controllers/shared/links_controller.rb`
- `app/policies/shared_link_context.rb`
- `app/controllers/api/v1/shared/points_controller.rb`
- `app/services/posters/native_renderer.rb`
- `vendor/poster_renderer/render.mjs`
- `app/controllers/shared/stats_controller.rb`
- `app/controllers/shared/digests_controller.rb`
- `app/views/shared/achievements/show.html.erb`

Open Graph specification: <https://ogp.me/>

# Spectral collectible cards

The v15 reference material from the Spectral Cartogram playground now renders
achievement cards in the collection, country/subdivision pages, fullscreen dialog
and public shared pages. Rarity, progress and earned dates still come from the
achievement registry and user progress; no reference-demo values replace them.
For example, Brazil is Rare in the current registry and uses blue/teal foil,
whereas the playground's Legendary reference uses blue/petrol/gold.

## Rendering

- `app/javascript/achievements/spectral_material.js`: material math, palettes,
  deterministic crops and normalized PostGIS polygon paths.
- `app/javascript/controllers/achievement_card_controller.js`: lazy material
  hydration, resize fitting and pointer-driven tilt/spectrum movement.
- `app/assets/stylesheets/achievements_spectral.css`: scoped material and layout.
- `app/views/achievements/_card.html.erb`: accessible content and no-JS silhouette.
- `app/assets/images/achievements/`: two shared WebPs, 1.64 MiB in total.

The existing boundary cache is retained; collections load twelve cards per page. No card uses
map tiles, a map instance, a dedicated raster asset, decorative GPS routes or
white glare. Material textures stay stationary while the spectrum changes on
tilt. Touch and reduced-motion users see the static finish. Missing boundaries
are explicitly labeled instead of inventing geography. A country has the same
material seed on its detail page, continent tile and shared card.

### Geographic framing

`Achievements::RegionSilhouettes` prepares display geometry separately from the
stored PostGIS boundaries. Mainland-focused country artwork for France,
Portugal, Norway, the Netherlands and Spain excludes distant possessions from
the card's fit calculation. Nearby islands such as Corsica and the Balearics
remain; other archipelagos are not reduced to their largest polygon.

Europe uses a regional atlas window (25°W–60°E, 34°N–72°N), so the illustration
does not shrink to include its members' overseas land or the Russian Pacific.
The eastern cutoff is a display crop, not an asserted national/continental border.
Continent/world paths are assembled from original boundaries in one common
coordinate frame, not from the individually cropped country cards. Longitudes
are [unwrapped](https://postgis.net/docs/ST_ShiftLongitude.html) when the 0–360°
domain fits the shape within one hemisphere, keeping Russia and Pacific islands
together without introducing a new seam through Greenwich on world cards.

Framing never changes country membership, visit detection, progress or totals.
No geometry rows or source assets are modified. The versioned SVG cache includes
the collection membership and framing key. Materialized SQL stages prevent the
planner from duplicating expensive framing/simplification expressions.

## Local preview

This worktree's local preview uses an ignored `tmp/spectral-local.env`, isolated
Docker PostgreSQL/Redis containers, and a development server bound to
`127.0.0.1:3016`. Its demonstration progress is synthetic, not imported user data.
Credentials are intentionally not committed. To restart the web process after
stopping it, from this worktree:

```sh
set -a
source tmp/spectral-local.env
set +a
asdf exec bundle exec rails server -b 127.0.0.1 -p 3016
```

## Checks

```sh
node --test spec/javascript/spectral_material_test.mjs
bundle exec rspec spec/services/achievements/set_presenter_spec.rb \
  spec/services/achievements/region_silhouettes_spec.rb \
  spec/requests/achievements_spec.rb spec/requests/shared/achievements_spec.rb
```

Use a separate test database for RSpec. Browser checks cover login, country and
collection pages, lazy hydration, responsive sizing, modal reparenting, tilt,
stationary paper and the absence of the previous glare layer.

## Application UI

The collection pages reuse Dawarich's page header, Inter typography, DaisyUI
theme tokens and standard form/pagination controls. Only the collectible itself
keeps its fixed dark material. Desktop navigation becomes an inline, native
disclosure above the content on mobile; it does not require JavaScript.

Country and region searches (accent-insensitive) and status filters run over the
whole collection before twelve-card pagination. Only visible cards load geometry.
Sharing returns to the page where it was changed. Empty searches have a clear
reset action; new collections retain their cards and offer an import entry point.

The Impeccable refinement preserves the card materials. Its detector's font
warnings refer to retained legacy TCG rules; the application font is deliberately
inherited rather than replaced. Browser checks cover both themes, 320–1440 px,
navigation, search, filters, pagination and modal restoration.

Detail pages place the native page title above the main content, aligned with
the featured card rather than the navigation sidebar. With at least 54rem of
main-pane space, a 300px featured card sits beside the countries/regions
collection. A shared header track aligns the top edges of both card groups:
one readable progress summary sits above the featured card, while the collection
heading, range, previous/next controls and filters sit above the grid. Browsers
without CSS subgrid retain independently stacked sections. Sharing actions use
the native page-header slot; the initial action explicitly says “Create public
link.” The repeated external description, status and rarity have been removed.

Below that threshold the sections stack, with a native “Browse countries/regions”
anchor before the featured card. Top and bottom pagination avoid traversing the
whole collection just to change pages; twelve cards fill three- and four-column
desktop rows. Search uses a native GET form to preserve `#collection`, which
Turbo's form submission discarded. The fragment target is keyboard-focusable.
The overview is not sticky and the card materials are unchanged.

At card widths up to 280px, functional status/progress type is 12px rather than
9px, with wrapping, 13px icons, 11px rarity and a 9px imprint. The map flexes to
leave room for the copy; no new font or raster assets are required. Closing a
card dialog restores focus to the same moved-and-reinserted trigger, without
scrolling. Isolated JS regression tests cover all close paths and stale origins.

The preview reserves responsive 24–64px clearance around the enlarged card so
its ±10° perspective tilt and shadow do not hit the dialog's overflow boundary.
The 480px desktop cap is retained; narrower viewports account for this clearance.
Sharing panels remain scrollable on short screens. The link field uses 16px text
to avoid iOS focus zoom. “Create public link” opens this preview and reveals the
copyable URL directly, with explicit enable/disable HTML fallbacks. Requests are
single-flight, late responses stay attached to their original card, and header
controls are synchronized with modal sharing. Clipboard failures offer manual
copy instead of reporting false success.

Mounted cards refit synchronously on controller reconnection when moved into
or out of the preview. Waiting for IntersectionObserver exposed the old compact
map scale for a painted frame before shrinking it to fit the enlarged layout.
Initial offscreen collection cards remain lazy-mounted; ResizeObserver still
handles viewport changes without replacing the material or geometry.

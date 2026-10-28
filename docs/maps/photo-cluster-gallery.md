# Map photo cluster gallery

Issue: [#3652](https://github.com/Freika/dawarich/issues/3652). Last updated: 2026-10-28.

Status: implemented for review on `codex/photo-cluster-gallery-3652`, based on
`origin/dev` at `13ec7af9e`. Release pending.

## Behavior

Clicking a photo cluster opens a modal gallery without changing the map zoom.
The gallery replaces its page of up to 24 thumbnails when Previous/Next is pressed.
Selecting a thumbnail opens the existing photo preview with filename, capture time,
location, source and media type. Back returns to the same page and focused thumbnail.
Only thumbnail URLs are used; originals and videos are not downloaded or played.

The close button, Escape and clicking the backdrop dismiss the gallery. Focus returns
to the map canvas. With the canvas focused, Enter opens the visible photo cluster
nearest the map centre; arrow keys retain MapLibre's map navigation. Native modal
behavior makes the underlying page inert while the gallery is open. On phones,
the thumbnail area scrolls independently so close and paging controls stay visible.
Loading, failed page requests (with Retry), empty results and missing thumbnails
have explicit messages. Strings are provided in all seven supported locales.

The source uses `maxzoom: 24` / `clusterMaxZoom: 23`, keeping coincident photos
clustered throughout MapLibre's default map zoom range (maximum 22). Nearby photos
still separate as the map zooms. Individual photo markers retain their popup and
overlap layout. Cluster circle/count ordering is unchanged.

## Implementation and boundaries

- `app/javascript/maps_maplibre/layers/photos_layer.js` owns the gallery and binds
  its lifetime to that layer/source. Update, hide, remove, map removal and source
  replacement close the gallery. Style restoration already removes old layers.
- `app/javascript/maps_maplibre/components/photo_cluster_gallery.js` uses the
  Promise API `GeoJSONSource.getClusterLeaves(clusterId, 24, offset)` in MapLibre
  GL JS 6.16.0. It never requests `Infinity` or expands every leaf into markers.
  A request generation and destroyed flag discard stale responses, including
  rejected responses after closing or a data/style change. The worker request
  itself cannot be aborted through this API.
- One page's metadata and image elements are retained, plus the selected preview;
  earlier pages are replaced. Image loading is lazy. Provider listing/source data
  loading remains unchanged: this paginates cluster leaves in the existing source,
  not the upstream Immich/PhotoPrism listing endpoint.
- `PhotoPopupFactory` supplies the existing escaped preview markup and timezone
  formatting. Thumbnail buttons use DOM properties/text, not interpolated HTML.
- The existing feature's `thumbnail_url` is reused unchanged, preserving the
  application proxy, authentication and provider/share scope. No integration key,
  URL or original media URL is constructed or logged by the gallery.
- Presentation is scoped under `.photo-cluster-gallery` in
  `app/assets/stylesheets/maps_maplibre.css`. A modal remains within the viewport
  and supports light/dark themes.

API reference: [MapLibre GeoJSONSource#getClusterLeaves](https://maplibre.org/maplibre-gl-js/docs/API/classes/GeoJSONSource/#getclusterleaves).

## Verification

```sh
npm ci --ignore-scripts
npm test
node spec/browser/photo_cluster_gallery_server.mjs
# In another terminal, from this worktree:
mkdir -p tmp/photo-cluster-evidence
playwright-cli -s=photo3652 open http://127.0.0.1:8796 --persistent
playwright-cli -s=photo3652 run-code --filename=spec/browser/photo_cluster_gallery.check.cjs
playwright-cli -s=photo3652 close
```

The loopback-only harness uses the installed MapLibre version and real worker,
production PhotosLayer/gallery/preview/CSS, 101 coincident synthetic photos and
one single marker. It stubs the authenticated thumbnail proxy with generated SVGs.
The blank offline map omits glyph-dependent cluster labels; the existing layer
ordering regression covers the unchanged circle/count layers. No Rails server,
DB, Redis, production data, live Immich or external basemap is required. Default
port 8796 can be changed with `PHOTO_GALLERY_PORT`; update the check URL accordingly.
Stop only the harness process you started when finished.

Browser assertions cover real cluster clicks and bounded Promise pagination through
all 101 photos; detail/back and escaped metadata; Enter/Escape/focus; desktop
1440×1000 and mobile 390×844 with dark theme; maximum zoom; stale responses after
date updates; error/retry/empty; hide/show; style teardown/rebuild; and single-photo
popups. Screenshots and browser output are written under `tmp/photo-cluster-evidence/`.
The Node suite additionally covers overlapping page responses and idempotent cleanup.

2026-10-28 verification: 741 Node tests passed; Biome passed for changed JS/CSS
and browser checks; `git diff --check` passed. Ruby 4.0.9 and Bundler dependencies
became available during finish review. The focused layer-order/photo API/shared
API/serializer/service set passed 56 examples, followed by 269 passing nested
Swagger examples. RuboCop passed for the changed regression spec.

A second browser check exercised the actual Rails Map v2 page with a synthetic
signed-in user on a dedicated PostGIS database and Redis instance. It loaded 102
synthetic photos through a loopback Immich stub, then used the real authenticated
Rails thumbnail proxy to display JPEGs. Importmap resolution, Rails translations,
actual `dawarich-dark` theme, a 101-photo cluster, 24-item pagination, detail/back,
Escape/focus, and desktop/mobile viewports passed. Evidence is in
`tmp/photo-cluster-evidence/rails-{desktop,mobile}.png` and `rails-gallery-check.log`.
A regression first failed for the real dark theme, then passed after both gallery
and detail selectors were corrected. The standalone harness now uses actual
Dawarich theme names and asserts the computed dialog background.

The full Rails UI check observed pre-existing 404s for empty hexagon bounds and
the default cluster font stack at the external glyph host; the new gallery had no
failed thumbnail loads. Cluster count glyph rendering was therefore not verified.
No live Immich or production data was used. Puma's default forked workers crashed
in the local pg native extension; the UI check passed with `WEB_CONCURRENCY=0`.
A full RSpec run uses another isolated test database; its outcome is recorded
separately in the PR, rather than inferred from these focused checks or remote CI.

Shared knowledge-base counterpart: **Dawarich — Map photo cluster gallery**,
AFFiNE docId `oRqgN2k5XyAzgoGWhFUWO`.

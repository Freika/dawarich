# Exploration geographic data

Pinned source: [Natural Earth vector repository, v5.1.2](https://github.com/nvkelso/natural-earth-vector/tree/v5.1.2/geojson).

- `countries.geojson.gz`: `ne_10m_admin_0_countries_lakes.geojson`.
- `lakes.geojson.gz`: `ne_10m_lakes.geojson`.
- `checksums.json`: SHA-256 of each original download and the bundled gzip.

Natural Earth data is [public domain](https://www.naturalearthdata.com/about/terms-of-use/). Attribution: Natural Earth. The repository release is 5.1.2; individual layers have their own upstream version history.

The bundle preserves source coordinates. Country properties are reduced to ADM0_A3, ISO_A2_EH, NAME_EN, ADMIN and NAME; lake properties are unnecessary. Gzip uses mtime 0. Country identity uses ADM0_A3, including territories without an ISO country code. This is a geographic dataset convention, not a political statement.

`Exploration::Geography` repairs geometry with PostGIS, subtracts mapped inland water, validates each result and calculates WGS84 spheroidal land area. The same resulting land geometry clips each resolution-9 H3 cell. No network download is needed at runtime.

The 1:10m scale is generalized: coastlines and small water bodies are not street-level ground truth. UI percentages explicitly carry this limitation. Dataset subdivisions and disputed territories follow Natural Earth. City and park extensions are pinned separately in `../achievement_collections/`. World totals use the union of country land and never sum overlapping cities or parks.

To update: pin the next upstream release, regenerate these assets preserving coordinates, record both checksums, and change `Exploration::Geography::VERSION`. Validate representative countries, islands, water holes, borders, and dateline/polar cells. Bump the version for changes to geometry preparation or eligibility rules too. Previously published snapshots retain their own dataset until a replacement completes.

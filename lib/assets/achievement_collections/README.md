# City and national-park catalog

Pinned pilot: `germany-pilot-20261028-v1`, public OpenStreetMap data fetched on
2026-10-28. Attribution: © OpenStreetMap contributors, [ODbL 1.0](https://www.openstreetmap.org/copyright).
The bundled GeoJSON is a derived database distributed under ODbL 1.0. Preserve
this notice, source identities and attribution when redistributing it.

| Stable OSM relation | Kind | Boundary |
| --- | --- | --- |
| 62422 | city | Berlin, administrative level 4 (city state) |
| 62782 | city | Hamburg, administrative level 4 (city state) |
| 191645 | city | Dresden, administrative level 6 |
| 90584 | park | Harz National Park |
| 1595534 | park | Saxon Switzerland National Park |
| 2345991 | park | Eifel National Park |

`source.overpass` selects these exact identities. The original retrieval used
name queries, followed by a corrected Dresden level-6 query; unrelated level-8
Dresden matches were discarded. Each feature retains its OSM version and edit
timestamp, and the bundle retains the Overpass database timestamp. No user
location or history was sent to a geodata service. Runtime uses only local files.
This is a curated regional pilot, not a worldwide or complete German catalog.

`script/build_achievement_catalog.rb` assembles outer/inner relation ways with
PostGIS `ST_BuildArea`, preserves holes, validates geometry and positive area,
serializes seven decimal places and writes deterministic gzip (`mtime=0`) and a
SHA-256 manifest. Run it with saved public Overpass JSON inputs on an isolated
local PostGIS database, through `bundle exec rails runner`. It performs no network
requests. A relation with missing member geometry must be corrected before use.

To add or update boundaries: review official administrative/protection status,
keep one canonical relation per place (never duplicate nested boundaries),
update `manifest.json` and the source query, rebuild the
bundle and checksum, and bump both `Exploration::Catalog::VERSION` and
`Exploration::Geography::VERSION`. Update UI catalog descriptions and regional
coverage. Never change geometry under an existing version. Subject `code` is an explicit internal identity: retain it even if OSM replaces a relation, and update only its source `osm_id`. Renaming a source must not mint another card. Check holes, coastal
water, administrative forests/outskirts, valid IANA timezones, actual point
membership and overlapping parks before release.

At installation, `Exploration::Catalog` verifies checksums/version and clips
city land to the same Natural Earth 5.1.2 land/water mask used by exploration.
Small water bodies absent at 1:10m remain a known approximation. Park **time**
uses actual points within the OSM boundary, never cell intersection. Historical
snapshots keep their dataset until a complete replacement is published.

## Geographic milestone globe artwork

`globes.json` contains display-only SVG paths for an equatorial view and two
views tilted 55° toward the north/south pole. Continents use the existing local
Natural Earth 5.1.2 land geometry, simplified by 0.18° and omitting islands below
500 km² for legibility. It is an illustration, never an eligibility or area input.
The asset records its export SHA-256, source/version and generator version.

Rebuild using an isolated local database containing the bundled geography:

```sh
bundle exec rails runner script/export_achievement_globe_land.rb tmp/achievement-globe-land.geojson
npm install --prefix tmp/achievement-globe-generator --no-save --ignore-scripts --no-audit --no-fund d3-geo@3.1.1
node script/build_achievement_globes.mjs tmp/achievement-globe-land.geojson
```

The build uses [D3's orthographic projection](https://d3js.org/d3-geo/azimuthal#geoOrthographic)
and spherical clipping, graticules and region polygons. D3 is only a pinned build
tool in ignored `tmp/`; no runtime/npm dependency or network call is added to the
app. RFC7946 polygon winding is adapted to D3's spherical convention. Natural
Earth source data remains public domain. The polar highlight uses the fixed
66.56° game latitude; `GlobeArtwork` checks that the bundled value matches the rule.

The same global continent outlines, grid and explicit region separators appear
in fallback SVG, the Spectral material and social PNGs. Completed hemispheres
keep contrasting tints; quarters keep four tints. Unsupported regions stay dark.
Polar cards retain the whole globe and highlight just the cap. Colors and
separators are illustrative; credit remains based solely on recorded evidence.

The shared silhouette contract adds optional `details` layers: `path`, `fill`,
`stroke`, `stroke_width` in viewBox units, and `opacity`. They render above the
unvisited mask so the global frame remains readable. Fallback SVG stores these
as `data-detail` attributes; hydration normalizes coordinates and stroke width
with the same transform as the main geometry. The client accepts M/L/Z paths,
`none` or six-digit hex paints, finite widths from 0 to 2, and opacity from 0 to 1;
raw markup, external paint servers and invalid attributes are rejected.

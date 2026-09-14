# Bundled Visited Countries boundaries

Visited Countries uses a bundled PMTiles v3 archive generated from the same canonical GeoJSON source used by the Country database seeds. The browser requests only the byte ranges needed for the current viewport; no Point coordinates or full border GeoJSON are loaded by the main map.

## Native zoom selection

Both accepted native maximum zooms were generated from the pinned recipe on 2026-09-14:

| Native max zoom | Archive size | SHA-256 |
| ---: | ---: | --- |
| 6 | 2,599,462 bytes (2.48 MiB) | `a6cc03e20c0228d52a79138c45d6d87e9636c5c7dbf1679cf50adba66b7aafe0` |
| 8 | 6,627,675 bytes (6.32 MiB) | `a5f3a6ca4a33672bff6aad02237a06acf52ecad7726daf6170f5baf5aa320215` |

Zoom 8 is selected because it retains two additional native levels of coastline and border detail while remaining below the 8 MiB archive budget. MapLibre overzooms the archive above level 8. Together, the compressed canonical source and selected archive occupy 11,211,549 bytes (10.69 MiB), below the former 14,643,638-byte raw GeoJSON alone.

Fiji crosses the antimeridian in the canonical source. Its western and eastern fragments are emitted with the same `FJI` property, so the single ISO-3 filter selects both sides as one visited country.

## Rebuilding

Use a clean virtual environment so the pinned encoder and geometry versions are applied:

```sh
python3 -m venv /tmp/dawarich-country-pmtiles
/tmp/dawarich-country-pmtiles/bin/pip install \
  -r script/country_pmtiles_requirements.txt
/tmp/dawarich-country-pmtiles/bin/python \
  script/build_country_pmtiles.py \
  lib/assets/countries.geojson.gz \
  public/maps/countries-v1.pmtiles \
  --maxzoom 8
```

After an intentional source, dependency, recipe, or archive change, update `public/maps/countries-v1.manifest.json`. The asset spec verifies the source-content, dependency, build-script, and archive checksums, PMTiles version and native maximum zoom, the 8 MiB hard limit, and the combined package budget.

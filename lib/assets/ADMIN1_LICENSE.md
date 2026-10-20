# First-level subdivisions

`admin1_world.geojson` carries one polygon per ISO 3166-2 first-level
subdivision, keyed by `iso_3166_2`, and is loaded into `regions` by
`Achievements::LoadRegions`.

## United States

The 52 `US-*` features are derived from the U.S. Census Bureau 2023
cartographic boundary file `cb_2023_us_state_500k`. Works of the U.S. federal
government are not subject to copyright in the United States
(17 U.S.C. § 105), so the source is public domain. See
https://www.census.gov/geographies/mapping-files/time-series/geo/cartographic-boundary.html.

Census state boundaries stop at the Great Lakes shoreline rather than running
out to the international border through open water, which keeps lake surface
out of the land achievements.

The source is reprojected from NAD83 to WGS84 and simplified with
topology-aware weighted Visvalingam, using a displacement interval scaled to
the size of each part so that small islands keep their shape while large
interiors are thinned. Coordinates are rounded to four decimals
and all attributes except `iso_3166_2` are dropped:

```sh
# cb_2023_us_state_500k.shp, exploded to parts carrying their own area in km2
mapshaper parts.json \
  -simplify variable interval='d.km2>=20000?800:(d.km2>=1000?400:(d.km2>=10?200:1))' \
    keep-shapes \
  -dissolve iso_3166_2 \
  -filter-fields iso_3166_2 \
  -o precision=0.0001 format=geojson us.json
```

`spec/assets/admin1_us_geometry_spec.rb` pins the result: every subdivision
must contain its own deepest interior point, must contain the coastal and
island land that earlier revisions dropped, and must not contain open Great
Lakes water.

## Everything else

The remaining features are unchanged from the previous revision of this file
and their provenance is not recorded here.

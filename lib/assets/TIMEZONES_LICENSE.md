# Time zone boundaries

`timezones.geojson.gz` contains time zone boundaries from
[timezone-boundary-builder](https://github.com/evansiroky/timezone-boundary-builder),
release `2026e`, file `timezones-with-oceans-1970.geojson.zip`
(https://github.com/evansiroky/timezone-boundary-builder/releases/tag/2026e).

The data is derived from OpenStreetMap and is available under the
[Open Database License (ODbL)](https://opendatacommons.org/licenses/odbl/1-0/).
© OpenStreetMap contributors.

Dawarich loads it into the `timezones` table (`Timezones::LoadBoundaries`) to
show visit times in the local time of the place.

## How the file was built

The `with-oceans-1970` variant covers the whole globe (oceans included) and
merges zones whose clocks have matched since 1970, which is enough for
location history. The polygons were simplified with a coverage-preserving
simplification so neighbouring zones still share their borders without gaps:

```sql
-- table tz(tzid text, geom geometry) loaded from combined-with-oceans-1970.json
CREATE TABLE s AS
  SELECT tzid, ST_SetSRID(ST_CoverageSimplify(geom, 0.005) OVER (), 4326) AS geom
  FROM tz;  -- ST_CoverageSimplify drops the SRID, hence ST_SetSRID

SELECT json_build_object('type', 'FeatureCollection', 'features', json_agg(
         json_build_object('type', 'Feature', 'properties', json_build_object('tzid', tzid),
                           'geometry', ST_AsGeoJSON(geom, 4)::json) ORDER BY tzid))::text
FROM s;  -- piped through `gzip -9n`
```

Built with PostGIS 3.6 / GEOS 3.14. A tolerance of 0.005° (about 500 m) keeps
the file near 3.6 MB; places within that distance of a zone border may resolve
to the neighbouring zone.

To update: download a newer release, repeat the steps above, replace the file,
and add a migration that runs `Timezones::LoadBoundaries.new.call` again.

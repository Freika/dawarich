# TeslaMate API integration research

Research date: 2026-09-02

Source snapshots:

- TeslaMate `main` at [`f06c44f`](https://github.com/teslamate-org/teslamate/tree/f06c44fd28827905823241cb4f200a54239e9fd0)
- TeslaMateApi `main`, effectively v1.25.0, at [`3e158df`](https://github.com/tobiasehlert/teslamateapi/tree/3e158df077165237130072c82d07878ab448f4f8)

## Executive conclusion

TeslaMate itself does **not** provide a historical drives/positions JSON API. Its only native JSON routes resume or suspend logging; it also has a GPX download for one already-known drive ID. The TeslaMate source is explicit about those routes, and the GPX controller provides no drive enumeration endpoint ([router](https://github.com/teslamate-org/teslamate/blob/f06c44fd28827905823241cb4f200a54239e9fd0/lib/teslamate_web/router.ex#L29-L56), [GPX controller](https://github.com/teslamate-org/teslamate/blob/f06c44fd28827905823241cb4f200a54239e9fd0/lib/teslamate_web/controllers/drive_controller.ex#L10-L29)). Tesla's own API is not a substitute: TeslaMate's official FAQ says it does not provide historical drives or charges ([FAQ](https://github.com/teslamate-org/teslamate/blob/f06c44fd28827905823241cb4f200a54239e9fd0/website/docs/faq.md#L10-L20)).

The realistic HTTP integration target is the separate, MIT-licensed community service [`tobiasehlert/teslamateapi`](https://github.com/tobiasehlert/teslamateapi). It reads TeslaMate's PostgreSQL database and MQTT broker and exposes the collected data as JSON. It is not maintained under `teslamate-org`, has no OpenAPI document, and its README says fuller endpoint documentation is still to come ([README](https://github.com/tobiasehlert/teslamateapi/blob/3e158df077165237130072c82d07878ab448f4f8/README.md#L155-L194)). Therefore Dawarich should describe the integration as **TeslaMateApi-compatible**, not as an official TeslaMate API.

Recommended flow:

1. `GET /api/v1/cars` to discover vehicle IDs.
2. For each vehicle, page through `GET /api/v1/cars/:car_id/drives?page=N&show=100`.
3. For each returned `drive_id`, fetch `GET /api/v1/cars/:car_id/drives/:drive_id`.
4. Import `data.drive.drive_details`, converting time and speed as described below.

This imports positions belonging to **completed drives only**. The list query requires a non-null drive `end_date`, and the detail query only selects positions with the requested `drive_id` ([list query](https://github.com/tobiasehlert/teslamateapi/blob/3e158df077165237130072c82d07878ab448f4f8/src/v1_TeslaMateAPICarsDrives.go#L181-L189), [detail query](https://github.com/tobiasehlert/teslamateapi/blob/3e158df077165237130072c82d07878ab448f4f8/src/v1_TeslaMateAPICarsDrivesDetails.go#L266-L296)). It omits the current unfinished drive and TeslaMate positions recorded while parked/online with no drive. Direct PostgreSQL access is the only complete historical-position surface.

## Available data surfaces

| Surface | Historical positions | Contract and suitability |
| --- | --- | --- |
| TeslaMate core HTTP | One known drive as GPX | The GPX contains latitude, longitude, optional elevation, and ISO-8601 time, ordered by time ([template](https://github.com/teslamate-org/teslamate/blob/f06c44fd28827905823241cb4f200a54239e9fd0/lib/teslamate_web/templates/drive/gpx.xml.eex#L1-L16)). There is no HTTP drive list, so this cannot power a standalone full import. |
| TeslaMate MQTT | No history | MQTT publishes current/last vehicle state, location, speed, heading, and elevation for automation clients ([official MQTT docs](https://github.com/teslamate-org/teslamate/blob/f06c44fd28827905823241cb4f200a54239e9fd0/website/docs/integrations/mqtt.md#L6-L39)). It is useful for future live ingestion, not a historical backfill. |
| TeslaMateApi HTTP | Completed-drive positions | Best fit for a Dawarich user-facing integration. It discovers cars, lists drives, and returns the positions nested in each drive detail ([routes](https://github.com/tobiasehlert/teslamateapi/blob/3e158df077165237130072c82d07878ab448f4f8/src/webserver.go#L126-L170)). |
| Direct TeslaMate PostgreSQL | All positions | Complete and efficient, including rows without a drive. TeslaMate's official deployment already gives Grafana direct DB credentials ([Docker docs](https://github.com/teslamate-org/teslamate/blob/f06c44fd28827905823241cb4f200a54239e9fd0/website/docs/installation/docker.md#L24-L66)), but the schema is an internal contract and DB access is usually not exposed outside the Docker network. Keep this as a future/advanced adapter, not the first implementation. |

## TeslaMateApi configuration and authentication

TeslaMateApi normally runs on port 8080 beside TeslaMate and requires TeslaMate DB credentials, `TZ`, and (unless disabled) MQTT configuration. The project's compose example and environment table are the authoritative setup reference ([compose example](https://github.com/tobiasehlert/teslamateapi/blob/3e158df077165237130072c82d07878ab448f4f8/README.md#L29-L54), [environment variables](https://github.com/tobiasehlert/teslamateapi/blob/3e158df077165237130072c82d07878ab448f4f8/README.md#L89-L128)). For Dawarich the user-facing configuration should be:

- Base URL, such as `http://teslamateapi:8080` or `https://teslamate.example.com`.
- Optional HTTP Basic username/password for the reverse proxy.
- Optionally support a bearer token or custom header for forks/future versions, but do not claim it protects reads on canonical v1.25.0.
- Optional TLS-verification override, consistent with other self-hosted Dawarich integrations.

The important security trap is that canonical v1.25.0 does **not authenticate read endpoints**, including cars and drives. `API_TOKEN` validation is only called by command/logging handlers, and the README only requires it for those mutating endpoints ([authentication docs](https://github.com/tobiasehlert/teslamateapi/blob/3e158df077165237130072c82d07878ab448f4f8/README.md#L196-L209), [auth implementation](https://github.com/tobiasehlert/teslamateapi/blob/3e158df077165237130072c82d07878ab448f4f8/src/AuthSupport.go#L62-L104)). The project explicitly recommends authentication in front of the container and demonstrates Traefik Basic Auth ([security guidance](https://github.com/tobiasehlert/teslamateapi/blob/3e158df077165237130072c82d07878ab448f4f8/README.md#L231-L239), [Traefik example](https://github.com/tobiasehlert/teslamateapi/blob/3e158df077165237130072c82d07878ab448f4f8/README.md#L56-L87)). Dawarich must never imply that filling an API-token field secures an otherwise exposed TeslaMateApi instance.

For connection testing, request `GET /api/v1/cars`. `/api/ping` and `/api/healthz` only prove that the process is alive, not that a readable TeslaMate database is available; `readyz` is tied to MQTT readiness unless MQTT is disabled ([health handlers](https://github.com/tobiasehlert/teslamateapi/blob/3e158df077165237130072c82d07878ab448f4f8/src/webserver.go#L440-L452)). Every response includes an `API-Version` header, available since TeslaMateApi 1.23.0 ([header middleware](https://github.com/tobiasehlert/teslamateapi/blob/3e158df077165237130072c82d07878ab448f4f8/src/webserver.go#L94-L103)).

## Endpoint contract

### Discover cars

`GET /api/v1/cars` is unpaginated and returns:

```json
{
  "data": {
    "cars": [
      {
        "car_id": 1,
        "name": "My Tesla",
        "car_details": {
          "eid": 123,
          "vid": 456,
          "vin": "...",
          "model": "3",
          "trim_badging": "...",
          "efficiency": 0.153
        },
        "car_exterior": { "exterior_color": "...", "spoiler_type": "...", "wheel_type": "..." },
        "car_settings": { "suspend_min": 21, "suspend_after_idle_min": 15, "req_not_unlocked": false, "free_supercharging": false, "use_streaming_api": true },
        "teslamate_details": { "inserted_at": "...", "updated_at": "..." },
        "teslamate_stats": { "total_charges": 1, "total_drives": 2, "total_updates": 3 }
      }
    ]
  }
}
```

The structs and SQL query are defined directly in the handler ([cars handler](https://github.com/tobiasehlert/teslamateapi/blob/3e158df077165237130072c82d07878ab448f4f8/src/v1_TeslaMateAPICars.go#L21-L104)). Dawarich only needs `car_id` and a display name. An empty result serializes `cars` as `null`, not `[]`, because the Go slice starts nil ([response construction](https://github.com/tobiasehlert/teslamateapi/blob/3e158df077165237130072c82d07878ab448f4f8/src/v1_TeslaMateAPICars.go#L75-L76)).

### List completed drives

`GET /api/v1/cars/:car_id/drives` accepts:

- `page`: one-based page, default `1`.
- `show`: page size, default `100`.
- `startDate`: include drives whose `start_date >=` this instant.
- `endDate`: include drives whose `end_date <=` this instant.
- `minDistance` and `maxDistance`: in the TeslaMate user's configured length unit.
- `location`: case-insensitive substring of the resolved start or end location.

The public README documents the date/distance/location filters ([README](https://github.com/tobiasehlert/teslamateapi/blob/3e158df077165237130072c82d07878ab448f4f8/README.md#L175-L194)); `page` and `show` are implemented but not documented there. Their defaults and offset calculation are in the handler ([pagination code](https://github.com/tobiasehlert/teslamateapi/blob/3e158df077165237130072c82d07878ab448f4f8/src/v1_TeslaMateAPICarsDrives.go#L17-L52), [offset calculation](https://github.com/tobiasehlert/teslamateapi/blob/3e158df077165237130072c82d07878ab448f4f8/src/v1_TeslaMateAPICarsDrives.go#L126-L132)). There is no enforced maximum page size, total count, next-page link, or pagination metadata. Rows are ordered newest-first by `start_date`; date filter semantics and `LIMIT/OFFSET` are visible in the SQL builder ([filters/order](https://github.com/tobiasehlert/teslamateapi/blob/3e158df077165237130072c82d07878ab448f4f8/src/v1_TeslaMateAPICarsDrives.go#L196-L259)).

The response shape is:

```json
{
  "data": {
    "car": { "car_id": 1, "car_name": "My Tesla" },
    "drives": [
      {
        "drive_id": 42,
        "start_date": "2026-08-20T10:00:00+02:00",
        "end_date": "2026-08-20T10:30:00+02:00",
        "start_address": "...",
        "end_address": "...",
        "odometer_details": { "odometer_start": 1000.0, "odometer_end": 1020.0, "odometer_distance": 20.0 },
        "duration_min": 30,
        "duration_str": "00:30",
        "speed_max": 100,
        "speed_avg": 40.0,
        "power_max": 120,
        "power_min": -30,
        "battery_details": { "start_usable_battery_level": 80, "start_battery_level": 81, "end_usable_battery_level": 74, "end_battery_level": 75, "reduced_range": true, "is_sufficiently_precise": true },
        "range_ideal": { "start_range": 400.0, "end_range": 370.0, "range_diff": 30.0 },
        "range_rated": { "start_range": 380.0, "end_range": 350.0, "range_diff": 30.0 },
        "outside_temp_avg": 20.5,
        "inside_temp_avg": 21.0,
        "energy_consumed_net": 4.5,
        "consumption_net": 225.0
      }
    ],
    "units": { "unit_of_length": "km", "unit_of_temperature": "C" }
  }
}
```

The complete list struct is the de facto schema ([drive list structs](https://github.com/tobiasehlert/teslamateapi/blob/3e158df077165237130072c82d07878ab448f4f8/src/v1_TeslaMateAPICarsDrives.go#L54-L117)). When a page has no rows, `data.drives` is `null` and the unit/name strings are empty because all are populated while scanning rows ([response construction](https://github.com/tobiasehlert/teslamateapi/blob/3e158df077165237130072c82d07878ab448f4f8/src/v1_TeslaMateAPICarsDrives.go#L352-L380)). Treat both `null` and `[]` as end-of-pagination.

### Get one drive and its positions

`GET /api/v1/cars/:car_id/drives/:drive_id` returns the same summary as `data.drive` plus unpaginated `data.drive.drive_details`. Each detail element has this schema ([detail structs](https://github.com/tobiasehlert/teslamateapi/blob/3e158df077165237130072c82d07878ab448f4f8/src/v1_TeslaMateAPICarsDrivesDetails.go#L50-L122)):

```json
{
  "detail_id": 12345,
  "date": "2026-08-20T10:00:02+02:00",
  "latitude": 52.5201,
  "longitude": 13.4051,
  "speed": 42,
  "power": 8,
  "odometer": 1000.1,
  "battery_level": 81,
  "usable_battery_level": 80,
  "elevation": 34,
  "climate_info": {
    "inside_temp": 21.0,
    "outside_temp": 20.5,
    "is_climate_on": false,
    "fan_status": 0,
    "driver_temp_setting": 20.0,
    "passenger_temp_setting": 20.0,
    "is_rear_defroster_on": false,
    "is_front_defroster_on": false
  },
  "battery_info": {
    "est_battery_range": 370.0,
    "ideal_battery_range": 390.0,
    "rated_battery_range": 375.0,
    "battery_heater": false,
    "battery_heater_on": false,
    "battery_heater_no_power": false
  }
}
```

Nullable database values in `usable_battery_level`, `elevation`, climate fields, and battery-info fields serialize as JSON `null` ([null wrappers](https://github.com/tobiasehlert/teslamateapi/blob/3e158df077165237130072c82d07878ab448f4f8/src/NullSupport.go#L13-L50)). Positions are ordered by their database ID ascending, which normally matches capture order; Dawarich should still order/dedupe by parsed timestamp during insertion ([position query](https://github.com/tobiasehlert/teslamateapi/blob/3e158df077165237130072c82d07878ab448f4f8/src/v1_TeslaMateAPICarsDrivesDetails.go#L266-L296)).

## Time and units

- Query dates should be RFC3339. Offsets are accepted and converted to UTC. The implementation also accepts a timezone-less date interpreted in the TeslaMateApi `TZ`, but Dawarich should always send RFC3339 with `Z` to avoid ambiguity ([date parser](https://github.com/tobiasehlert/teslamateapi/blob/3e158df077165237130072c82d07878ab448f4f8/src/webserver.go#L312-L330)).
- Response timestamps are RFC3339 strings converted from stored UTC into the `TZ` configured on TeslaMateApi. Parse them as instants and store Unix seconds in Dawarich; never strip the offset ([time conversion](https://github.com/tobiasehlert/teslamateapi/blob/3e158df077165237130072c82d07878ab448f4f8/src/webserver.go#L297-L310)).
- TeslaMate stores position speed as km/h: it converts the Tesla mph value before insertion ([vehicle source](https://github.com/teslamate-org/teslamate/blob/f06c44fd28827905823241cb4f200a54239e9fd0/lib/teslamate/vehicles/vehicle.ex#L1649-L1656)). TeslaMateApi returns km/h when `unit_of_length == "km"` and converts it to mph when the setting is `"mi"` ([detail conversion](https://github.com/tobiasehlert/teslamateapi/blob/3e158df077165237130072c82d07878ab448f4f8/src/v1_TeslaMateAPICarsDrivesDetails.go#L341-L348)). Dawarich velocity is conventionally m/s, so convert with `km/h / 3.6` or `mph * 0.44704`.
- `elevation` is meters above sea level and is not converted for imperial users; TeslaMate's official MQTT contract confirms the unit ([MQTT docs](https://github.com/teslamate-org/teslamate/blob/f06c44fd28827905823241cb4f200a54239e9fd0/website/docs/integrations/mqtt.md#L32-L39)).
- Battery levels are percentages. Prefer `usable_battery_level` when present, otherwise `battery_level`.
- Latitude and longitude are WGS84 decimal degrees. TeslaMate requires car, date, latitude, and longitude for every position ([position schema](https://github.com/teslamate-org/teslamate/blob/f06c44fd28827905823241cb4f200a54239e9fd0/lib/teslamate/log/position.ex#L7-L39), [validation](https://github.com/teslamate-org/teslamate/blob/f06c44fd28827905823241cb4f200a54239e9fd0/lib/teslamate/log/position.ex#L41-L76)).

Suggested Dawarich mapping:

| TeslaMateApi | Dawarich |
| --- | --- |
| `longitude`, `latitude` | `lonlat = POINT(longitude latitude)` |
| `date` | RFC3339 parse, then Unix seconds `timestamp` |
| `elevation` | `altitude` / `altitude_decimal`, meters |
| `speed` + `data.units.unit_of_length` | `velocity`, converted to m/s |
| `usable_battery_level || battery_level` | `battery` |
| `car_id` | stable tracker ID such as `teslamate-<car_id>` |
| `drive_id`, `detail_id`, source fields | `raw_data` for provenance/debugging |

## Error behavior and defensive parsing

TeslaMateApi has nonstandard error semantics. Database errors, invalid date filters, and a missing drive all go through `TeslaMateAPIHandleErrorResponse`, which returns **HTTP 200** with a root JSON object such as `{"error":"Unable to load drives."}`, `{"error":"Invalid date format."}`, or `{"error":"No rows were returned!"}` ([error handler](https://github.com/tobiasehlert/teslamateapi/blob/3e158df077165237130072c82d07878ab448f4f8/src/webserver.go#L273-L295), [missing-drive branch](https://github.com/tobiasehlert/teslamateapi/blob/3e158df077165237130072c82d07878ab448f4f8/src/v1_TeslaMateAPICarsDrivesDetails.go#L224-L233)). Unknown routes are conventional HTTP 404 JSON ([router](https://github.com/tobiasehlert/teslamateapi/blob/3e158df077165237130072c82d07878ab448f4f8/src/webserver.go#L105-L108)); a reverse proxy may also return ordinary 401/403 or non-JSON bodies.

The client must therefore:

1. Require a 2xx status.
2. Require JSON with the expected `data` structure.
3. Check for a root `error` key even when the status is 200.
4. Treat `drives: null`/`cars: null` as an empty success, not an exception.
5. Reject non-finite/out-of-range coordinates and unparseable dates without aborting all other positions in the drive.
6. Time out and retry idempotent GETs with bounded backoff; a drive detail can be large because it has no pagination.

Malformed numeric URL/query values are converted silently to zero. Invalid `car_id`, `page`, or `show` therefore do not reliably produce a 400 response ([conversion helpers](https://github.com/tobiasehlert/teslamateapi/blob/3e158df077165237130072c82d07878ab448f4f8/src/webserver.go#L370-L392)). Validate them within Dawarich.

## Robust synchronization algorithm

For an initial import:

1. Capture `sync_cutoff = Time.current.utc` once and send it as `endDate`. This prevents a newly completed drive from being inserted at the front while offset pagination is in progress.
2. Fetch all cars.
3. For each car, request drive pages with a modest fixed `show` (100 is the implementation default).
4. Stop when `drives` is null/empty or the returned count is smaller than `show`.
5. Fetch each drive detail and upsert its positions. Continue other drives if one detail fails, while reporting the failed drive ID.
6. Dedupe using Dawarich's existing point uniqueness `(user_id, timestamp, lonlat)` and retain TeslaMate `car_id`, `drive_id`, and `detail_id` in provenance data.
7. Only record the synchronization checkpoint after all intended pages have been processed; retain failed drive IDs for retry.

For later syncs, use an overlapping `startDate` window and a new fixed `endDate`, then rely on idempotent upserts. A small overlap is preferable to a strict last-timestamp cursor because the list is newest-first offset pagination and TeslaMateApi exposes neither a cursor nor a total count. Note that its filters require `start_date >= startDate` and `end_date <= endDate`, so a drive crossing a boundary is excluded; overlap avoids losing it ([filter implementation](https://github.com/tobiasehlert/teslamateapi/blob/3e158df077165237130072c82d07878ab448f4f8/src/v1_TeslaMateAPICarsDrives.go#L196-L206)).

## Direct database fallback

If complete location history becomes a requirement, add a separately named PostgreSQL adapter rather than silently changing the TeslaMateApi integration. The authoritative TeslaMate schema has a nullable `drive_id` relationship and the required WGS84/time fields plus optional speed, elevation, odometer, and battery data ([position schema](https://github.com/teslamate-org/teslamate/blob/f06c44fd28827905823241cb4f200a54239e9fd0/lib/teslamate/log/position.ex#L7-L39)). A scalable read shape is an ID cursor:

```sql
SELECT id, car_id, drive_id, date, latitude, longitude,
       elevation, speed, battery_level, usable_battery_level
FROM positions
WHERE id > $1
ORDER BY id ASC
LIMIT $2;
```

Use a dedicated read-only PostgreSQL role, TLS where the DB crosses hosts, and persist the last completed ID. This avoids the HTTP N+1 pattern and includes positions outside drives, but it deliberately accepts coupling to TeslaMate migrations and requires more sensitive credentials. TeslaMateApi itself illustrates that coupling by querying the same `cars`, `drives`, `positions`, and `settings` tables directly ([drive SQL](https://github.com/tobiasehlert/teslamateapi/blob/3e158df077165237130072c82d07878ab448f4f8/src/v1_TeslaMateAPICarsDrivesDetails.go#L132-L185)).

## Compatibility notes

- Target and test TeslaMateApi v1.25.0. That release added configurable token headers and fixed nullable historical-drive temperatures ([changelog](https://github.com/tobiasehlert/teslamateapi/blob/3e158df077165237130072c82d07878ab448f4f8/CHANGELOG.md#L1-L27)). Older releases may fail on old rows or lack newer filters.
- Do not confuse TeslaMateApi's `API_TOKEN` with Tesla Fleet/Owner API credentials. Dawarich only reads already-collected history and should never request Tesla account tokens.
- Do not use TeslaMate MQTT for the initial import. It exposes the current/last location and is valuable only as a possible later real-time extension.
- Treat extra JSON keys as forward-compatible and required location keys conservatively. There is no published OpenAPI/schema version beyond the `API-Version` response header.

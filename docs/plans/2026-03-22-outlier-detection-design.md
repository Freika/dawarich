# GPS Outlier Detection - Design Document

## Problem

Dawarich stores every GPS point it receives regardless of quality. When a phone's GPS glitches (e.g., WiFi-based location guessing wrong country, indoor GPS scatter), these erroneous points inflate distance stats, distort track visualization, and corrupt visit detection. The `accuracy` column exists in the schema but is never used for filtering.

Related issues: #155, #466, #940, #946, #1393, #1397.

## Solution

A speed-based outlier detection system that flags points requiring physically impossible speeds to reach from their temporal neighbors. Flagged points are soft-deleted (boolean column) so they're excluded from calculations but remain recoverable.

## Algorithm

### Core: Speed-Based Detection

For consecutive points ordered by timestamp, calculate implied speed:

```
speed_kmh = distance_km(A, B) / ((B.timestamp - A.timestamp) / 3600.0)
```

If `speed_kmh > max_speed_kmh` (user-configurable, default 900 km/h), the point is a candidate outlier.

### Sandwich Resolution

A single bad point B between good points A and C produces two speed spikes: A->B and B->C. To handle this:

1. When B is suspicious, check A->C speed (skipping B).
2. If A->C is reasonable, B is the outlier.
3. If A->C is also unreasonable, continue scanning forward — the problem may span multiple points.

### Edge Cases

- **Time delta = 0**: Two points at the same timestamp with different locations. Flag the one farther from its other neighbor.
- **First/last points in a day**: Only one neighbor available. Use single-neighbor speed check.
- **Flights**: Default threshold of 900 km/h is above commercial cruise speed (~850 km/h). Users who never fly can lower it.
- **Large time gaps**: If gap between consecutive points exceeds 1 hour, skip the pair — speed calculation is meaningless over long gaps with no intermediate data.

## Components

### 1. Migration: Add `outlier` column to `points`

```ruby
add_column :points, :outlier, :boolean, default: false, null: false
add_index :points, :outlier, where: 'outlier = true'
```

Partial index on `outlier = true` keeps the index small since the vast majority of points are valid.

### 2. Model: Point scope

```ruby
# app/models/point.rb
scope :not_outlier, -> { where(outlier: false) }
```

### 3. Service: `Points::OutlierDetector`

```
app/services/points/outlier_detector.rb
```

**Input**: user_id, optional date range (start_at, end_at)
**Output**: count of points flagged

**Process**:
1. Load points for user in date range, ordered by timestamp, selecting only id, lonlat, timestamp.
2. Process in daily batches to limit memory usage.
3. For each consecutive pair, compute implied speed using PostGIS `ST_Distance`.
4. Apply sandwich resolution logic.
5. Bulk update flagged points: `UPDATE points SET outlier = true WHERE id IN (...)`.

The distance calculation should use the existing PostGIS infrastructure (same as `Distanceable`) to stay consistent with how the project measures distances.

### 4. Job: `Points::OutlierDetectionJob`

```
app/jobs/points/outlier_detection_job.rb
```

**Arguments**: user_id, optional start_at, end_at
**Queue**: default

Called:
- After import completes (in `Imports::Create#call`, after point insertion)
- Manually from settings page

### 5. User Setting: `max_speed_kmh`

Add to `Users::SafeSettings::DEFAULT_VALUES`:

```ruby
'outlier_detection_enabled' => true,
'max_speed_kmh' => 900
```

Accessor methods: `outlier_detection_enabled?`, `max_speed_kmh`.

### 6. Settings UI

New section in the settings page: "Data Quality"

- Toggle: "Automatically detect outlier points" (default: on)
- Number input: "Maximum realistic speed (km/h)" (default: 900)
- Button: "Scan all points for outliers" (triggers full scan job)
- Info text: "Points flagged as outliers are excluded from distance calculations and track generation but are not deleted. You can review and restore them."

### 7. Integration Points

**Post-import hook** — in `Imports::Create#call` (line 29-30 area), add:

```ruby
schedule_outlier_detection(user.id, import)
```

Only runs if `user.safe_settings.outlier_detection_enabled?`.

**Distance calculations** — in `Distanceable`, ensure queries filter `outlier = false`. Two places:
- `calculate_distance_for_relation` (SQL-based, line 107): add `WHERE outlier = false`
- `calculate_distance_for_array_geocoder` (in-memory, line 16): caller should pass pre-filtered points

**Track generation** — wherever tracks pull points, apply `.not_outlier` scope.

**Stats calculation** — stats jobs should use `.not_outlier` when aggregating.

**Map rendering** — API endpoints serving points to the map should use `.not_outlier` by default.

## What Does NOT Change

- No points are deleted. The `outlier` flag is reversible.
- Existing `bulk_destroy` and single point deletion continue to work.
- The `accuracy` column is not used (would be a separate, complementary feature).
- Import pipeline itself is untouched — detection runs as a post-processing step.

## File Summary

| File | Action |
|------|--------|
| `db/migrate/TIMESTAMP_add_outlier_to_points.rb` | New migration |
| `app/models/point.rb` | Add `not_outlier` scope |
| `app/services/points/outlier_detector.rb` | New service |
| `app/jobs/points/outlier_detection_job.rb` | New job |
| `app/services/users/safe_settings.rb` | Add settings |
| `app/services/imports/create.rb` | Hook outlier detection post-import |
| `app/models/concerns/distanceable.rb` | Filter outliers in distance SQL |
| `app/controllers/settings/general_controller.rb` | Handle new settings + scan trigger |
| `spec/services/points/outlier_detector_spec.rb` | New tests |
| `spec/jobs/points/outlier_detection_job_spec.rb` | New tests |

## Testing Strategy

- Unit tests for `OutlierDetector` with synthetic point sequences:
  - Normal movement (no flags)
  - Single teleport spike (flag the bad point)
  - Sandwich pattern (flag middle point, not neighbors)
  - Flight-speed movement below threshold (no flags)
  - Zero time delta edge case
  - Large time gap (skip pair)
- Job specs verifying it enqueues and delegates to the service
- Integration test: import with bad points -> verify outliers flagged -> verify stats exclude them

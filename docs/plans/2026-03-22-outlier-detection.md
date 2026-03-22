# GPS Outlier Detection Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Detect and soft-flag GPS points that require physically impossible speeds, excluding them from distance/track/stats calculations while keeping them recoverable.

**Architecture:** A `Points::OutlierDetector` service processes points ordered by timestamp, computing implied speed between consecutive pairs using PostGIS. Points exceeding a user-configurable speed threshold (default 900 km/h) are flagged via a boolean `outlier` column. A background job runs this after imports and on manual trigger.

**Tech Stack:** Ruby on Rails 8, PostgreSQL + PostGIS, Sidekiq, RSpec

---

### Task 1: Migration — Add `outlier` column to `points`

**Files:**
- Create: `db/migrate/TIMESTAMP_add_outlier_to_points.rb`

**Step 1: Generate the migration**

Run:
```bash
bundle exec rails generate migration AddOutlierToPoints outlier:boolean
```

**Step 2: Edit the migration to add partial index and default**

```ruby
# db/migrate/TIMESTAMP_add_outlier_to_points.rb
class AddOutlierToPoints < ActiveRecord::Migration[8.0]
  def change
    add_column :points, :outlier, :boolean, default: false, null: false
    add_index :points, :outlier, where: 'outlier = true', name: 'index_points_on_outlier_true'
  end
end
```

**Step 3: Run the migration**

Run:
```bash
bundle exec rails db:migrate
```
Expected: Migration succeeds, `schema.rb` updated with `outlier` column.

**Step 4: Commit**

```bash
git add db/migrate/*_add_outlier_to_points.rb db/schema.rb
git commit -m "feat: add outlier boolean column to points table"
```

---

### Task 2: Point model — Add `not_outlier` scope

**Files:**
- Modify: `app/models/point.rb:30-33` (add scope near other scopes)
- Test: `spec/models/point_spec.rb`

**Step 1: Write the failing test**

Add to `spec/models/point_spec.rb` (in the appropriate describe block, or create one):

```ruby
describe '.not_outlier' do
  let(:user) { create(:user) }
  let!(:normal_point) { create(:point, user: user, outlier: false) }
  let!(:outlier_point) { create(:point, user: user, outlier: true) }

  it 'excludes points flagged as outliers' do
    expect(Point.not_outlier).to include(normal_point)
    expect(Point.not_outlier).not_to include(outlier_point)
  end
end
```

**Step 2: Run test to verify it fails**

Run:
```bash
bundle exec rspec spec/models/point_spec.rb -e "not_outlier"
```
Expected: FAIL — `NoMethodError: undefined method 'not_outlier'`

**Step 3: Add the scope**

In `app/models/point.rb`, after line 33 (`scope :not_visited`):

```ruby
scope :not_outlier, -> { where(outlier: false) }
scope :outlier, -> { where(outlier: true) }
```

**Step 4: Run test to verify it passes**

Run:
```bash
bundle exec rspec spec/models/point_spec.rb -e "not_outlier"
```
Expected: PASS

**Step 5: Commit**

```bash
git add app/models/point.rb spec/models/point_spec.rb
git commit -m "feat: add not_outlier and outlier scopes to Point model"
```

---

### Task 3: User settings — Add outlier detection configuration

**Files:**
- Modify: `app/services/users/safe_settings.rb:8-55` (add defaults)
- Modify: `app/services/users/safe_settings.rb` (add accessor methods)

**Step 1: Add default values**

In `app/services/users/safe_settings.rb`, add to `DEFAULT_VALUES` hash (after `'timezone'` line 54):

```ruby
'outlier_detection_enabled' => true,
'max_speed_kmh' => 900
```

**Step 2: Add accessor methods**

After `timezone` method (line 241), add:

```ruby
def outlier_detection_enabled?
  value = settings['outlier_detection_enabled']
  return true if value.nil?

  ActiveModel::Type::Boolean.new.cast(value)
end

def max_speed_kmh
  (settings['max_speed_kmh'] || DEFAULT_VALUES['max_speed_kmh']).to_i
end
```

**Step 3: Verify with a quick console test or existing settings specs**

Run:
```bash
bundle exec rspec spec/services/users/ -e "safe_settings" 2>/dev/null || echo "No existing settings specs to break"
```
Expected: No regressions.

**Step 4: Commit**

```bash
git add app/services/users/safe_settings.rb
git commit -m "feat: add outlier detection settings (enabled toggle, max speed)"
```

---

### Task 4: Core service — `Points::OutlierDetector`

**Files:**
- Create: `app/services/points/outlier_detector.rb`
- Create: `spec/services/points/outlier_detector_spec.rb`

**Step 1: Write the failing tests**

Create `spec/services/points/outlier_detector_spec.rb`:

```ruby
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Points::OutlierDetector do
  let(:user) { create(:user) }
  let(:base_time) { DateTime.new(2024, 5, 1, 12, 0, 0).to_i }

  # Helper: create a point at a given lat/lon and time offset (seconds)
  def create_point_at(lat:, lon:, time_offset: 0, outlier: false)
    create(:point,
      user: user,
      latitude: lat,
      longitude: lon,
      lonlat: "POINT(#{lon} #{lat})",
      timestamp: base_time + time_offset,
      outlier: outlier
    )
  end

  describe '#call' do
    context 'with normal movement' do
      before do
        # ~1 km apart, 10 minutes between each = ~6 km/h (walking)
        create_point_at(lat: 51.5000, lon: -0.1200, time_offset: 0)
        create_point_at(lat: 51.5090, lon: -0.1200, time_offset: 600)
        create_point_at(lat: 51.5180, lon: -0.1200, time_offset: 1200)
      end

      it 'flags no points' do
        result = described_class.new(user).call
        expect(result).to eq(0)
        expect(user.points.where(outlier: true).count).to eq(0)
      end
    end

    context 'with a single teleport spike' do
      before do
        # Point 1: London
        create_point_at(lat: 51.5074, lon: -0.1278, time_offset: 0)
        # Point 2: Tokyo (teleport!) — 1 minute later
        create_point_at(lat: 35.6762, lon: 139.6503, time_offset: 60)
        # Point 3: London again — 1 minute after that
        create_point_at(lat: 51.5080, lon: -0.1280, time_offset: 120)
      end

      it 'flags the teleported point' do
        result = described_class.new(user).call
        expect(result).to eq(1)

        outliers = user.points.where(outlier: true)
        expect(outliers.count).to eq(1)
        # The Tokyo point should be the outlier
        expect(outliers.first.lat).to be_within(0.01).of(35.6762)
      end
    end

    context 'with a large time gap' do
      before do
        # Point 1: London
        create_point_at(lat: 51.5074, lon: -0.1278, time_offset: 0)
        # Point 2: New York — 10 hours later (plausible flight)
        create_point_at(lat: 40.7128, lon: -74.0060, time_offset: 36_000)
      end

      it 'does not flag points separated by more than 1 hour' do
        result = described_class.new(user).call
        expect(result).to eq(0)
        expect(user.points.where(outlier: true).count).to eq(0)
      end
    end

    context 'with flight-speed movement below threshold' do
      before do
        # London to Paris, ~340km, in 50 minutes = ~408 km/h (fast train or slow plane)
        create_point_at(lat: 51.5074, lon: -0.1278, time_offset: 0)
        create_point_at(lat: 48.8566, lon: 2.3522, time_offset: 3000)
      end

      it 'does not flag points within speed threshold' do
        result = described_class.new(user).call
        expect(result).to eq(0)
      end
    end

    context 'with custom speed threshold' do
      before do
        user.settings['max_speed_kmh'] = 100
        user.save!

        # London to Paris, ~340km, in 50 minutes = ~408 km/h
        create_point_at(lat: 51.5074, lon: -0.1278, time_offset: 0)
        create_point_at(lat: 48.8566, lon: 2.3522, time_offset: 3000)
        # Back near London
        create_point_at(lat: 51.5080, lon: -0.1280, time_offset: 6000)
      end

      it 'uses the user configured threshold' do
        result = described_class.new(user).call
        expect(result).to be >= 1
      end
    end

    context 'with date range filter' do
      before do
        # Points on day 1 — normal
        create_point_at(lat: 51.5000, lon: -0.1200, time_offset: 0)
        create_point_at(lat: 51.5090, lon: -0.1200, time_offset: 600)

        # Points on day 2 — has outlier
        create_point_at(lat: 51.5074, lon: -0.1278, time_offset: 86_400)
        create_point_at(lat: 35.6762, lon: 139.6503, time_offset: 86_460) # Tokyo spike
        create_point_at(lat: 51.5080, lon: -0.1280, time_offset: 86_520)
      end

      it 'only processes points in the given range' do
        day2_start = Time.zone.at(base_time + 86_400)
        day2_end = Time.zone.at(base_time + 86_400 + 86_399)

        result = described_class.new(user, start_at: day2_start, end_at: day2_end).call
        expect(result).to eq(1)
      end
    end

    context 'with already flagged outliers' do
      before do
        create_point_at(lat: 51.5074, lon: -0.1278, time_offset: 0)
        create_point_at(lat: 35.6762, lon: 139.6503, time_offset: 60, outlier: true)
        create_point_at(lat: 51.5080, lon: -0.1280, time_offset: 120)
      end

      it 'does not double-count previously flagged outliers' do
        result = described_class.new(user).call
        expect(result).to eq(0)
        expect(user.points.where(outlier: true).count).to eq(1)
      end
    end
  end
end
```

**Step 2: Run tests to verify they fail**

Run:
```bash
bundle exec rspec spec/services/points/outlier_detector_spec.rb
```
Expected: FAIL — `NameError: uninitialized constant Points::OutlierDetector`

**Step 3: Write the service implementation**

Create `app/services/points/outlier_detector.rb`:

```ruby
# frozen_string_literal: true

class Points::OutlierDetector
  MAX_TIME_GAP_SECONDS = 3600 # 1 hour — skip pairs with gaps larger than this
  BATCH_SIZE = 5000

  attr_reader :user, :start_at, :end_at

  def initialize(user, start_at: nil, end_at: nil)
    @user = user
    @start_at = start_at
    @end_at = end_at
  end

  # Returns the number of points newly flagged as outliers
  def call
    total_flagged = 0

    points_scope.find_in_batches(batch_size: BATCH_SIZE) do |batch|
      outlier_ids = detect_outliers_in_batch(batch)
      next if outlier_ids.empty?

      Point.where(id: outlier_ids).update_all(outlier: true)
      total_flagged += outlier_ids.size
    end

    total_flagged
  end

  private

  def max_speed_kmh
    @max_speed_kmh ||= user.safe_settings.max_speed_kmh
  end

  def points_scope
    scope = user.points.where(outlier: false).order(:timestamp)
    scope = scope.where('timestamp >= ?', start_at.to_i) if start_at
    scope = scope.where('timestamp <= ?', end_at.to_i) if end_at
    scope.select(:id, :lonlat, :timestamp)
  end

  def detect_outliers_in_batch(points)
    outlier_ids = []
    i = 0

    while i < points.size - 1
      current = points[i]
      next_point = points[i + 1]

      speed = implied_speed(current, next_point)

      if speed && speed > max_speed_kmh
        # Suspected outlier — apply sandwich resolution
        if sandwich_confirms_outlier?(points, i)
          outlier_ids << next_point.id
          # Skip the outlier and continue from the point after it
          i += 2
          next
        end
      end

      i += 1
    end

    outlier_ids
  end

  # Check if skipping the suspected outlier (at index+1) produces a reasonable
  # speed between points[index] and points[index+2].
  # If yes, the middle point is confirmed as an outlier.
  # If there is no point after the suspect, flag it anyway (single-neighbor check).
  def sandwich_confirms_outlier?(points, index)
    suspect_index = index + 1
    after_index = index + 2

    # No point after suspect — flag based on single-neighbor speed alone
    return true if after_index >= points.size

    before = points[index]
    after = points[after_index]

    skip_speed = implied_speed(before, after)

    # If skipping the suspect produces reasonable speed, it's the outlier
    return true if skip_speed.nil? || skip_speed <= max_speed_kmh

    # Both paths are unreasonable — don't flag (could be a real location change
    # with missing intermediate data)
    false
  end

  # Calculate implied speed in km/h between two points.
  # Returns nil if time gap exceeds MAX_TIME_GAP_SECONDS (meaningless measurement).
  def implied_speed(point_a, point_b)
    time_delta = (point_b.timestamp - point_a.timestamp).abs.to_f

    return nil if time_delta == 0
    return nil if time_delta > MAX_TIME_GAP_SECONDS

    distance_km = Geocoder::Calculations.distance_between(
      [point_a.lat, point_a.lon],
      [point_b.lat, point_b.lon],
      units: :km
    )

    return nil unless distance_km.finite?

    hours = time_delta / 3600.0
    distance_km / hours
  end
end
```

**Step 4: Run tests to verify they pass**

Run:
```bash
bundle exec rspec spec/services/points/outlier_detector_spec.rb
```
Expected: ALL PASS

**Step 5: Commit**

```bash
git add app/services/points/outlier_detector.rb spec/services/points/outlier_detector_spec.rb
git commit -m "feat: add Points::OutlierDetector service with speed-based detection"
```

---

### Task 5: Background job — `Points::OutlierDetectionJob`

**Files:**
- Create: `app/jobs/points/outlier_detection_job.rb`
- Create: `spec/jobs/points/outlier_detection_job_spec.rb`

**Step 1: Write the failing test**

Create `spec/jobs/points/outlier_detection_job_spec.rb`:

```ruby
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Points::OutlierDetectionJob, type: :job do
  let(:user) { create(:user) }

  describe '#perform' do
    it 'calls the OutlierDetector service' do
      detector = instance_double(Points::OutlierDetector, call: 0)
      allow(Points::OutlierDetector).to receive(:new)
        .with(user, start_at: nil, end_at: nil)
        .and_return(detector)

      described_class.new.perform(user.id)

      expect(detector).to have_received(:call)
    end

    it 'passes date range when provided' do
      start_at = '2024-05-01T00:00:00Z'
      end_at = '2024-05-01T23:59:59Z'

      detector = instance_double(Points::OutlierDetector, call: 0)
      allow(Points::OutlierDetector).to receive(:new)
        .with(user, start_at: Time.parse(start_at), end_at: Time.parse(end_at))
        .and_return(detector)

      described_class.new.perform(user.id, start_at, end_at)

      expect(detector).to have_received(:call)
    end

    it 'skips if user not found' do
      expect(Points::OutlierDetector).not_to receive(:new)
      described_class.new.perform(-1)
    end

    it 'skips if outlier detection is disabled' do
      user.settings['outlier_detection_enabled'] = false
      user.save!

      expect(Points::OutlierDetector).not_to receive(:new)
      described_class.new.perform(user.id)
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run:
```bash
bundle exec rspec spec/jobs/points/outlier_detection_job_spec.rb
```
Expected: FAIL — `NameError: uninitialized constant Points::OutlierDetectionJob`

**Step 3: Write the job**

Create `app/jobs/points/outlier_detection_job.rb`:

```ruby
# frozen_string_literal: true

class Points::OutlierDetectionJob < ApplicationJob
  queue_as :default

  def perform(user_id, start_at = nil, end_at = nil)
    user = find_user_or_skip(user_id) || return
    return unless user.safe_settings.outlier_detection_enabled?

    parsed_start = start_at ? Time.parse(start_at.to_s) : nil
    parsed_end = end_at ? Time.parse(end_at.to_s) : nil

    count = Points::OutlierDetector.new(user, start_at: parsed_start, end_at: parsed_end).call

    Rails.logger.info(
      "#{self.class.name}: Flagged #{count} outlier points for user #{user_id}"
    )
  end
end
```

**Step 4: Run tests to verify they pass**

Run:
```bash
bundle exec rspec spec/jobs/points/outlier_detection_job_spec.rb
```
Expected: ALL PASS

**Step 5: Commit**

```bash
git add app/jobs/points/outlier_detection_job.rb spec/jobs/points/outlier_detection_job_spec.rb
git commit -m "feat: add OutlierDetectionJob background job"
```

---

### Task 6: Post-import hook — Auto-detect outliers after import

**Files:**
- Modify: `app/services/imports/create.rb:29-30` (add scheduling call)
- Modify: `app/services/imports/create.rb` (add private method)

**Step 1: Add the hook in `Imports::Create#call`**

In `app/services/imports/create.rb`, after line 30 (`schedule_visit_suggesting(user.id, import)`), add:

```ruby
schedule_outlier_detection(user.id, import)
```

**Step 2: Add the private method**

In the `private` section of the same file, add:

```ruby
def schedule_outlier_detection(user_id, import)
  return unless user.safe_settings.outlier_detection_enabled?

  min_max = import.points.pick('MIN(timestamp), MAX(timestamp)')
  return if min_max.compact.empty?

  start_at = Time.zone.at(min_max[0])
  end_at = Time.zone.at(min_max[1])

  Points::OutlierDetectionJob.perform_later(user_id, start_at.iso8601, end_at.iso8601)
end
```

**Step 3: Verify no existing tests break**

Run:
```bash
bundle exec rspec spec/services/imports/create_spec.rb
```
Expected: PASS (existing tests should not break; the new method only fires when enabled)

**Step 4: Commit**

```bash
git add app/services/imports/create.rb
git commit -m "feat: trigger outlier detection after import completion"
```

---

### Task 7: Filter outliers from track generation

**Files:**
- Modify: `app/models/track.rb:61` (add outlier filter to SQL)

**Step 1: Add outlier filter to `segment_points_in_sql`**

In `app/models/track.rb`, modify the `where_clause` construction (lines 55-59):

Change:
```ruby
where_clause = if untracked_only
                 'WHERE user_id = $1 AND timestamp BETWEEN $2 AND $3 AND track_id IS NULL'
               else
                 'WHERE user_id = $1 AND timestamp BETWEEN $2 AND $3'
               end
```

To:
```ruby
where_clause = if untracked_only
                 'WHERE user_id = $1 AND timestamp BETWEEN $2 AND $3 AND track_id IS NULL AND outlier = false'
               else
                 'WHERE user_id = $1 AND timestamp BETWEEN $2 AND $3 AND outlier = false'
               end
```

**Step 2: Verify no existing track tests break**

Run:
```bash
bundle exec rspec spec/models/track_spec.rb
```
Expected: PASS

**Step 3: Commit**

```bash
git add app/models/track.rb
git commit -m "feat: exclude outlier points from track segmentation"
```

---

### Task 8: Filter outliers from distance calculations

**Files:**
- Modify: `app/models/concerns/distanceable.rb:107-125` (add WHERE clause)

**Step 1: Add outlier filter to SQL distance calculation**

In `app/models/concerns/distanceable.rb`, modify `calculate_distance_for_relation` (line 107-125).

Change the SQL (line 107-125) from:

```ruby
distance_in_meters = connection.select_value(<<-SQL.squish)
  WITH points_with_previous AS (
    SELECT
      lonlat,
      LAG(lonlat) OVER (ORDER BY timestamp) as prev_lonlat
    FROM (#{to_sql}) AS points
  )
  SELECT COALESCE(
    SUM(
      ST_Distance(
        lonlat::geography,
        prev_lonlat::geography
      )
    ),
    0
  )
  FROM points_with_previous
  WHERE prev_lonlat IS NOT NULL
SQL
```

To:

```ruby
distance_in_meters = connection.select_value(<<-SQL.squish)
  WITH points_with_previous AS (
    SELECT
      lonlat,
      LAG(lonlat) OVER (ORDER BY timestamp) as prev_lonlat
    FROM (#{to_sql}) AS points
    WHERE outlier = false
  )
  SELECT COALESCE(
    SUM(
      ST_Distance(
        lonlat::geography,
        prev_lonlat::geography
      )
    ),
    0
  )
  FROM points_with_previous
  WHERE prev_lonlat IS NOT NULL
SQL
```

**Note:** This adds `WHERE outlier = false` to the inner subquery. If the outer scope already applies `.not_outlier`, this is redundant but safe. If the outer scope does not filter, this is the safety net.

**Step 2: Verify no existing distance tests break**

Run:
```bash
bundle exec rspec spec/models/concerns/distanceable_spec.rb 2>/dev/null || bundle exec rspec spec/ -e "distance" 2>/dev/null || echo "Run full suite to check"
```

**Step 3: Commit**

```bash
git add app/models/concerns/distanceable.rb
git commit -m "feat: exclude outlier points from distance calculations"
```

---

### Task 9: Settings controller — Manual scan trigger

**Files:**
- Modify: `app/controllers/settings/general_controller.rb` (add action)
- Modify: `config/routes.rb` (add route)

**Step 1: Add the controller action**

In `app/controllers/settings/general_controller.rb`, add a public method before the `private` keyword:

```ruby
def detect_outliers
  Points::OutlierDetectionJob.perform_later(current_user.id)
  redirect_to settings_general_index_path,
              notice: 'Outlier detection started. This may take a few minutes for large datasets.'
end
```

Also add outlier settings handling to the `update` method. Add a new private method:

```ruby
def update_outlier_settings
  if params.key?(:outlier_detection_enabled)
    current_user.settings['outlier_detection_enabled'] =
      ActiveModel::Type::Boolean.new.cast(params[:outlier_detection_enabled])
  end
  return unless params.key?(:max_speed_kmh)

  current_user.settings['max_speed_kmh'] = params[:max_speed_kmh].to_i
end
```

And call it from `update`:

```ruby
def update
  update_timezone
  update_email_settings
  update_supporter_settings
  update_outlier_settings
  # ... rest unchanged
end
```

**Step 2: Add the route**

In `config/routes.rb`, find the settings routes section and add:

```ruby
post 'settings/general/detect_outliers', to: 'settings/general#detect_outliers', as: :detect_outliers
```

**Step 3: Verify the route works**

Run:
```bash
bundle exec rails routes | grep outlier
```
Expected: Shows the `detect_outliers` route.

**Step 4: Commit**

```bash
git add app/controllers/settings/general_controller.rb config/routes.rb
git commit -m "feat: add outlier detection settings and manual scan trigger"
```

---

### Task 10: Settings view — Data Quality section

**Files:**
- Find and modify the settings general view template (likely `app/views/settings/general/index.html.erb` or similar)

**Step 1: Locate the view file**

Run:
```bash
find app/views/settings -name "*.erb" -o -name "*.html.erb" | head -20
```

**Step 2: Add the Data Quality section**

Add a new section to the settings general page (follow existing patterns for form elements, Tailwind/DaisyUI styling):

```erb
<!-- Data Quality -->
<div class="card bg-base-100 shadow-xl mb-6">
  <div class="card-body">
    <h2 class="card-title">Data Quality</h2>

    <div class="form-control">
      <label class="label cursor-pointer">
        <span class="label-text">Automatically detect outlier points after import</span>
        <input type="checkbox" name="outlier_detection_enabled"
               value="true"
               class="toggle toggle-primary"
               <%= 'checked' if current_user.safe_settings.outlier_detection_enabled? %> />
      </label>
    </div>

    <div class="form-control">
      <label class="label">
        <span class="label-text">Maximum realistic speed (km/h)</span>
      </label>
      <input type="number" name="max_speed_kmh"
             value="<%= current_user.safe_settings.max_speed_kmh %>"
             min="10" max="2000" step="10"
             class="input input-bordered w-full max-w-xs" />
      <label class="label">
        <span class="label-text-alt">Points requiring faster travel are flagged as outliers. Default: 900 km/h (above commercial flight speed).</span>
      </label>
    </div>

    <div class="mt-4">
      <%= button_to "Scan all points for outliers",
            detect_outliers_path,
            method: :post,
            class: "btn btn-outline btn-sm",
            data: { confirm: "This will scan all your points. It may take a few minutes for large datasets. Continue?" } %>
    </div>

    <% if current_user.points.where(outlier: true).any? %>
      <div class="mt-2 text-sm opacity-70">
        <%= current_user.points.where(outlier: true).count %> points currently flagged as outliers.
      </div>
    <% end %>
  </div>
</div>
```

**Step 3: Verify the page renders**

Start the dev server and navigate to the settings page to visually verify.

**Step 4: Commit**

```bash
git add app/views/settings/
git commit -m "feat: add Data Quality section to settings page with outlier controls"
```

---

### Task 11: Full integration test

**Files:**
- Create: `spec/integration/outlier_detection_spec.rb` (or add to existing integration tests)

**Step 1: Write an integration test**

```ruby
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Outlier detection integration', type: :model do
  let(:user) { create(:user) }
  let(:base_time) { DateTime.new(2024, 5, 1, 12, 0, 0).to_i }

  it 'flags outliers and excludes them from distance calculations' do
    # Create a sequence: London -> Tokyo (spike) -> London
    p1 = create(:point, user: user, latitude: 51.5074, longitude: -0.1278,
                lonlat: 'POINT(-0.1278 51.5074)', timestamp: base_time)
    p2 = create(:point, user: user, latitude: 35.6762, longitude: 139.6503,
                lonlat: 'POINT(139.6503 35.6762)', timestamp: base_time + 60)
    p3 = create(:point, user: user, latitude: 51.5080, longitude: -0.1280,
                lonlat: 'POINT(-0.1280 51.5080)', timestamp: base_time + 120)

    # Distance before detection (includes the Tokyo teleport)
    distance_before = Point.where(user: user).total_distance

    # Run outlier detection
    count = Points::OutlierDetector.new(user).call

    expect(count).to eq(1)
    expect(p2.reload.outlier).to be true

    # Distance after detection (excludes the Tokyo teleport)
    distance_after = Point.where(user: user).not_outlier.total_distance

    # The distance should be dramatically smaller
    expect(distance_after).to be < distance_before
    expect(distance_after).to be < 1 # Less than 1 km (London to London ~67m)
  end
end
```

**Step 2: Run the test**

Run:
```bash
bundle exec rspec spec/integration/outlier_detection_spec.rb
```
Expected: PASS

**Step 3: Run the full test suite**

Run:
```bash
bundle exec rspec
```
Expected: No regressions.

**Step 4: Commit**

```bash
git add spec/integration/outlier_detection_spec.rb
git commit -m "test: add integration test for outlier detection end-to-end flow"
```

---

### Task 12: Run full linting and test suite

**Step 1: Run RuboCop**

Run:
```bash
bundle exec rubocop app/services/points/outlier_detector.rb app/jobs/points/outlier_detection_job.rb app/models/point.rb app/services/users/safe_settings.rb app/controllers/settings/general_controller.rb app/services/imports/create.rb app/models/track.rb app/models/concerns/distanceable.rb
```
Expected: No offenses. Fix any that appear.

**Step 2: Run full test suite**

Run:
```bash
bundle exec rspec
```
Expected: ALL PASS

**Step 3: Final commit if any fixes were needed**

```bash
git add -A
git commit -m "chore: fix linting issues from outlier detection feature"
```

---

## File Change Summary

| File | Action | Description |
|------|--------|-------------|
| `db/migrate/*_add_outlier_to_points.rb` | Create | Add `outlier` boolean column with partial index |
| `app/models/point.rb` | Modify | Add `not_outlier` and `outlier` scopes |
| `app/services/users/safe_settings.rb` | Modify | Add `outlier_detection_enabled` and `max_speed_kmh` settings |
| `app/services/points/outlier_detector.rb` | Create | Core detection algorithm |
| `app/jobs/points/outlier_detection_job.rb` | Create | Background job wrapper |
| `app/services/imports/create.rb` | Modify | Post-import hook |
| `app/models/track.rb` | Modify | Filter outliers from segmentation SQL |
| `app/models/concerns/distanceable.rb` | Modify | Filter outliers from distance SQL |
| `app/controllers/settings/general_controller.rb` | Modify | Manual scan trigger + settings |
| `config/routes.rb` | Modify | Add route for scan trigger |
| `app/views/settings/general/` | Modify | Data Quality UI section |
| `spec/services/points/outlier_detector_spec.rb` | Create | Unit tests for detector |
| `spec/jobs/points/outlier_detection_job_spec.rb` | Create | Job tests |
| `spec/models/point_spec.rb` | Modify | Scope tests |
| `spec/integration/outlier_detection_spec.rb` | Create | End-to-end test |

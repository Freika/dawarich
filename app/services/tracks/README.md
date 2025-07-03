# Tracks Services

This directory contains services for working with tracks generated from user points.

## Tracks::CreateFromPoints

This service takes all points for a user and creates tracks by splitting them based on the user's configured settings for distance and time thresholds.

### Usage

```ruby
# Basic usage
user = User.find(123)
service = Tracks::CreateFromPoints.new(user)
tracks_created = service.call

puts "Created #{tracks_created} tracks for user #{user.email}"
```

### How it works

The service:

1. **Fetches all user points** ordered by timestamp
2. **Splits points into track segments** based on two thresholds:
   - **Distance threshold**: `user.safe_settings.meters_between_routes` (default: 500 meters)
   - **Time threshold**: `user.safe_settings.minutes_between_routes` (default: 30 minutes)
3. **Creates Track records** with calculated statistics:
   - Distance (in meters)
   - Duration (in seconds)
   - Average speed (in km/h)
   - Elevation statistics (gain, loss, min, max)
   - PostGIS LineString path
4. **Associates points with tracks** by updating the `track_id` field

### Track Splitting Logic

A new track is created when either condition is met:
- **Time gap**: Time between consecutive points > time threshold
- **Distance gap**: Distance between consecutive points > distance threshold

### Example with custom settings

```ruby
# User with custom settings
user.update!(settings: {
  'meters_between_routes' => 1000,  # 1km distance threshold
  'minutes_between_routes' => 60    # 1 hour time threshold
})

service = Tracks::CreateFromPoints.new(user)
service.call
```

### Background Job Usage

For large datasets, consider running in a background job:

```ruby
class Tracks::CreateJob < ApplicationJob
  queue_as :default

  def perform(user_id)
    user = User.find(user_id)
    tracks_created = Tracks::CreateFromPoints.new(user).call

    # Create notification for user
    Notification.create!(
      user: user,
      title: 'Tracks Generated',
      content: "Created #{tracks_created} tracks from your location data",
      kind: :info
    )
  end
end

# Enqueue the job
Tracks::CreateJob.perform_later(user.id)
```

### Console Usage

```ruby
# In Rails console
rails console

# Generate tracks for a specific user
user = User.find_by(email: 'user@example.com')
Tracks::CreateFromPoints.new(user).call

# Generate tracks for all users
User.find_each do |user|
  tracks_created = Tracks::CreateFromPoints.new(user).call
  puts "User #{user.id}: #{tracks_created} tracks created"
end
```

### Configuration

The service respects user settings:

- `meters_between_routes`: Maximum distance between points in the same track (meters)
- `minutes_between_routes`: Maximum time between points in the same track (minutes)
- `distance_unit`: Used for internal calculations (km/miles)

### Performance Considerations

- Uses database transactions for consistency
- Processes points with `find_each` to avoid loading all points into memory
- Destroys existing tracks before regenerating (use with caution)
- For users with many points, consider running as background job

### Track Statistics

Each track includes:

- **start_at/end_at**: First and last point timestamps
- **distance**: Total distance in meters (converted from user's preferred unit)
- **duration**: Total time in seconds
- **avg_speed**: Average speed in km/h
- **elevation_gain/loss**: Cumulative elevation changes
- **elevation_min/max**: Altitude range
- **original_path**: PostGIS LineString geometry

### Dependencies

- PostGIS for distance calculations and path geometry
- Existing `Tracks::BuildPath` service for creating LineString geometry
- User settings via `Users::SafeSettings`
- Point model with `Distanceable` concern

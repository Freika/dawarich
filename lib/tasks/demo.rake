# frozen_string_literal: true

namespace :demo do
  desc 'Seed demo data: user, points from GeoJSON, visits, and areas'
  task :seed_data, [:geojson_path] => :environment do |_t, args|
    geojson_path = args[:geojson_path] || Rails.root.join('tmp/demo_data.geojson').to_s

    unless File.exist?(geojson_path)
      puts "Error: GeoJSON file not found at #{geojson_path}"
      puts 'Usage: rake demo:seed_data[path/to/file.geojson]'
      puts 'Or place file at tmp/demo_data.geojson'
      exit 1
    end

    puts '🚀 Starting demo data generation...'
    puts '=' * 60

    # 1. Create demo user
    puts "\n📝 Creating demo user..."
    user = User.find_or_initialize_by(email: 'demo@dawarich.app')

    if user.new_record?
      user.password = 'password'
      user.password_confirmation = 'password'
      user.save!
      user.update!(status: :active, active_until: 1000.years.from_now)
      puts "✅ User created: #{user.email}"
      puts '   Password: password'
    else
      puts "ℹ️  User already exists: #{user.email}"
    end

    # Set specific API key and enable live mode for e2e testing
    user.update!(
      api_key: 'demo_api_key_001',
      settings: (user.settings || {}).merge('live_map_enabled' => true)
    )
    puts "   API Key: #{user.api_key}"
    puts '   Live Mode: enabled'

    # 2. Import GeoJSON data
    puts "\n📍 Importing GeoJSON data from #{geojson_path}..."
    import = user.imports.create!(
      name: "Demo Data Import - #{Time.current.strftime('%Y-%m-%d %H:%M')}",
      source: :geojson
    )

    begin
      Geojson::Importer.new(import, user.id, geojson_path).call
      import.update!(status: :completed)
      points_count = user.points.count
      puts "✅ Imported #{points_count} points"
    rescue StandardError => e
      import.update!(status: :failed)
      puts "❌ Import failed: #{e.message}"
      exit 1
    end

    # Check if points were imported
    points_count = Point.where(user_id: user.id).count

    if points_count.zero?
      puts '❌ No points found after import. Cannot create visits and areas.'
      exit 1
    end

    # 3. Create suggested visits
    puts "\n🏠 Creating 50 suggested visits..."
    created_suggested = create_visits(user, 50, :suggested)
    puts "✅ Created #{created_suggested} suggested visits"

    # 4. Create confirmed visits
    puts "\n✅ Creating 50 confirmed visits..."
    created_confirmed = create_visits(user, 50, :confirmed)
    puts "✅ Created #{created_confirmed} confirmed visits"

    # 5. Create areas
    puts "\n📍 Creating 10 areas..."
    created_areas = create_areas(user, 10)
    puts "✅ Created #{created_areas} areas"

    # 6. Create tracks
    puts "\n🛤️  Creating 20 tracks..."
    created_tracks = create_tracks(user, 20)
    puts "✅ Created #{created_tracks} tracks"

    # 7. Create timeline fixtures — tagged places, today's pattern, suggested
    # alternates, declined visits, and an all-day visit. Needed to exercise the
    # Map v2 Timeline tab (calendar heatmap, inline suggestion picker, tag chips,
    # place drawer with notes, and the all-day collapse rule).
    puts "\n🗓️  Creating timeline fixtures..."
    timeline_summary = create_timeline_demo_data(user)
    puts "✅ #{timeline_summary[:tags]} tags · #{timeline_summary[:places]} places · " \
         "#{timeline_summary[:visits]} visits (#{timeline_summary[:by_status]})"

    # 8. Create family with members
    puts "\n👨‍👩‍👧‍👦 Creating demo family..."
    family_members = create_family_with_members(user)
    puts "✅ Created family with #{family_members.count} members"

    # 9. Create Lite demo user
    puts "\n📝 Creating Lite demo user..."
    lite_user = User.find_or_initialize_by(email: 'lite@dawarich.app')
    if lite_user.new_record?
      lite_user.password = 'password'
      lite_user.password_confirmation = 'password'
      lite_user.save!
      puts "✅ Lite user created: #{lite_user.email}"
    else
      puts "ℹ️  Lite user already exists: #{lite_user.email}"
    end

    lite_user.update_columns(
      api_key: 'lite_demo_api_key_001',
      plan: User.plans[:lite],
      status: User.statuses[:active],
      active_until: 1000.years.from_now,
      signup_variant: 'legacy_trial'
    )
    lite_user.update!(settings: (lite_user.settings || {}).merge('live_map_enabled' => true))
    puts "   API Key: #{lite_user.api_key}"
    puts '   Plan: lite'
    puts "   Signup Variant: #{lite_user.signup_variant}"

    # 9a. Create recent points for Lite user (within 12-month window)
    puts "\n📍 Creating recent points for Lite user..."
    recent_points_count = create_lite_recent_points(lite_user)
    puts "✅ Created #{recent_points_count} recent points"

    # 9b. Create old points for Lite user (outside 12-month window)
    puts "\n📍 Creating old points for Lite user..."
    old_points_count = create_lite_old_points(lite_user)
    puts "✅ Created #{old_points_count} old points"

    # 9c. Create visits and areas for Lite user
    puts "\n🏠 Creating visits for Lite user..."
    lite_confirmed = create_visits(lite_user, 3, :confirmed)
    puts "✅ Created #{lite_confirmed} confirmed visits"

    puts "\n📍 Creating areas for Lite user..."
    lite_areas = create_areas(lite_user, 2)
    puts "✅ Created #{lite_areas} areas"

    puts "\n#{'=' * 60}"
    puts '🎉 Demo data generation complete!'
    puts '=' * 60
    puts "\n📊 Summary:"
    puts "   User: #{user.email}"
    puts "   Points: #{Point.where(user_id: user.id).count}"
    puts "   Places: #{user.visits.joins(:place).select('DISTINCT places.id').count}"
    puts "   Suggested Visits: #{user.visits.suggested.count}"
    puts "   Confirmed Visits: #{user.visits.confirmed.count}"
    puts "   Areas: #{user.areas.count}"
    puts "   Tracks: #{user.tracks.count}"
    puts "   Track Segments: #{TrackSegment.joins(:track).where(tracks: { user_id: user.id }).count}"
    puts "   Family Members: #{family_members.count}"
    puts "\n   Lite User: #{lite_user.email}"
    puts "   Lite Points: #{Point.where(user_id: lite_user.id).count}"
    lite_points = Point.where(user_id: lite_user.id)
    puts "   Lite Recent Points: #{lite_points.where('timestamp >= ?', 12.months.ago.to_i).count}"
    puts "   Lite Old Points: #{lite_points.where('timestamp < ?', 12.months.ago.to_i).count}"
    puts "   Lite Visits: #{lite_user.visits.count}"
    puts "   Lite Areas: #{lite_user.areas.count}"
    puts "\n🔐 Login credentials:"
    puts '   Email: demo@dawarich.app'
    puts '   Password: password'
    puts "\n   Lite Email: lite@dawarich.app"
    puts '   Lite Password: password'
    puts "\n👨‍👩‍👧‍👦 Family member credentials:"
    family_members.each_with_index do |member, index|
      puts "   Member #{index + 1}: #{member.email} / password / API Key: #{member.api_key}"
    end
  end

  def create_visits(user, count, status)
    area_names = [
      'Home', 'Work', 'Gym', 'Coffee Shop', 'Restaurant',
      'Park', 'Library', 'Shopping Mall', 'Friend\'s House',
      'Doctor\'s Office', 'Supermarket', 'School', 'Cinema',
      'Beach', 'Museum', 'Airport', 'Train Station', 'Hotel'
    ]

    # Get random points, excluding already used ones
    used_point_ids = user.visits.pluck(:id).flat_map { |v| Visit.find(v).points.pluck(:id) }.uniq
    available_points = Point.where(user_id: user.id).where.not(id: used_point_ids).order('RANDOM()').limit(count * 2)

    if available_points.empty?
      puts "⚠️  No available points for #{status} visits"
      return 0
    end

    created_count = 0
    available_points.first(count).each_with_index do |point, index|
      # Random duration between 1-6 hours
      duration_hours = rand(1..6)
      started_at = point.recorded_at
      ended_at = started_at + duration_hours.hours

      # Create or find a place at this location
      # Round coordinates to 5 decimal places (~1 meter precision)
      rounded_lat = point.lat.round(5)
      rounded_lon = point.lon.round(5)

      place = Place.find_or_initialize_by(
        latitude: rounded_lat,
        longitude: rounded_lon
      )

      if place.new_record?
        place.name = area_names.sample
        place.lonlat = "POINT(#{rounded_lon} #{rounded_lat})"
        place.save!
      end

      # Create visit with place. visit.duration is stored in MINUTES
      # (see app/services/visits/creator.rb and ...create.rb).
      visit = user.visits.create!(
        name: place.name,
        place: place,
        started_at: started_at,
        ended_at: ended_at,
        duration: ((ended_at - started_at) / 60).to_i,
        status: status
      )

      # Associate the point with the visit
      point.update!(visit: visit)

      # Find nearby points within 100 meters and associate them
      nearby_points = Point.where(user_id: user.id)
                           .where.not(id: point.id)
                           .where.not(id: used_point_ids)
                           .where('timestamp BETWEEN ? AND ?', started_at.to_i, ended_at.to_i)
                           .select { |p| distance_between(point, p) < 100 }
                           .first(10)

      nearby_points.each do |nearby_point|
        nearby_point.update!(visit: visit)
        used_point_ids << nearby_point.id
      end

      created_count += 1
      print '.' if ((index + 1) % 10).zero?
    end

    puts '' if created_count.positive?
    created_count
  end

  def create_areas(user, count)
    area_names = [
      'Home', 'Work', 'Gym', 'Parents House', 'Favorite Restaurant',
      'Coffee Shop', 'Park', 'Library', 'Shopping Center', 'Friend\'s Place'
    ]

    # Get random points spread across the dataset
    total_points = Point.where(user_id: user.id).count
    step = [total_points / count, 1].max
    sample_points = Point.where(user_id: user.id).order(:timestamp).each_slice(step).map(&:first).first(count)

    created_count = 0
    sample_points.each_with_index do |point, index|
      # Random radius between 50-500 meters
      radius = rand(50..500)

      user.areas.create!(
        name: area_names[index] || "Area #{index + 1}",
        latitude: point.lat,
        longitude: point.lon,
        radius: radius
      )

      created_count += 1
    end

    created_count
  end

  def distance_between(point1, point2)
    # Haversine formula to calculate distance in meters
    lat1 = point1.lat
    lon1 = point1.lon
    lat2 = point2.lat
    lon2 = point2.lon

    rad_per_deg = Math::PI / 180
    rkm = 6371 # Earth radius in kilometers
    rm = rkm * 1000 # Earth radius in meters

    dlat_rad = (lat2 - lat1) * rad_per_deg
    dlon_rad = (lon2 - lon1) * rad_per_deg

    lat1_rad = lat1 * rad_per_deg
    lat2_rad = lat2 * rad_per_deg

    a = Math.sin(dlat_rad / 2)**2 + Math.cos(lat1_rad) * Math.cos(lat2_rad) * Math.sin(dlon_rad / 2)**2
    c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a))

    rm * c # Distance in meters
  end

  # Specific API keys for e2e testing
  FAMILY_API_KEYS = %w[
    family_member_1_api_key
    family_member_2_api_key
    family_member_3_api_key
  ].freeze

  def create_family_with_members(owner)
    # Create or find family
    family = Family.find_or_initialize_by(creator: owner)

    if family.new_record?
      family.name = 'Demo Family'
      family.save!
      puts "   Created family: #{family.name}"
    else
      puts "   ℹ️  Family already exists: #{family.name}"
    end

    # Create or find owner membership
    Family::Membership.find_or_create_by!(
      family: family,
      user: owner,
      role: :owner
    )

    # Create 3 family members with location data
    member_emails = [
      'family.member1@dawarich.app',
      'family.member2@dawarich.app',
      'family.member3@dawarich.app'
    ]

    family_members = []

    # Get some sample points from the owner's data to create realistic locations
    sample_points = Point.where(user_id: owner.id).order('RANDOM()').limit(10)

    member_emails.each_with_index do |email, index|
      # Create or find family member user
      member = User.find_or_initialize_by(email: email)

      if member.new_record?
        member.password = 'password'
        member.password_confirmation = 'password'
        member.save!
        member.update!(status: :active, active_until: 1000.years.from_now)
        puts "   Created family member: #{member.email}"
      else
        puts "   ℹ️  Family member already exists: #{member.email}"
      end

      # Set specific API key for e2e testing
      member.update!(api_key: FAMILY_API_KEYS[index])

      # Add member to family
      Family::Membership.find_or_create_by!(
        family: family,
        user: member,
        role: :member
      )

      # Enable location sharing for this member (permanent)
      member.update_family_location_sharing!(true, duration: 'permanent')

      # Create some points for this family member near owner's locations
      if sample_points.any?
        # Get a different sample point for each member
        base_point = sample_points[index % sample_points.length]

        # Create 3-5 recent points for this member within 1km of base location
        points_count = rand(3..5)

        points_count.times do |_point_index|
          # Add random offset (within ~1km)
          lat_offset = (rand(-0.01..0.01) * 100) / 100.0
          lon_offset = (rand(-0.01..0.01) * 100) / 100.0

          # Calculate new coordinates
          lat = base_point.lat + lat_offset
          lon = base_point.lon + lon_offset

          # Create point with recent timestamp (last 24 hours)
          timestamp = (Time.current - rand(0..24).hours).to_i

          Point.create!(
            user: member,
            latitude: lat,
            longitude: lon,
            lonlat: "POINT(#{lon} #{lat})",
            timestamp: timestamp,
            altitude: base_point.altitude || 0,
            velocity: rand(0..50),
            battery: rand(20..100),
            battery_status: %w[charging connected_not_charging full].sample,
            tracker_id: "demo_tracker_#{member.id}",
            import_id: nil
          )
        end

        puts "   Created #{points_count} location points for #{member.email}"
      end

      family_members << member
    end

    family_members
  end

  # Transportation modes for demo tracks
  DEMO_TRANSPORTATION_MODES = %i[walking running cycling driving bus train stationary].freeze

  def create_tracks(user, count)
    # Get points that aren't already assigned to tracks
    available_points = Point.where(user_id: user.id, track_id: nil)
                            .order(:timestamp)

    if available_points.count < 10
      puts '   ⚠️  Not enough untracked points to create tracks'
      return 0
    end

    created_count = 0
    points_per_track = [available_points.count / count, 10].max

    count.times do |index|
      # Get a segment of consecutive points
      offset = index * points_per_track
      track_points = available_points.offset(offset).limit(points_per_track).to_a

      break if track_points.length < 2

      # Sort by timestamp to ensure proper ordering
      track_points = track_points.sort_by(&:timestamp)

      # Build LineString from points
      coordinates = track_points.map { |p| [p.lon, p.lat] }
      linestring_wkt = "LINESTRING(#{coordinates.map { |lon, lat| "#{lon} #{lat}" }.join(', ')})"

      # Calculate track metadata
      start_at = Time.zone.at(track_points.first.timestamp)
      end_at = Time.zone.at(track_points.last.timestamp)
      duration = (end_at - start_at).to_i

      # Calculate total distance
      total_distance = 0
      track_points.each_cons(2) do |p1, p2|
        total_distance += haversine_distance(p1.lat, p1.lon, p2.lat, p2.lon)
      end

      # Calculate average speed (m/s)
      avg_speed = duration.positive? ? (total_distance / duration.to_f) : 0

      # Calculate elevation data
      elevations = track_points.map(&:altitude).compact
      elevation_gain = 0
      elevation_loss = 0
      elevation_max = elevations.any? ? elevations.max : 0
      elevation_min = elevations.any? ? elevations.min : 0

      if elevations.length > 1
        elevations.each_cons(2) do |alt1, alt2|
          diff = alt2 - alt1
          if diff.positive?
            elevation_gain += diff
          else
            elevation_loss += diff.abs
          end
        end
      end

      # Create the track
      track = user.tracks.create!(
        start_at: start_at,
        end_at: end_at,
        distance: total_distance,
        avg_speed: avg_speed,
        duration: duration,
        elevation_gain: elevation_gain,
        elevation_loss: elevation_loss,
        elevation_max: elevation_max,
        elevation_min: elevation_min,
        original_path: linestring_wkt
      )

      # Associate points with the track
      track_points.each { |p| p.update_column(:track_id, track.id) }

      # Create transportation mode segments for this track
      create_track_segments(track, track_points)

      created_count += 1
      print '.' if ((index + 1) % 5).zero?
    end

    puts '' if created_count.positive?
    created_count
  end

  def create_track_segments(track, track_points)
    return if track_points.length < 2

    # Determine number of segments (1-4 based on track length)
    num_segments = case track_points.length
                   when 2..5 then 1
                   when 6..15 then rand(1..2)
                   when 16..30 then rand(2..3)
                   else rand(2..4)
                   end

    # Calculate segment boundaries
    points_per_segment = track_points.length / num_segments
    current_index = 0

    num_segments.times do |seg_idx|
      # Calculate start and end indices for this segment
      start_index = current_index
      end_index = if seg_idx == num_segments - 1
                    track_points.length - 1
                  else
                    [current_index + points_per_segment - 1, track_points.length - 1].min
                  end

      # Get points for this segment
      segment_points = track_points[start_index..end_index]
      next if segment_points.length < 2

      # Calculate segment metrics
      segment_distance = 0
      segment_points.each_cons(2) do |p1, p2|
        segment_distance += haversine_distance(p1.lat, p1.lon, p2.lat, p2.lon)
      end

      segment_duration = Time.zone.at(segment_points.last.timestamp) - Time.zone.at(segment_points.first.timestamp)
      segment_duration = [segment_duration.to_i, 1].max # Minimum 1 second

      segment_avg_speed = segment_distance / segment_duration.to_f # m/s
      segment_avg_speed_kmh = segment_avg_speed * 3.6 # Convert to km/h

      # Determine transportation mode based on speed
      transportation_mode = determine_mode_from_speed(segment_avg_speed_kmh)

      # Calculate max speed from velocities if available
      velocities = segment_points.map(&:velocity).compact
      max_speed = velocities.any? ? velocities.max : segment_avg_speed_kmh

      # Determine confidence based on segment length and consistency
      confidence = case segment_points.length
                   when 2..3 then :low
                   when 4..10 then :medium
                   else :high
                   end

      # Create the track segment
      track.track_segments.create!(
        transportation_mode: transportation_mode,
        start_index: start_index,
        end_index: end_index,
        distance: segment_distance.to_i,
        duration: segment_duration,
        avg_speed: segment_avg_speed_kmh,
        max_speed: max_speed,
        confidence: confidence
      )

      current_index = end_index + 1
    end

    # Update the track's dominant mode
    track.update_dominant_mode!
  end

  def determine_mode_from_speed(speed_kmh)
    case speed_kmh
    when 0..1 then :stationary
    when 1..7 then :walking
    when 7..15 then :running
    when 15..35 then :cycling
    when 35..120 then :driving
    when 120..250 then :train
    else :flying
    end
  end

  def haversine_distance(lat1, lon1, lat2, lon2)
    # Haversine formula to calculate distance in meters
    rad_per_deg = Math::PI / 180
    rm = 6_371_000 # Earth radius in meters

    dlat_rad = (lat2 - lat1) * rad_per_deg
    dlon_rad = (lon2 - lon1) * rad_per_deg

    lat1_rad = lat1 * rad_per_deg
    lat2_rad = lat2 * rad_per_deg

    a = Math.sin(dlat_rad / 2)**2 + Math.cos(lat1_rad) * Math.cos(lat2_rad) * Math.sin(dlon_rad / 2)**2
    c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a))

    rm * c # Distance in meters
  end

  # Berlin area coordinates matching e2e/v2/helpers/constants.js
  BERLIN_BASE = { lat: 52.52, lon: 13.405 }.freeze

  def create_lite_recent_points(user)
    created = 0
    20.times do |i|
      # Spread across last 6 months
      months_ago = (i % 6) + 1
      day_offset = (i * 3) % 28 + 1
      timestamp = (months_ago.months.ago + day_offset.days).to_i

      lat = BERLIN_BASE[:lat] + rand(-0.03..0.03)
      lon = BERLIN_BASE[:lon] + rand(-0.05..0.05)

      Point.create!(
        user: user,
        latitude: lat,
        longitude: lon,
        lonlat: "POINT(#{lon} #{lat})",
        timestamp: timestamp,
        altitude: rand(30..80),
        velocity: rand(0..30),
        battery: rand(30..100),
        tracker_id: "lite_demo_#{user.id}"
      )
      created += 1
    end
    created
  end

  def create_lite_old_points(user)
    created = 0
    10.times do |i|
      # 13-14 months ago (outside the 12-month retention window)
      months_ago = 13 + (i % 2)
      day_offset = (i * 2) % 28 + 1
      timestamp = (months_ago.months.ago + day_offset.days).to_i

      lat = BERLIN_BASE[:lat] + rand(-0.03..0.03)
      lon = BERLIN_BASE[:lon] + rand(-0.05..0.05)

      Point.create!(
        user: user,
        latitude: lat,
        longitude: lon,
        lonlat: "POINT(#{lon} #{lat})",
        timestamp: timestamp,
        altitude: rand(30..80),
        velocity: rand(0..30),
        battery: rand(30..100),
        tracker_id: "lite_demo_#{user.id}"
      )
      created += 1
    end
    created
  end

  # --------------------------------------------------------------------------
  # Timeline fixtures (Map v2 Timeline tab)
  # --------------------------------------------------------------------------
  # Seeds named, tagged places (home/work/coffee/food/gym) plus visits spread
  # across the last ~14 days in the user's timezone. Exercises:
  #   - Calendar heatmap buckets (multi-visit days light up hotter)
  #   - Suggested visits with multiple `suggested_places` (radio picker)
  #   - Declined visits (grey status dot + filter)
  #   - All-day visit (duration ≥ 23h → compact collapse)
  #   - Place Drawer with tags + notes
  # Non-idempotent by design: rerunning appends more visits (matches the style
  # of `create_visits` / `create_tracks` above).
  # --------------------------------------------------------------------------

  TIMELINE_CATEGORIES = {
    home:   { name: 'Home',           tag: 'home',   icon: '🏠', color: '#22c55e', lat_offset: -0.003,
lon_offset: 0.002, note: nil },
    work:   { name: 'Office',         tag: 'work',   icon: '💼', color: '#3b82f6', lat_offset:  0.008,
lon_offset: -0.006, note: nil },
    coffee: { name: 'Café Süd',       tag: 'coffee', icon: '☕', color: '#f59e0b', lat_offset:  0.002,
lon_offset: 0.015, note: 'Good wifi, quiet mornings. Almond croissant > everything.' },
    food:   { name: 'Bäckerei Meier', tag: 'food',   icon: '🍞',  color: '#ef4444', lat_offset:  0.007,
lon_offset: -0.003, note: 'Cash only. Sourdough lunch special Thursdays.' },
    gym:    { name: 'Gym',            tag: 'gym',    icon: '🏋',  color: '#8b5cf6', lat_offset: -0.008,
lon_offset: 0.009, note: nil }
  }.freeze

  def create_timeline_demo_data(user)
    tz = user.safe_settings&.timezone.presence || 'Europe/Berlin'
    user.update!(settings: (user.settings || {}).merge('timezone' => tz))

    tags = timeline_demo_tags(user)
    places = timeline_demo_places(user, tags)
    counts = { confirmed: 0, suggested: 0, declined: 0 }

    Time.use_zone(tz) do
      today      = Date.current
      yesterday  = today - 1.day
      day_before = today - 2.days

      # --- TODAY: rich pattern the user sees when they open /map/v2 -----
      add_timeline_visit(user, places[:home],   today.beginning_of_day,
                         today.beginning_of_day + 7.hours, :confirmed, 'Home', counts)
      # A suggested visit with alternates drives the inline radio picker
      add_timeline_visit(user, places[:coffee], today.beginning_of_day + 9.hours,
                         today.beginning_of_day + 10.hours, :suggested, nil, counts,
                         alternates: [places[:coffee], places[:food], places[:work]])
      add_timeline_visit(user, places[:work],   today.beginning_of_day + 10.hours + 30.minutes,
                         today.beginning_of_day + 18.hours, :confirmed, 'Office', counts)
      add_timeline_visit(user, places[:home],   today.beginning_of_day + 19.hours,
                         today.beginning_of_day + 23.hours + 45.minutes, :confirmed, 'Home', counts)

      # --- YESTERDAY: mix including a declined -----------------------------
      add_timeline_visit(user, places[:home], yesterday.beginning_of_day,
                         yesterday.beginning_of_day + 8.hours, :confirmed, 'Home', counts)
      add_timeline_visit(user, places[:work], yesterday.beginning_of_day + 9.hours,
                         yesterday.beginning_of_day + 17.hours,          :confirmed, 'Office', counts)
      add_timeline_visit(user, places[:gym],  yesterday.beginning_of_day + 18.hours,
                         yesterday.beginning_of_day + 19.hours,          :declined,  'Gym',    counts)
      add_timeline_visit(user, places[:food], yesterday.beginning_of_day + 19.hours + 30.minutes,
                         yesterday.beginning_of_day + 20.hours + 15.minutes, :suggested, nil, counts,
                         alternates: [places[:food], places[:coffee]])

      # --- 2 DAYS AGO: all-day home (exercises the compact collapse) -----
      add_timeline_visit(user, places[:home], day_before.beginning_of_day,
                         day_before.beginning_of_day + 23.hours + 59.minutes, :confirmed, 'Home', counts)

      # --- Sprinkle across the last 14 days so the heatmap has shape -----
      (3..14).each do |days_ago|
        next if days_ago.odd? && days_ago > 10 # a few gaps for realism

        date = today - days_ago.days
        add_timeline_visit(user, places[:home], date.beginning_of_day, date.beginning_of_day + 8.hours,
                           :confirmed, 'Home',   counts)
        add_timeline_visit(user, places[:work], date.beginning_of_day + 9.hours, date.beginning_of_day + 17.hours,
                           :confirmed, 'Office', counts)

        # Occasional midday café or bakery visit
        next unless (days_ago % 3).zero?

        midday_place = [places[:coffee], places[:food]].sample
        add_timeline_visit(user, midday_place, date.beginning_of_day + 12.hours + 15.minutes,
                           date.beginning_of_day + 13.hours, :confirmed, nil, counts)
      end
    end

    {
      tags:      tags.size,
      places:    places.size,
      visits:    counts.values.sum,
      by_status: counts.map { |k, v| "#{v} #{k}" }.join(', ')
    }
  end

  def timeline_demo_tags(user)
    TIMELINE_CATEGORIES.values.map do |cat|
      tag = user.tags.find_or_initialize_by(name: cat[:tag])
      tag.icon  = cat[:icon]  if tag.icon.blank?
      tag.color = cat[:color] if tag.color.blank?
      tag.save!
      tag
    end
  end

  def timeline_demo_places(user, tags)
    tag_by_name = tags.index_by(&:name)

    TIMELINE_CATEGORIES.each_with_object({}) do |(key, cat), acc|
      lat = (BERLIN_BASE[:lat] + cat[:lat_offset]).round(5)
      lon = (BERLIN_BASE[:lon] + cat[:lon_offset]).round(5)

      place = Place.find_or_initialize_by(latitude: lat, longitude: lon)
      place.user    ||= user
      place.name      = cat[:name]
      place.lonlat    = "POINT(#{lon} #{lat})"
      place.note      = cat[:note] if cat[:note] && place.note.blank?
      place.save!

      matching_tag = tag_by_name[cat[:tag]]
      place.tags << matching_tag if matching_tag && !place.tags.include?(matching_tag)

      acc[key] = place
    end
  end

  # visit.duration is stored in MINUTES.
  def add_timeline_visit(user, place, starts, ends, status, name, counts, alternates: nil)
    duration_minutes = ((ends - starts) / 60).to_i

    visit = user.visits.create!(
      name:       name.presence || place.name,
      place:      place,
      started_at: starts,
      ended_at:   ends,
      duration:   duration_minutes,
      status:     status
    )

    Array(alternates).uniq.each do |alt|
      PlaceVisit.find_or_create_by!(visit: visit, place: alt)
    end

    counts[status] += 1
    visit
  end
end

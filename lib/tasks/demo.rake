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
      puts "   API Key: #{user.api_key}"
    else
      puts "ℹ️  User already exists: #{user.email}"
    end

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

    # 7. Create family with members
    puts "\n👨‍👩‍👧‍👦 Creating demo family..."
    family_members = create_family_with_members(user)
    puts "✅ Created family with #{family_members.count} members"

    puts "\n" + '=' * 60
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
    puts "   Family Members: #{family_members.count}"
    puts "\n🔐 Login credentials:"
    puts '   Email: demo@dawarich.app'
    puts '   Password: password'
    puts "\n👨‍👩‍👧‍👦 Family member credentials:"
    family_members.each_with_index do |member, index|
      puts "   Member #{index + 1}: #{member.email} / password"
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

      # Create visit with place
      visit = user.visits.create!(
        name: place.name,
        place: place,
        started_at: started_at,
        ended_at: ended_at,
        duration: (ended_at - started_at).to_i,
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
      print '.' if (index + 1) % 10 == 0
    end

    puts '' if created_count > 0
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
    owner_membership = Family::Membership.find_or_create_by!(
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

        points_count.times do |point_index|
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

  def create_tracks(user, count)
    # Get points that aren't already assigned to tracks
    available_points = Point.where(user_id: user.id, track_id: nil)
                            .order(:timestamp)

    if available_points.count < 10
      puts "   ⚠️  Not enough untracked points to create tracks"
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
      avg_speed = duration > 0 ? (total_distance / duration.to_f) : 0

      # Calculate elevation data
      elevations = track_points.map(&:altitude).compact
      elevation_gain = 0
      elevation_loss = 0
      elevation_max = elevations.any? ? elevations.max : 0
      elevation_min = elevations.any? ? elevations.min : 0

      if elevations.length > 1
        elevations.each_cons(2) do |alt1, alt2|
          diff = alt2 - alt1
          if diff > 0
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

      created_count += 1
      print '.' if (index + 1) % 5 == 0
    end

    puts '' if created_count > 0
    created_count
  end

  def haversine_distance(lat1, lon1, lat2, lon2)
    # Haversine formula to calculate distance in meters
    rad_per_deg = Math::PI / 180
    rm = 6371000 # Earth radius in meters

    dlat_rad = (lat2 - lat1) * rad_per_deg
    dlon_rad = (lon2 - lon1) * rad_per_deg

    lat1_rad = lat1 * rad_per_deg
    lat2_rad = lat2 * rad_per_deg

    a = Math.sin(dlat_rad / 2)**2 + Math.cos(lat1_rad) * Math.cos(lat2_rad) * Math.sin(dlon_rad / 2)**2
    c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a))

    rm * c # Distance in meters
  end
end

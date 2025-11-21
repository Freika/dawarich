# frozen_string_literal: true

namespace :demo do
  desc 'Seed demo data: user, points from GeoJSON, visits, and areas'
  task :seed_data, [:geojson_path] => :environment do |_t, args|
    geojson_path = args[:geojson_path] || Rails.root.join('tmp', 'demo_data.geojson').to_s

    unless File.exist?(geojson_path)
      puts "Error: GeoJSON file not found at #{geojson_path}"
      puts "Usage: rake demo:seed_data[path/to/file.geojson]"
      puts "Or place file at tmp/demo_data.geojson"
      exit 1
    end

    puts "🚀 Starting demo data generation..."
    puts "=" * 60

    # 1. Create demo user
    puts "\n📝 Creating demo user..."
    user = User.find_or_initialize_by(email: 'demo@dawarich.app')

    if user.new_record?
      user.password = 'password'
      user.password_confirmation = 'password'
      user.save!
      user.update!(status: :active, active_until: 1000.years.from_now)
      puts "✅ User created: #{user.email}"
      puts "   Password: password"
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
      puts "❌ No points found after import. Cannot create visits and areas."
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

    puts "\n" + "=" * 60
    puts "🎉 Demo data generation complete!"
    puts "=" * 60
    puts "\n📊 Summary:"
    puts "   User: #{user.email}"
    puts "   Points: #{Point.where(user_id: user.id).count}"
    puts "   Places: #{user.visits.joins(:place).select('DISTINCT places.id').count}"
    puts "   Suggested Visits: #{user.visits.suggested.count}"
    puts "   Confirmed Visits: #{user.visits.confirmed.count}"
    puts "   Areas: #{user.areas.count}"
    puts "\n🔐 Login credentials:"
    puts "   Email: demo@dawarich.app"
    puts "   Password: password"
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
      print "." if (index + 1) % 10 == 0
    end

    puts "" if created_count > 0
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
    lat1, lon1 = point1.lat, point1.lon
    lat2, lon2 = point2.lat, point2.lon

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
end

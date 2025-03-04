class Visits::SmartDetect
  MINIMUM_VISIT_DURATION = 5.minutes
  MAXIMUM_VISIT_GAP = 30.minutes
  MINIMUM_POINTS_FOR_VISIT = 3
  SIGNIFICANT_PLACE_VISITS = 2 # Number of visits to consider a place significant
  SIGNIFICANT_MOVEMENT_THRESHOLD = 50 # meters

  attr_reader :user, :start_at, :end_at, :points

  def initialize(user, start_at:, end_at:)
    @user = user
    @start_at = start_at.to_i
    @end_at = end_at.to_i
    @points = user.tracked_points.not_visited
                  .order(timestamp: :asc)
                  .where(timestamp: start_at..end_at)
  end

  def call
    return [] if points.empty?

    potential_visits = detect_potential_visits
    merged_visits = merge_consecutive_visits(potential_visits)
    grouped_visits = group_nearby_visits(merged_visits).flatten

    create_visits(grouped_visits)
  end

  private

  def detect_potential_visits
    visits = []
    current_visit = nil

    points.each do |point|
      if current_visit.nil?
        current_visit = initialize_visit(point)
        next
      end

      if belongs_to_current_visit?(point, current_visit)
        current_visit[:points] << point
        current_visit[:end_time] = point.timestamp
      else
        visits << finalize_visit(current_visit) if valid_visit?(current_visit)
        current_visit = initialize_visit(point)
      end
    end

    # Handle the last visit
    visits << finalize_visit(current_visit) if current_visit && valid_visit?(current_visit)

    visits
  end

  def merge_consecutive_visits(visits)
    return visits if visits.empty?

    merged = []
    current_merged = visits.first

    visits[1..-1].each do |visit|
      if can_merge_visits?(current_merged, visit)
        # Merge the visits
        current_merged[:end_time] = visit[:end_time]
        current_merged[:points].concat(visit[:points])
      else
        merged << current_merged
        current_merged = visit
      end
    end

    merged << current_merged
    merged
  end

  def can_merge_visits?(first_visit, second_visit)
    return false unless same_location?(first_visit, second_visit)
    return false if gap_too_large?(first_visit, second_visit)
    return false if significant_movement_between?(first_visit, second_visit)

    true
  end

  def same_location?(first_visit, second_visit)
    distance = Geocoder::Calculations.distance_between(
      [first_visit[:center_lat], first_visit[:center_lon]],
      [second_visit[:center_lat], second_visit[:center_lon]]
    )

    # Convert to meters and check if within threshold
    (distance * 1000) <= SIGNIFICANT_MOVEMENT_THRESHOLD
  end

  def gap_too_large?(first_visit, second_visit)
    gap = second_visit[:start_time] - first_visit[:end_time]
    gap > MAXIMUM_VISIT_GAP
  end

  def significant_movement_between?(first_visit, second_visit)
    # Get points between the two visits
    between_points = points.where(
      timestamp: (first_visit[:end_time] + 1)..(second_visit[:start_time] - 1)
    )

    return false if between_points.empty?

    visit_center = [first_visit[:center_lat], first_visit[:center_lon]]
    max_distance = between_points.map do |point|
      Geocoder::Calculations.distance_between(
        visit_center,
        [point.lat, point.lon]
      )
    end.max

    # Convert to meters and check if exceeds threshold
    (max_distance * 1000) > SIGNIFICANT_MOVEMENT_THRESHOLD
  end

  def initialize_visit(point)
    {
      start_time: point.timestamp,
      end_time: point.timestamp,
      center_lat: point.lat,
      center_lon: point.lon,
      points: [point]
    }
  end

  def belongs_to_current_visit?(point, visit)
    time_gap = point.timestamp - visit[:end_time]
    return false if time_gap > MAXIMUM_VISIT_GAP

    # Calculate distance from visit center
    distance = Geocoder::Calculations.distance_between(
      [visit[:center_lat], visit[:center_lon]],
      [point.lat, point.lon]
    )

    # Dynamically adjust radius based on visit duration
    max_radius = calculate_max_radius(visit[:end_time] - visit[:start_time])

    distance <= max_radius
  end

  def calculate_max_radius(duration_seconds)
    # Start with a small radius for short visits, increase for longer stays
    # but cap it at a reasonable maximum
    base_radius = 0.05 # 50 meters
    duration_hours = duration_seconds / 3600.0
    [base_radius * (1 + Math.log(1 + duration_hours)), 0.5].min # Cap at 500 meters
  end

  def valid_visit?(visit)
    duration = visit[:end_time] - visit[:start_time]
    visit[:points].size >= MINIMUM_POINTS_FOR_VISIT && duration >= MINIMUM_VISIT_DURATION
  end

  def finalize_visit(visit)
    points = visit[:points]
    center = calculate_center(points)

    visit.merge(
      duration: visit[:end_time] - visit[:start_time],
      center_lat: center[0],
      center_lon: center[1],
      radius: calculate_visit_radius(points, center),
      suggested_name: suggest_place_name(points)
    )
  end

  def calculate_center(points)
    lat_sum = points.sum(&:lat)
    lon_sum = points.sum(&:lon)
    count = points.size.to_f

    [lat_sum / count, lon_sum / count]
  end

  def calculate_visit_radius(points, center)
    max_distance = points.map do |point|
      Geocoder::Calculations.distance_between(center, [point.lat, point.lon])
    end.max

    # Convert to meters and ensure minimum radius
    [(max_distance * 1000), 15].max
  end

  def suggest_place_name(points)
    # Get points with geodata
    geocoded_points = points.select { |p| p.geodata.present? && !p.geodata.empty? }
    return nil if geocoded_points.empty?

    # Extract all features from points' geodata
    features = geocoded_points.flat_map do |point|
      next [] unless point.geodata['features'].is_a?(Array)

      point.geodata['features']
    end.compact

    return nil if features.empty?

    # Group features by type and count occurrences
    feature_counts = features.group_by { |f| f.dig('properties', 'type') }
                             .transform_values(&:size)

    # Find the most common feature type
    most_common_type = feature_counts.max_by { |_, count| count }&.first
    return nil unless most_common_type

    # Get all features of the most common type
    common_features = features.select { |f| f.dig('properties', 'type') == most_common_type }

    # Group these features by name and get the most common one
    name_counts = common_features.group_by { |f| f.dig('properties', 'name') }
                                 .transform_values(&:size)
    most_common_name = name_counts.max_by { |_, count| count }&.first

    return unless most_common_name.present?

    # If we have a name, try to get additional context
    feature = common_features.find { |f| f.dig('properties', 'name') == most_common_name }
    properties = feature['properties']

    # Build a more descriptive name if possible
    [
      most_common_name,
      properties['street'],
      properties['city'],
      properties['state']
    ].compact.uniq.join(', ')
  end

  def group_nearby_visits(visits)
    visits.group_by do |visit|
      [
        (visit[:center_lat] * 1000).round / 1000.0,
        (visit[:center_lon] * 1000).round / 1000.0
      ]
    end.values
  end

  def significant_duration?(visits)
    total_duration = visits.sum { |v| v[:duration] }
    total_duration >= 1.hour
  end

  def near_known_place?(visit)
    # Check if the visit is near a known area or previously confirmed place
    center = [visit[:center_lat], visit[:center_lon]]

    user.areas.any? { |area| near_area?(center, area) } ||
      user.places.any? { |place| near_place?(center, place) }
  end

  def near_area?(center, area)
    distance = Geocoder::Calculations.distance_between(
      center,
      [area.latitude, area.longitude]
    )
    distance * 1000 <= area.radius # Convert to meters
  end

  def near_place?(center, place)
    distance = Geocoder::Calculations.distance_between(
      center,
      [place.latitude, place.longitude]
    )
    distance <= 0.05 # 50 meters
  end

  def create_visits(visits)
    visits.map do |visit_data|
      ActiveRecord::Base.transaction do
        # Try to find matching area or place
        area = find_matching_area(visit_data)
        place = area ? nil : find_or_create_place(visit_data)

        visit = Visit.create!(
          user: user,
          area: area,
          place: place,
          started_at: Time.zone.at(visit_data[:start_time]),
          ended_at: Time.zone.at(visit_data[:end_time]),
          duration: visit_data[:duration] / 60, # Convert to minutes
          name: generate_visit_name(area, place, visit_data[:suggested_name]),
          status: :suggested # Use the new status
        )

        Point.where(id: visit_data[:points].map(&:id)).update_all(visit_id: visit.id)

        visit
      end
    end
  end

  def find_matching_area(visit_data)
    user.areas.find do |area|
      near_area?([visit_data[:center_lat], visit_data[:center_lon]], area)
    end
  end

  def find_or_create_place(visit_data)
    lat = visit_data[:center_lat].round(5)
    lon = visit_data[:center_lon].round(5)
    name = visit_data[:suggested_name]

    # Define the search radius in meters
    search_radius = 100 # Adjust this value as needed

    # First check by exact coordinates
    existing_place = Place.where('ST_DWithin(lonlat, ST_SetSRID(ST_MakePoint(?, ?), 4326), 1)', lon, lat).first

    # If no exact match, check by name within radius
    existing_place ||= Place.where(name: name)
                            .where('ST_DWithin(lonlat, ST_SetSRID(ST_MakePoint(?, ?), 4326), ?)', lon, lat, search_radius)
                            .first

    return existing_place if existing_place

    # Use a database transaction with a lock to prevent race conditions
    Place.transaction do
      # Check again within transaction to prevent race conditions
      existing_place = Place.where('ST_DWithin(lonlat, ST_SetSRID(ST_MakePoint(?, ?), 4326), 50)', lon, lat)
                            .lock(true)
                            .first

      return existing_place if existing_place

      # If no existing place is found, create a new one
      place = Place.new(
        lonlat: "POINT(#{lon} #{lat})",
        latitude: lat,
        longitude: lon
      )

      # Get reverse geocoding data
      geocoded_data = Geocoder.search([lat, lon])

      if geocoded_data.present?
        first_result = geocoded_data.first
        data = first_result.data.with_indifferent_access
        properties = data['properties'] || {}

        # Build a descriptive name from available components
        name_components = [
          properties['name'],
          properties['street'],
          properties['housenumber'],
          properties['postcode'],
          properties['city']
        ].compact.uniq

        place.name = name_components.any? ? name_components.join(', ') : Place::DEFAULT_NAME
        place.city = properties['city']
        place.country = properties['country']
        place.geodata = data
        place.source = :photon

        place.save!

        # Process nearby organizations outside the main transaction
        process_nearby_organizations(geocoded_data.drop(1))
      else
        place.name = visit_data[:suggested_name] || Place::DEFAULT_NAME
        place.source = :manual
        place.save!
      end

      place
    end
  end

  # Extract nearby organizations processing to a separate method
  def process_nearby_organizations(geocoded_data)
    # Fetch nearby organizations
    nearby_organizations = fetch_nearby_organizations(geocoded_data)

    # Save each organization as a possible place
    nearby_organizations.each do |org|
      lon = org[:longitude]
      lat = org[:latitude]

      # Check if a similar place already exists
      existing = Place.where(name: org[:name])
                      .where('ST_DWithin(lonlat, ST_SetSRID(ST_MakePoint(?, ?), 4326), 1)', lon, lat)
                      .first

      next if existing

      Place.create!(
        name: org[:name],
        lonlat: "POINT(#{lon} #{lat})",
        latitude: lat,
        longitude: lon,
        city: org[:city],
        country: org[:country],
        geodata: org[:geodata],
        source: :photon
      )
    end
  end

  def fetch_nearby_organizations(geocoded_data)
    geocoded_data.map do |result|
      data = result.data
      properties = data['properties'] || {}

      {
        name: properties['name'] || 'Unknown Organization',
        latitude: result.latitude,
        longitude: result.longitude,
        city: properties['city'],
        country: properties['country'],
        geodata: data
      }
    end
  end

  def generate_visit_name(area, place, suggested_name)
    return area.name if area
    return place.name if place
    return suggested_name if suggested_name.present?

    'Unknown Location'
  end
end

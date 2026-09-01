# frozen_string_literal: true

FactoryBot.define do
  factory :point do
    battery         { 1 }
    altitude        { 1 }
    velocity        { 0 }
    vertical_accuracy { 1 }
    accuracy { 1 }
    # Sequential timestamps: the model validates uniqueness of (user, lonlat,
    # timestamp), and rand(1_000) produced birthday-paradox collisions whenever
    # a spec created several same-coordinate points ("usually red" CI).
    sequence(:timestamp) { |n| DateTime.new(2024, 5, 1).to_i + (n % 100_000) * 10 }
    raw_data        { '' }
    import_id       { '' }
    city            { nil }
    reverse_geocoded_at { nil }
    course          { nil }
    course_accuracy { nil }
    lonlat { "POINT(#{longitude} #{latitude})" }
    user
    country_id { nil }

    transient do
      country { nil }
      tracker_id { nil }
      # Sequential coordinates for the same reason as timestamps above:
      # FFaker::Geolocation draws from only ~66 values per axis, which
      # collides with the (user, lonlat, timestamp) uniqueness validation
      # whenever a spec pins the same timestamp across several points.
      sequence(:longitude) { |n| -179.0 + ((n * 0.37) % 358.0) }
      sequence(:latitude)  { |n| -89.0 + ((n * 0.19) % 178.0) }
    end

    # Keep user.points_count in sync (counter_cache was removed from belongs_to :user)
    after(:create) do |point, _|
      User.update_counters(point.user_id, points_count: 1)
      point.user.reload
    end

    after(:destroy) do |point|
      User.update_counters(point.user_id, points_count: -1)
    end

    # Handle country string assignment by creating Country objects
    after(:create) do |point, evaluator|
      if evaluator.country.is_a?(String)
        # Set both the country string attribute and the Country association
        country_obj = Country.find_or_create_by(name: evaluator.country) do |country|
          iso_a2, iso_a3 = Countries::IsoCodeMapper.fallback_codes_from_country_name(evaluator.country)
          country.iso_a2 = iso_a2
          country.iso_a3 = iso_a3
          country.geom = 'MULTIPOLYGON (((0 0, 1 0, 1 1, 0 1, 0 0)))'
        end
        point.update_columns(country_id: country_obj.id)
      elsif evaluator.country
        point.update_columns(country_id: evaluator.country.id)
      end
    end

    # Device/importer context lives on the point_sources dimension.
    after(:build) do |point, evaluator|
      next if evaluator.tracker_id.nil? || point.source_id

      row = { tracker_id: evaluator.tracker_id }
      Points::DimensionResolver.new.stamp([row])
      point.source_id = row[:source_id]
    end

    trait :with_source do
      source factory: %i[point_source]
    end

    trait :with_known_location do
      lonlat { 'POINT(37.6173 55.755826)' }
    end

    trait :with_geodata do
      geodata do
        {
          'type' => 'Feature',
          'geometry' => { 'type' => 'Point', 'coordinates' => [37.6177036, 55.755847] },
          'properties' => {
            'city' => 'Moscow',
            'name' => 'Kilometre zero',
            'type' => 'house',
            'state' => 'Moscow',
            'osm_id' => 583_204_619,
            'street' => 'Манежная площадь',
            'country' => 'Russia',
            'osm_key' => 'tourism',
            'district' => 'Tverskoy',
            'osm_type' => 'N',
            'postcode' => '103265',
            'osm_value' => 'attraction',
            'countrycode' => 'RU'
          }
        }
      end
    end

    trait :reverse_geocoded do
      city { FFaker::Address.city }
      reverse_geocoded_at { Time.current }

      after(:build) do |point, _evaluator|
        # Only set country if not already set by transient attribute
        unless point.country_id
          country_name = FFaker::Address.country
          country_obj = Country.find_or_create_by(name: country_name) do |country|
            iso_a2, iso_a3 = Countries::IsoCodeMapper.fallback_codes_from_country_name(country_name)
            country.iso_a2 = iso_a2
            country.iso_a3 = iso_a3
            country.geom = 'MULTIPOLYGON (((0 0, 1 0, 1 1, 0 1, 0 0)))'
          end
          point.country_id = country_obj.id
        end
      end
    end
  end
end

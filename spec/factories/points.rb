# frozen_string_literal: true

# Module to cache countries during factory creation to avoid N+1 queries
module CountriesCache
  def self.get_or_create(country_name)
    @cache ||= {}
    @cache[country_name] ||= begin
      # Pause Prosopite as this is test data setup, not application code
      Prosopite.pause if defined?(Prosopite)

      country = Country.find_or_create_by(name: country_name) do |c|
        iso_a2, iso_a3 = Countries::IsoCodeMapper.fallback_codes_from_country_name(country_name)
        c.iso_a2 = iso_a2
        c.iso_a3 = iso_a3
        c.geom = "MULTIPOLYGON (((0 0, 1 0, 1 1, 0 1, 0 0)))"
      end

      country
    ensure
      Prosopite.resume if defined?(Prosopite)
    end
  end

  def self.clear
    @cache = {}
  end
end

FactoryBot.define do
  factory :point do
    battery_status  { 1 }
    ping            { 'MyString' }
    battery         { 1 }
    topic           { 'MyString' }
    altitude        { 1 }
    longitude       { FFaker::Geolocation.lng }
    velocity        { 0 }
    trigger         { 1 }
    bssid           { 'MyString' }
    ssid            { 'MyString' }
    connection      { 1 }
    vertical_accuracy { 1 }
    accuracy        { 1 }
    timestamp       { DateTime.new(2024, 5, 1).to_i + rand(1_000).minutes }
    latitude        { FFaker::Geolocation.lat }
    mode            { 1 }
    inrids          { 'MyString' }
    in_regions      { 'MyString' }
    raw_data        { '' }
    tracker_id      { 'MyString' }
    import_id       { '' }
    city            { nil }
    reverse_geocoded_at { nil }
    course          { nil }
    course_accuracy { nil }
    external_track_id { nil }
    lonlat { "POINT(#{longitude} #{latitude})" }
    user
    country_id { nil }

    # Add transient attribute to handle country strings
    transient do
      country { nil }  # Allow country to be passed as string
    end

    # Handle country string assignment by creating Country objects
    after(:create) do |point, evaluator|
      if evaluator.country.is_a?(String)
        # Set both the country string attribute and the Country association
        country_obj = Country.find_or_create_by(name: evaluator.country) do |country|
          iso_a2, iso_a3 = Countries::IsoCodeMapper.fallback_codes_from_country_name(evaluator.country)
          country.iso_a2 = iso_a2
          country.iso_a3 = iso_a3
          country.geom = "MULTIPOLYGON (((0 0, 1 0, 1 1, 0 1, 0 0)))"
        end
        point.update_columns(
          country: evaluator.country,
          country_name: evaluator.country,
          country_id: country_obj.id
        )
      elsif evaluator.country
        point.update_columns(
          country: evaluator.country.name,
          country_name: evaluator.country.name,
          country_id: evaluator.country.id
        )
      end
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

      after(:build) do |point, evaluator|
        # Only set country if not already set by transient attribute
        unless point.read_attribute(:country)
          country_name = FFaker::Address.country

          # Use module-level cache to avoid N+1 queries during factory creation
          country_obj = CountriesCache.get_or_create(country_name)

          point.write_attribute(:country, country_name)        # Set the legacy string attribute
          point.write_attribute(:country_name, country_name)  # Set the new string attribute
          point.country_id = country_obj.id   # Set the association
        end
      end
    end
  end
end

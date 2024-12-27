# frozen_string_literal: true

class DataMigrations::MigratePoint
  def initialize(point)
    @point = point
  end

  def call
    country = find_or_create_country(geodata['country'], geodata['countrycode'])
    state   = find_or_create_state(geodata['state'], country)
    county  = find_or_create_county(geodata['county'], state)
    city    = find_or_create_city(geodata['city'], county)

    point.update(
      country: country,
      state: state,
      county: county,
      city: city,

      osm_id: geodata['osm_id'],
      osm_type: geodata['osm_type'],
      osm_key: geodata['osm_key'],
      osm_value: geodata['osm_value'],

      post_code: geodata['postcode'],
      street: geodata['street'],
      house_number: geodata['housenumber'],
      type: geodata['type'],
      name: geodata['name'],
      district: geodata['district'],
      locality: geodata['locality'],
      importance: geodata['importance'],
      object_type: geodata['objecttype'],
      classification: geodata['classification']
    )
  end

  private

  def geodata
    @geodata ||= @point.geodata['properties']
  end

  def find_or_create_country(country_name, country_code)
    Country.find_or_create_by(name: country_name, iso2_code: country_code)
  end

  def find_or_create_state(state_name, country)
    State.find_or_create_by(name: state_name, country: country)
  end

  def find_or_create_county(county_name, state)
    County.find_or_create_by(name: county_name, state: state)
  end

  def find_or_create_city(city_name, county)
    City.find_or_create_by(name: city_name, county: county)
  end
end

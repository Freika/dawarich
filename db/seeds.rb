# frozen_string_literal: true

if User.none?
  puts 'Creating user...'

  User.create!(
    email: 'demo@dawarich.app',
    password: 'password',
    password_confirmation: 'password',
    admin: true
  )

  puts "User created: #{User.first.email} / password: 'password'"
end

if Country.none?
  puts 'Creating countries...'

  countries_json = Oj.load(File.read(Rails.root.join('lib/assets/countries.geojson')))

  factory = RGeo::Geos.factory(srid: 4326)
  countries_multi_polygon = RGeo::GeoJSON.decode(countries_json.to_json, geo_factory: factory)

  ActiveRecord::Base.transaction do
    countries_multi_polygon.each do |country, index|
      p "Creating #{country.properties['name']}..."

      Country.create!(
        name: country.properties['name'],
        iso_a2: country.properties['ISO3166-1-Alpha-2'],
        iso_a3: country.properties['ISO3166-1-Alpha-3'],
        geom: country.geometry
      )
    end
  end
end

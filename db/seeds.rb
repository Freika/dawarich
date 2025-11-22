# frozen_string_literal: true

if User.none?
  puts 'Creating user...'

  email = 'demo@dawarich.app'

  User.create!(
    email:,
    password: 'password',
    password_confirmation: 'password',
    admin: true,
    status: :active,
    active_until: 100.years.from_now
  )

  puts "User created: '#{email}' / password: 'password'"
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

if Tag.none?
  puts 'Creating default tags...'

  default_tags = [
    { name: 'Home', color: '#FF5733', icon: '🏡' },
    { name: 'Work', color: '#33FF57', icon: '💼' },
    { name: 'Favorite', color: '#3357FF', icon: '⭐' },
    { name: 'Travel Plans', color: '#F1C40F', icon: '🗺️' },
  ]

  default_tags.each do |tag_attrs|
    Tag.create!(tag_attrs)
  end
end

# frozen_string_literal: true

# Geocoders return OSM English names; the countries table is seeded with the
# Natural Earth names from lib/assets/countries.geojson, and the two disagree
# for a handful of countries. Every alias here was observed in stored point
# data that a plain name match failed to resolve. One canonical map, rendered
# into SQL for the backfill and used directly for live lookups, so both paths
# resolve identically.
module Countries
  module NameAliases
    ALIASES = {
      'United States' => 'United States of America',
      'Serbia' => 'Republic of Serbia',
      'Tanzania' => 'United Republic of Tanzania',
      'Vatican City' => 'Vatican',
      'Palestinian Territory' => 'Palestine',
      'Palestinian Territories' => 'Palestine',
      'Congo-Brazzaville' => 'Republic of the Congo',
      'Eswatini' => 'eSwatini',
      "Côte d'Ivoire" => 'Ivory Coast',
      'Côte d’Ivoire' => 'Ivory Coast'
    }.freeze

    def self.canonical(name)
      ALIASES.fetch(name, name)
    end

    # A (alias, canonical) VALUES list for joining alias names onto the
    # countries table in raw SQL.
    def self.values_sql
      rows = ALIASES.map do |alias_name, canonical|
        "(#{quote(alias_name)}, #{quote(canonical)})"
      end

      "(VALUES #{rows.join(', ')})"
    end

    def self.quote(value)
      ActiveRecord::Base.connection.quote(value)
    end
    private_class_method :quote
  end
end

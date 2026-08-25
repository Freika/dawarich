# frozen_string_literal: true

# Geocoders return OSM English names; the countries table is seeded with the
# Natural Earth names from lib/assets/countries.geojson, and the two disagree
# for a handful of countries. Aliases come from two sources: names observed
# unresolved in stored point data, and known OSM-vs-seed divergences that the
# name-only backfill could never recover once the name columns are dropped.
# One canonical map, rendered into SQL for the backfill and used directly for
# live lookups, so both paths resolve identically. Every canonical value must
# exist verbatim in the seed — the spec enforces it against the geojson.
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
      'Côte d’Ivoire' => 'Ivory Coast',
      'Timor-Leste' => 'East Timor',
      'The Gambia' => 'Gambia',
      'Cape Verde' => 'Cabo Verde',
      'Hong Kong' => 'Hong Kong S.A.R.',
      'Macau' => 'Macao S.A.R',
      'Macao' => 'Macao S.A.R',
      'Congo-Kinshasa' => 'Democratic Republic of the Congo',
      'Saint Barthélemy' => 'Saint Barthelemy',
      'São Tomé and Príncipe' => 'São Tomé and Principe'
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

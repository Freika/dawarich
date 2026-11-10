# frozen_string_literal: true

# Geocoders return OSM English names; the countries table is seeded with the
# Natural Earth names from lib/assets/countries.geojson.gz, and the two disagree
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

    SPELLINGS = ALIASES.keys.group_by { |alias_name| ALIASES[alias_name] }
                       .to_h { |canonical_name, aliases| [canonical_name, [canonical_name, *aliases].freeze] }
                       .freeze

    # The name a point counts under: its linked country, then the alias map,
    # then the stored text. Needs point_joins_sql in the same query.
    POINT_NAME_SQL = 'COALESCE(countries.name, country_aliases.canonical, points.country_name)'

    def self.canonical(name)
      ALIASES.fetch(name, name)
    end

    def self.spellings(name)
      SPELLINGS.fetch(canonical(name), [name])
    end

    # Every form of each aliased country that has a form containing the text.
    def self.spellings_containing(text)
      needle = text.downcase
      SPELLINGS.values.select { |forms| forms.any? { |form| form.downcase.include?(needle) } }.flatten
    end

    # Merges the entries of one country in a summary stored before the names
    # were unified, without changing what is stored.
    def self.merge_toponyms(toponyms)
      return toponyms unless toponyms.is_a?(Array)

      merged = {}

      toponyms.filter_map do |toponym|
        country = canonical(toponym['country']) if toponym.is_a?(Hash)
        next toponym unless SPELLINGS.key?(country)

        if merged.key?(country)
          merged[country]['cities'] = merge_cities(Array(merged[country]['cities']) + Array(toponym['cities']))
          next
        end

        merged[country] = toponym.merge('country' => country)
      end
    end

    # Same merge for [{ 'name', 'minutes' }] rows, longest stay first. A list
    # with no aliased country is returned as stored.
    def self.merge_minutes(rows)
      return rows unless Array(rows).any? { |row| ALIASES.key?(row['name']) }

      rows.group_by { |row| canonical(row['name']) }
          .map { |name, same| same.first.merge('name' => name, 'minutes' => same.sum { |row| row['minutes'].to_i }) }
          .sort_by { |row| [-row['minutes'], row['name'].to_s] }
    end

    def self.point_joins_sql
      'LEFT JOIN countries ON countries.id = points.country_id ' \
        "LEFT JOIN #{values_sql} AS country_aliases(alias, canonical) ON country_aliases.alias = points.country_name"
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

    def self.merge_cities(cities)
      cities.group_by { |city| city['city'] }.values.map do |visits|
        next visits.first if visits.one?

        visits.first.merge(
          'points' => visits.sum { |visit| visit['points'].to_i },
          'timestamp' => visits.map { |visit| visit['timestamp'].to_i }.max,
          'stayed_for' => visits.sum { |visit| visit['stayed_for'].to_i }
        )
      end
    end
    private_class_method :merge_cities
  end
end

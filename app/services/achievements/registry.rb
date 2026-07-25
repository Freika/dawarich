# frozen_string_literal: true

module Achievements
  Definition = Data.define(:key, :kind, :name, :country, :continent, :card, :threshold, :regions,
                           :level, :parent_key) do
    def initialize(card: {}, country: nil, continent: nil, threshold: nil, level: :country,
                   parent_key: nil, **rest)
      super
    end

    def region_codes
      regions.keys
    end

    def total
      regions.size
    end

    def target
      threshold || total
    end

    def flat?
      kind == 'country' && level == :country
    end
  end

  class Registry
    HAND_PATH = 'config/achievements.yml'
    PLANET_PATH = 'config/achievements/planet.yml'
    NO_META_CONTINENT = 'Antarctica'

    class << self
      def all
        @all ||= hand_definitions + continent_definitions + country_definitions
      end

      def region_sets
        all
      end

      def subdivision_sets
        @subdivision_sets ||= all.select { |definition| definition.level == :subdivision }
      end

      def country_codes
        @country_codes ||= all.select { |definition| definition.kind == 'country' }.map(&:country).to_set
      end

      def subdivision_codes
        @subdivision_codes ||= subdivision_sets.flat_map(&:region_codes).to_set
      end

      def find(key)
        index[key]
      end

      def reset!
        @all = nil
        @index = nil
        @planet = nil
        @hand_yaml = nil
        @country_universe = nil
        @subdivision_sets = nil
        @country_codes = nil
        @subdivision_codes = nil
      end

      private

      def index
        @index ||= all.index_by(&:key)
      end

      def planet
        @planet ||= YAML.load_file(Rails.root.join(PLANET_PATH))['continents']
      end

      def hand_yaml
        @hand_yaml ||= YAML.load_file(Rails.root.join(HAND_PATH), aliases: true)
      end

      def country_universe
        @country_universe ||= planet.values.flat_map { |data| data['countries'].to_a }
                                           .to_h { |code, country| [code, country['name']] }
      end

      def continent_key(continent)
        "continent_#{continent.downcase.tr(' ', '_')}"
      end

      def hand_definitions
        hand_yaml.reject { |key, _attrs| key.start_with?('_') }.map do |key, attrs|
          Definition.new(
            key: key,
            kind: attrs['kind'],
            name: attrs['name'],
            continent: attrs['continent'],
            card: attrs['card'] || {},
            threshold: attrs['threshold'],
            regions: attrs['regions'] || country_universe
          )
        end
      end

      def continent_definitions
        planet.except(NO_META_CONTINENT).map do |continent, data|
          countries = data['countries'].to_h { |code, country| [code, country['name']] }

          Definition.new(
            key: continent_key(continent),
            kind: 'continent',
            name: "#{continent} Explorer",
            continent: continent,
            card: continent_card(continent, countries.size),
            regions: countries
          )
        end
      end

      def country_definitions
        planet.flat_map do |continent, data|
          data['countries'].map { |code, country| country_definition(continent, code, country) }
        end
      end

      def country_definition(continent, code, country)
        gridded = country['subdivisions'].any?

        Definition.new(
          key: "country_#{code.downcase}",
          kind: 'country',
          name: gridded ? "#{country['name']} Explorer" : country['name'],
          country: code,
          continent: continent,
          card: country_card(country, gridded),
          regions: gridded ? country['subdivisions'] : { code => country['name'] },
          level: gridded ? :subdivision : :country,
          parent_key: (continent_key(continent) unless continent == NO_META_CONTINENT)
        )
      end

      def continent_card(continent, count)
        meta = hand_yaml.fetch('_continents').fetch(continent)

        {
          'rarity' => 'Legendary',
          'description' => "Spend time in all #{count} countries and territories of #{continent}.",
          'flavor' => meta['flavor'],
          'place' => continent,
          'child_zoom' => meta['child_zoom'],
          'art' => meta['art']
        }
      end

      def country_card(country, gridded)
        name = country['name']
        count = country['subdivisions'].size

        {
          'rarity' => 'Rare',
          'description' => gridded ? "Spend time in all #{count} regions of #{name}." : "Spend time in #{name}.",
          'place' => name,
          'child_zoom' => (country['art']['zoom'] + 1.5).round(1),
          'art' => country['art']
        }
      end
    end
  end
end

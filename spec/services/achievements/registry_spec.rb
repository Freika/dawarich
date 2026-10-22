# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Achievements::Registry do
  after { described_class.reset! }

  describe '.all' do
    it 'builds a definition per continent, country and world tier' do
      kinds = described_class.all.group_by(&:kind).transform_values(&:size)

      expect(kinds).to eq('continent' => 6, 'country' => 238, 'region_set' => 3)
    end

    it 'derives keys from continent names and ISO codes' do
      expect(described_class.find('continent_north_america').name).to eq('North America Explorer')
      expect(described_class.find('country_de').name).to eq('Germany Explorer')
      expect(described_class.find('country_no')).to be_present
    end

    it 'gives every definition renderable card metadata' do
      definitions = described_class.all

      definitions.each do |definition|
        expect(definition.card['rarity']).to be_in(%w[Common Rare Epic Legendary])
        expect(definition.card['art']).to include('lat', 'lon', 'zoom')
        expect(definition.card['description']).to be_present
      end
    end
  end

  describe 'country definitions' do
    it 'grids a covered country over its subdivisions' do
      germany = described_class.find('country_de')

      expect(germany.total).to eq(16)
      expect(germany.level).to eq(:subdivision)
      expect(germany).not_to be_flat
      expect(germany.parent_key).to eq('continent_europe')
      expect(germany.card['rarity']).to eq('Rare')
    end

    it 'represents an ungridded country as a single binary card' do
      france = described_class.find('country_fr')

      expect(france).to be_flat
      expect(france.level).to eq(:country)
      expect(france.region_codes).to eq(['FR'])
      expect(france.target).to eq(1)
      expect(france.card['rarity']).to eq('Rare')
    end
  end

  describe 'disputed subdivisions' do
    it 'leaves subdivisions lying almost entirely in disputed areas out of their country' do
      ukraine = described_class.find('country_ua')

      expect(ukraine.region_codes).not_to include('UA-43', 'UA-40')
      expect(ukraine.total).to eq(25)
      expect(ukraine.card['description']).to eq('Spend time in all 25 regions of Ukraine.')
    end

    it 'lists exactly the planet subdivisions lying at least 75% inside a disputed area' do
      Achievements::LoadDisputedAreas.new.call
      planet = YAML.load_file(Rails.root.join(described_class::PLANET_PATH))['continents']
      planet_codes = planet.values.flat_map do |continent|
        continent['countries'].values.flat_map { |country| country['subdivisions'].keys }
      end
      sql = <<~SQL
        SELECT feature -> 'properties' ->> 'iso_3166_2'
        FROM jsonb_array_elements(?::jsonb -> 'features') AS feature
        CROSS JOIN LATERAL (
          SELECT ST_MakeValid(ST_SetSRID(ST_GeomFromGeoJSON(feature ->> 'geometry'), 4326)) AS g
        ) region
        WHERE ST_Area(ST_Intersection(region.g, (
                SELECT ST_Union(d.geom) FROM disputed_areas d WHERE ST_Intersects(d.geom, region.g)
              ))::geography) >= 0.75 * ST_Area(region.g::geography)
      SQL
      asset = Rails.root.join(Achievements::LoadRegions::ASSET_PATH).read
      covered = ActiveRecord::Base.connection.select_values(ActiveRecord::Base.sanitize_sql_array([sql, asset]))

      expect(covered & planet_codes).to match_array(described_class::DISPUTED_SUBDIVISIONS)
    end

    it 'never resolves them to a parent set' do
      expect(described_class.subdivision_codes).not_to include('GE-AB', 'IN-JK', 'MD-SN')
      expect(described_class.subdivision_parent_for('UA-43')).to be_nil
    end
  end

  describe 'continent definitions' do
    it 'collects the countries of its continent' do
      europe = described_class.find('continent_europe')

      expect(europe.level).to eq(:country)
      expect(europe.total).to eq(50)
      expect(europe.region_codes).to include('DE', 'FR', 'NO')
      expect(europe.card['rarity']).to eq('Legendary')
    end

    it 'skips the Antarctica meta set but keeps its country card' do
      expect(described_class.find('continent_antarctica')).to be_nil
      expect(described_class.find('country_aq')).to be_present
    end
  end

  describe 'world tiers' do
    it 'keeps thresholds over the full country universe' do
      border_hopper = described_class.find('border_hopper')

      expect(border_hopper.total).to eq(238)
      expect(border_hopper.target).to eq(5)
      expect(border_hopper.level).to eq(:country)
      expect(described_class.find('globetrotter').target).to eq(15)
      expect(described_class.find('world_traveler').target).to eq(50)
    end
  end

  describe '.subdivision_sets' do
    it 'returns only sets whose regions are subdivisions' do
      expect(described_class.subdivision_sets.map(&:level).uniq).to eq([:subdivision])
      expect(described_class.subdivision_sets.size).to eq(183)
    end
  end
end

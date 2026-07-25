# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'planet achievement data' do
  let(:dataset_regions) do
    ['Africa', 'Antarctica', 'Asia', 'Europe', 'North America', 'Oceania', 'South America']
  end
  let(:unmapped_countries) { %w[BQ BV CC CX GF GP MQ RE SJ TK YT] }
  let(:german_lander) do
    %w[DE-BW DE-BY DE-BE DE-BB DE-HB DE-HH DE-HE DE-MV DE-NI DE-NW DE-RP DE-SL DE-SN DE-ST
       DE-SH DE-TH]
  end

  let(:planet) { YAML.load_file(Rails.root.join('config/achievements/planet.yml')) }
  let(:continents) { planet['continents'] }
  let(:countries) { continents.values.flat_map { |c| c['countries'].to_a }.to_h }

  it 'covers the seven dataset regions' do
    expect(continents.keys).to match_array(dataset_regions)
  end

  it 'keeps only countries that resolve to a countries row' do
    expect(countries.keys).not_to include(*unmapped_countries)
    expect(countries.size).to eq(238)
  end

  it 'grids Germany with every Bundesland' do
    germany = continents.dig('Europe', 'countries', 'DE')

    expect(germany['name']).to eq('Germany')
    expect(germany['subdivisions'].keys).to match_array(german_lander)
  end

  it 'dissolves finer Natural Earth subdivisions up to the ISO first level' do
    expect(countries.fetch('GB')['subdivisions'].keys).to match_array(%w[GB-ENG GB-NIR GB-SCT GB-WLS])
    expect(countries.fetch('IT')['subdivisions'].size).to eq(19)
    expect(countries.fetch('ES')['subdivisions'].size).to eq(19)
  end

  it 'leaves poorly covered countries flat' do
    %w[MK MC PL FR].each do |code|
      expect(countries.fetch(code)['subdivisions']).to be_empty, "expected #{code} to be flat"
    end
  end

  it 'recovers Czechia via the Natural Earth code aliases' do
    czechia = countries.fetch('CZ')['subdivisions']

    expect(czechia.keys).to include('CZ-10', 'CZ-64')
    expect(czechia.size).to eq(14)
    expect(czechia['CZ-10']).to eq('Prague')
  end

  it 'grids the permissive geoBoundaries countries Natural Earth could not cover' do
    expect(countries.fetch('KE')['subdivisions'].size).to eq(47)
    expect(countries.fetch('KE')['subdivisions']).to include('KE-30' => 'Nairobi City')
    expect(countries.fetch('ZA')['subdivisions']['ZA-WC']).to eq('Western Cape')
    expect(countries.fetch('CI')['subdivisions'].size).to eq(14)
  end

  it 'keeps Norway a string key rather than a boolean' do
    expect(continents.dig('Europe', 'countries')).to have_key('NO')
  end

  it 'ships geometry for every gridded subdivision' do
    geojson = Oj.load(File.read(Rails.root.join('lib/assets/admin1_world.geojson')))
    shipped = geojson['features'].map { |f| f['properties']['iso_3166_2'] }
    declared = countries.values.flat_map { |c| c['subdivisions'].keys }

    expect(declared).not_to be_empty
    expect(shipped).to match_array(declared)
  end
end

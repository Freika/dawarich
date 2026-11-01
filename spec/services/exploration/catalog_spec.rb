# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Exploration::Catalog do
  let(:dataset) { Exploration::Dataset.create!(version: 'catalog-test') }
  let(:connection) { ApplicationRecord.connection }

  before do
    # Coarse country land so every catalog boundary is clipped to something.
    connection.execute(<<~SQL)
      INSERT INTO exploration_territories(dataset_id,code,name,boundary,land,land_area)
      SELECT #{dataset.id},code,code,g,g,ST_Area(g::geography) FROM (VALUES
        ('DEU',ST_Multi(ST_MakeEnvelope(5.8,47.2,15.1,55.1,4326))),
        ('BGR',ST_Multi(ST_MakeEnvelope(22.3,41.2,28.7,44.3,4326)))) s(code,g)
    SQL
  end

  it 'imports every regional file with its own catalog version' do
    described_class.import!(dataset)

    territories = Exploration::Territory.where(dataset_id: dataset.id).where.not(kind: 'country')
    versions = territories.to_h { |t| [t.name, t.source_metadata['catalog_version']] }
    expect(versions).to include('Berlin' => 'germany-pilot-20261028-v1', 'Sofia' => 'bulgaria-20261101-v1')
    expect(territories.where(kind: 'city').count).to eq(30)
    expect(territories.where(kind: 'city').pluck(:name)).to include('Dresden', 'Plovdiv', 'Veliko Tarnovo', 'Smolyan')
    expect(territories.where(kind: 'park').count).to eq(6)
  end

  it 'gives Bulgarian territories valid land in the Sofia timezone' do
    described_class.import!(dataset)

    bulgarian = Exploration::Territory.where(dataset_id: dataset.id, timezone: 'Europe/Sofia')
    expect(bulgarian.count).to eq(30)
    expect(bulgarian.where("NOT ST_IsValid(land) OR land_area <= 0 OR land_area = 'NaN'::float")).to be_empty
    central_balkan = bulgarian.find_by!(code: 'park_osm_relation_1404501')
    expect(central_balkan.source_metadata['local_name']).to eq('Централен Балкан')
  end

  it 'refuses a regional file whose checksum does not match' do
    tampered = Rails.root.join(described_class::ROOT, 'bulgaria.geojson.gz')
    allow(Digest::SHA256).to receive(:file).and_call_original
    wrong = instance_double(Digest::SHA256, hexdigest: '0' * 64)
    allow(Digest::SHA256).to receive(:file).with(tampered).and_return(wrong)

    expect { described_class.import!(dataset) }.to raise_error('Achievement catalog checksum mismatch')
  end
end

# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Exploration::Result do
  let(:user) { create(:user) }
  let(:dataset) { Exploration::Dataset.create!(version: "world-#{SecureRandom.hex(4)}", completed_at: Time.current) }
  let(:snapshot) { Exploration::Snapshot.create!(user_id: user.id, dataset_id: dataset.id, revision: 1, completed_at: Time.current) }

  def territory(dataset_id, code, area)
    ApplicationRecord.connection.execute(<<~SQL)
      INSERT INTO exploration_territories(dataset_id,code,name,boundary,land,land_area)
      SELECT #{dataset_id},'#{code}','#{code}',g,g,#{area} FROM
      (SELECT ST_Multi(ST_MakeEnvelope(13,52,14,53,4326)) g) s
    SQL
    Exploration::Territory.find_by!(dataset_id: dataset_id, code: code)
  end

  before do
    state = Exploration::State.create!(user_id: user.id, snapshot_id: snapshot.id, revision: 1, published_revision: 1)
    allow(Exploration::Schedule).to receive(:call).with(user).and_return(state)
    allow(Exploration::Geography).to receive(:current).and_return(dataset)
  end

  it 'uses every territory in the published dataset, including unopened land, independently of map dates' do
    opened = territory(dataset.id, 'OPEN', 100)
    territory(dataset.id, 'UNOPENED', 300)
    other = Exploration::Dataset.create!(version: "other-#{SecureRandom.hex(4)}", completed_at: Time.current)
    territory(other.id, 'OTHER', 1_000)
    Exploration::CountryTotal.create!(snapshot_id: snapshot.id, territory_id: opened.id, opened_area: 10, visited: true)

    dataset.update!(world_land_area: 400)
    snapshot.update!(world_opened_area: 10)
    result = described_class.new(user, start_at: 100, end_at: 200).call
    expect(result[:world]).to eq(land_area: 400, opened_area: 10, percentage: 2.5)
    expect(result[:countries].first[:percentage]).to eq(10)
    expect(described_class.new(user, start_at: 300, end_at: 400).call[:world]).to eq(result[:world])

    # An update must not mix the new geography's denominator into the previous snapshot.
    allow(Exploration::Geography).to receive(:current).and_return(other)
    expect(described_class.new(user).call[:world]).to eq(result[:world])
  end

  it 'returns zero for no opened land with a known denominator' do
    territory(dataset.id, 'UNOPENED', 300)
    dataset.update!(world_land_area: 300)
    snapshot.update!(world_opened_area: 0)
    expect(described_class.new(user).call[:world]).to eq(land_area: 300, opened_area: 0, percentage: 0)
  end

  it 'does not fabricate a percentage when the land denominator is unavailable' do
    expect(described_class.new(user).call[:world][:percentage]).to be_nil
  end
end

RSpec.describe Exploration::WorldTotals do
  it 'unions overlapping territories for both world land and each opened cell' do
    dataset = Exploration::Dataset.create!(version: "union-#{SecureRandom.hex(4)}", completed_at: Time.current)
    connection = ApplicationRecord.connection
    %w[A B].each do |code|
      connection.execute(<<~SQL)
        INSERT INTO exploration_territories(dataset_id,code,name,boundary,land,land_area)
        SELECT #{dataset.id},'#{code}','#{code}',g,g,ST_Area(g::geography) FROM
        (SELECT ST_Multi(ST_MakeEnvelope(13,52,14,53,4326)) g) s
      SQL
    end
    described_class.prepare_dataset!(dataset)
    single_territory_area = Exploration::Territory.where(dataset_id: dataset.id).first.land_area
    expect(dataset.world_land_area).to be_within(0.1).of(single_territory_area)

    user = create(:user)
    snapshot = Exploration::Snapshot.create!(user_id: user.id, dataset_id: dataset.id, revision: 1)
    cell = Exploration::CellGeometry.id(52.5, 13.5)
    Exploration::Coverage.ensure!([cell], dataset)
    Exploration::Opening.create!(snapshot_id: snapshot.id, cell_id: cell, first_timestamp: 100, point_id: 1)
    country_sum = Exploration::CellCoverage.find_by!(dataset_id: dataset.id, cell_id: cell).areas.values.sum(&:to_f)
    expect(described_class.opened_area(snapshot)).to be_within(0.1).of(country_sum / 2)
  end
end

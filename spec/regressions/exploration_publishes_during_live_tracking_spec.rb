# frozen_string_literal: true

require 'rails_helper'

# Standalone non-transactional group: it cleans only the rows it creates.
RSpec.describe 'Exploration rebuild while points keep arriving' do
  before(:context) { self.class.use_transactional_tests = false }
  after(:context) { self.class.use_transactional_tests = true }

  let!(:user) { create(:user) }
  let!(:dataset) { Exploration::Dataset.create!(version: "live-#{SecureRandom.hex(6)}", completed_at: Time.current) }

  before do
    allow(Exploration::Geography).to receive_messages(current: dataset, install!: dataset)
    ApplicationRecord.connection.execute(<<~SQL)
      INSERT INTO exploration_territories(dataset_id,code,name,boundary,land,land_area)
      SELECT #{dataset.id},'LIVE','Live',g,g,ST_Area(g::geography) FROM
      (SELECT ST_Multi(ST_MakeEnvelope(13.30,52.49,13.40,52.53,4326)) g) s
    SQL
  end

  after do
    snapshots = Exploration::Snapshot.where(user_id: user.id)
    cells = Exploration::Opening.where(snapshot_id: snapshots.select(:id)).pluck(:cell_id)
    Exploration::CountryTotal.where(snapshot_id: snapshots.select(:id)).delete_all
    Exploration::Opening.where(snapshot_id: snapshots.select(:id)).delete_all
    Exploration::State.where(user_id: user.id).delete_all
    snapshots.delete_all
    ApplicationRecord.connection.execute("DELETE FROM exploration_cell_coverages WHERE dataset_id=#{dataset.id}")
    ApplicationRecord.connection.execute("DELETE FROM exploration_territories WHERE dataset_id=#{dataset.id}")
    Exploration::Cell.where(id: cells).delete_all
    user.points.delete_all
    dataset.destroy!
    user.destroy!
  end

  def add_point(timestamp:, lon:)
    Point.insert_all!([{ user_id: user.id, timestamp: timestamp, lonlat: "POINT(#{lon} 52.514)",
                         created_at: Time.current, updated_at: Time.current }])
  end

  it 'publishes the consistent source snapshot it read and leaves the newer point for the next run' do
    add_point(timestamp: 100, lon: 13.31)
    allow(Exploration::FlightEvidence).to receive(:prepare!).and_wrap_original do |original, *args, **kwargs|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection { add_point(timestamp: 200, lon: 13.39) }
      end.join
      original.call(*args, **kwargs)
    end

    Exploration::Rebuild.new(user).call

    state = Exploration::State.find_by!(user_id: user.id)
    expect(state.snapshot_id).to be_present
    expect(Exploration::Opening.where(snapshot_id: state.snapshot_id).pluck(:first_timestamp)).to eq([100])
    expect(state.revision).to be > state.published_revision
  end
end

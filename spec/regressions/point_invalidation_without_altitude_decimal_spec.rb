# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Point invalidation without altitude_decimal' do
  let(:connection) { ApplicationRecord.connection }
  let(:user) { create(:user) }
  let(:payload) { payload_with_altitude(35) }

  def payload_with_altitude(altitude)
    {
      locations: [{
        type: 'Feature',
        geometry: { type: 'Point', coordinates: [13.405, 52.52] },
        properties: { timestamp: '2026-11-02T12:00:00Z', altitude: altitude }
      }]
    }
  end

  before do
    skip 'column absence regression only applies when the decimal migration did not finish' unless
      connection.column_exists?(:points, :altitude_decimal)

    # Loads Point while the column exists; the model caches column support once per process.
    allow(Point).to receive(:altitude_decimal_supported?).and_return(false)
    connection.remove_column(:points, :altitude_decimal)
    Point.reset_column_information
    %w[db/exploration_invalidation.sql db/achievement_collections_invalidation.sql].each do |path|
      connection.execute(File.read(Rails.root.join(path)))
    end
  end

  after do
    # Point writes arm per-user debounce keys in Redis; don't leak them into later examples.
    [Tracks::RealtimeDebouncer, Visits::RealtimeDebouncer].each { |debouncer| debouncer.new(user.id).clear }
    unless connection.column_exists?(:points, :altitude_decimal)
      connection.add_column(:points, :altitude_decimal, :decimal, precision: 10, scale: 2)
      Point.reset_column_information
    end
  end

  it 'accepts an Overland insert and an upsert update on a legacy points schema' do
    expect { Overland::PointsCreator.new(payload, user.id).call }.not_to raise_error
    # Re-sending the point with a new altitude upserts it, which fires the UPDATE triggers.
    expect { Overland::PointsCreator.new(payload_with_altitude(36), user.id).call }.not_to raise_error

    expect(Point.where(user_id: user.id).count).to eq(1)
    %w[achievement_collection_states exploration_states].each do |table|
      expect(connection.select_value("SELECT revision FROM #{table} WHERE user_id=#{user.id}")).to eq(2)
    end
  end
end

# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Points API without source_id', type: :request do
  let(:connection) { ApplicationRecord.connection }
  let(:user) { create(:user) }

  def payload(altitude)
    {
      locations: [{
        type: 'Feature',
        geometry: { type: 'Point', coordinates: [13.405, 52.52] },
        properties: { timestamp: '2026-11-02T12:00:00Z', altitude: altitude }
      }]
    }
  end

  before do
    # 20260816150000 can defer this column to a background job on a busy instance (#3972).
    connection.execute('ALTER TABLE points DROP COLUMN source_id')
    Point.reset_column_information
    Points::DimensionResolver.instance_variable_set(:@columns_available, nil)
    connection.execute(File.read(Rails.root.join('db/achievement_collections_invalidation.sql')))
  end

  after do
    [Tracks::RealtimeDebouncer, Visits::RealtimeDebouncer].each { |debouncer| debouncer.new(user.id).clear }
    unless connection.column_exists?(:points, :source_id)
      connection.execute('ALTER TABLE points ADD COLUMN source_id integer')
      Point.reset_column_information
    end
    Points::DimensionResolver.instance_variable_set(:@columns_available, nil)
  end

  it 'stores a new point and an updated resend' do
    post api_v1_points_url(api_key: user.api_key), params: payload(35), as: :json
    expect(response).to have_http_status(:ok)

    post api_v1_points_url(api_key: user.api_key), params: payload(36), as: :json
    expect(response).to have_http_status(:ok)

    expect(user.points.pluck(:altitude)).to eq([36])
    expect(connection.select_value("SELECT revision FROM achievement_collection_states WHERE user_id=#{user.id}"))
      .to eq(2)
  end
end

# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Authoritative tracker transportation mode', type: :request do
  let(:user) { create(:user) }
  let(:start_at) { Time.zone.parse('2026-10-13 12:00:00 UTC') }
  let(:track) do
    create(:track, user: user, start_at: start_at, end_at: start_at + 20.minutes,
                   original_path: 'LINESTRING(-140 -30, -140 -30)',
                   distance: 0, avg_speed: 0, duration: 1200)
  end

  def classify_stopped_vehicle(authoritative: false)
    locations = (0..240).map do |i|
      properties = {
        timestamp: (start_at + i * 5).iso8601, speed: 0, horizontal_accuracy: 5,
        device_id: 'synthetic-tracker', motion: ['driving']
      }
      properties[:motion_authoritative] = true if authoritative
      { type: 'Feature', geometry: { type: 'Point', coordinates: [-140.0, -30.0] }, properties: properties }
    end

    post "/api/v1/points?api_key=#{user.api_key}", params: { locations: locations }, as: :json
    expect(response).to have_http_status(:ok)
    expect(user.points.count).to eq(241)
    expect(user.points.first.motion_data).to include('motion' => ['driving'])
    expect(user.points.first.raw_data.dig('properties', 'motion_authoritative')).to be(true) if authoritative

    user.points.update_all(track_id: track.id)
    TransportationModes::Detector.new(track, fallback: false).call
  end

  it 'keeps ordinary motion values as hints when the vehicle is stopped' do
    segments = classify_stopped_vehicle

    expect(segments.map { |segment| segment[:mode] }).to eq([:stationary])
  end

  # motion_authoritative is the proposed opt-in from the feature request,
  # not an existing API guarantee. This example records the requested behavior.
  it 'preserves an authoritative driving mode throughout a twenty-minute stop' do
    segments = classify_stopped_vehicle(authoritative: true)

    expect(segments.map { |segment| segment[:mode] }).to eq([:driving])
    expect(segments.first[:start_at]).to eq(start_at)
    expect(segments.last[:end_at]).to eq(start_at + 20.minutes)
  end
end

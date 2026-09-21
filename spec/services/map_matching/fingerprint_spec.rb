# frozen_string_literal: true

require 'rails_helper'

RSpec.describe MapMatching::Fingerprint do
  let(:user) { create(:user) }
  let(:track) do
    create(:track, user:, start_at: Time.zone.at(100), end_at: Time.zone.at(110),
                   original_path: 'LINESTRING(13.4 52.5, 13.41 52.51)')
  end
  let!(:first_point) do
    create(:point, user:, track:, timestamp: 100, longitude: 13.4, latitude: 52.5, accuracy: 5)
  end
  let!(:second_point) do
    create(:point, user:, track:, timestamp: 110, longitude: 13.41, latitude: 52.51, accuracy: 6)
  end
  let!(:segment) do
    create(:track_segment, :anchored, track:, transportation_mode: :walking,
                                      start_at: Time.zone.at(100), end_at: Time.zone.at(110))
  end

  def digest
    described_class.call(MapMatching::Input.new(track.reload))
  end

  it 'is deterministic for the same logical Atlas input' do
    expect(digest).to eq(digest)
  end

  it 'changes with point coordinates, timestamps, accuracy, boundaries, or mode' do
    original = digest

    first_point.update!(accuracy: 9)
    expect(digest).not_to eq(original)
    accuracy_digest = digest

    second_point.update!(timestamp: 111)
    expect(digest).not_to eq(accuracy_digest)
    time_digest = digest

    first_point.update!(lonlat: 'POINT(13.401 52.5)')
    expect(digest).not_to eq(time_digest)
    coordinate_digest = digest

    segment.update!(end_at: Time.zone.at(111))
    expect(digest).not_to eq(coordinate_digest)
    boundary_digest = digest

    segment.update!(transportation_mode: :cycling)
    expect(digest).not_to eq(boundary_digest)
  end
end

# frozen_string_literal: true

require 'rails_helper'

RSpec.describe MapMatching::Input do
  let(:user) { create(:user) }
  let(:track) do
    create(:track, user:, start_at: Time.zone.at(100), end_at: Time.zone.at(130),
                   original_path: 'LINESTRING(13.4 52.5, 13.43 52.53)')
  end

  before do
    [[100, 13.40, 52.50], [110, 13.41, 52.51], [120, 13.42, 52.52], [130, 13.43, 52.53]].each do |time, lon, lat|
      create(:point, user:, track:, timestamp: time, longitude: lon, latitude: lat, accuracy: 5)
    end
  end

  it 'covers the full path with eligible and original fallback portions' do
    create(:track_segment, :anchored, track:, transportation_mode: :walking,
                                      start_at: Time.zone.at(100), end_at: Time.zone.at(120))
    create(:track_segment, :anchored, :train, track:,
                                              start_at: Time.zone.at(120), end_at: Time.zone.at(130))

    input = described_class.new(track)

    expect(input.portions.map(&:atlas_mode)).to eq(%w[pedestrian] + [nil])
    expect(input.portions.map { |portion| portion.points.map(&:timestamp) })
      .to eq([[100, 110, 120], [120, 130]])
    expect(input.portions.flat_map(&:original_coordinates).first).to eq([13.4, 52.5])
  end

  it 'creates an original fallback for an uncovered edge' do
    create(:track_segment, :anchored, track:, transportation_mode: :cycling,
                                      start_at: Time.zone.at(100), end_at: Time.zone.at(110))
    create(:track_segment, :anchored, track:, transportation_mode: :driving,
                                      start_at: Time.zone.at(120), end_at: Time.zone.at(130))

    input = described_class.new(track)

    expect(input.portions.map(&:atlas_mode)).to eq(['bicycle', nil, 'auto'])
    expect(input.portions.map { |portion| [portion.start_index, portion.end_index] })
      .to eq([[0, 1], [1, 2], [2, 3]])
  end

  it 'ignores anomalous points' do
    track.points.find_by(timestamp: 110).update!(anomaly: true)

    expect(described_class.new(track).points.map(&:timestamp)).to eq([100, 120, 130])
  end
end

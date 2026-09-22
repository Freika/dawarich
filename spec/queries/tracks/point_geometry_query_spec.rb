# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Tracks::PointGeometryQuery do
  let(:user) { create(:user) }
  let(:track) { create(:track, user:) }
  let(:selected_import) { create(:import, user:) }
  let(:other_import) { create(:import, user:) }

  def add_point(longitude, point_import, timestamp)
    create(:point, user:, track:, import: point_import, longitude:, latitude: 0.001, timestamp:)
  end

  it 'returns only the geometry and times of contiguous selected-import runs' do
    add_point(0.001, selected_import, 100)
    add_point(0.002, selected_import, 110)
    add_point(0.003, other_import, 120)
    add_point(0.004, selected_import, 130)
    add_point(0.005, selected_import, 140)

    summary = described_class.new(points_scope: user.points, import_id: selected_import.id)
                             .summary_for(track_id: track.id)

    expect(summary[:geometry]).to eq(
      type: 'MultiLineString', coordinates: [
        [[0.001, 0.001], [0.002, 0.001]], [[0.004, 0.001], [0.005, 0.001]]
      ]
    )
    expect(summary).to include(start_timestamp: 100, end_timestamp: 140)
    expect(summary[:distance]).to be_positive
  end

  it 'returns no line for a lone Point in the selected import' do
    add_point(0.001, selected_import, 100)
    add_point(0.002, other_import, 110)

    summary = described_class.new(points_scope: user.points, import_id: selected_import.id)
                             .summary_for(track_id: track.id)

    expect(summary).to be_nil
  end
end

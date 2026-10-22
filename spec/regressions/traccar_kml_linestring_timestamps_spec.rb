# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Traccar KML LineString timestamps' do
  it 'imports points across the named time range' do
    user = create(:user)
    import = create(:import, user:, name: 'traccar.kml', source: 'kml')
    file_path = Rails.root.join('spec/fixtures/files/kml/traccar_linestring.kml').to_s

    expect { Kml::Importer.new(import, user.id, file_path).call }.to change(Point, :count).by(3)

    expected_timestamps = [
      Time.zone.parse('2026-05-23 16:55').to_i,
      Time.zone.parse('2026-05-23 16:56').to_i,
      Time.zone.parse('2026-05-23 16:57').to_i
    ]

    expect(user.points.order(:timestamp).pluck(:timestamp)).to eq(expected_timestamps)
  end
end

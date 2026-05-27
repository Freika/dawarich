# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'GPX with both <trk> and <wpt> imports tracks as Points and waypoints as Places' do
  subject(:run_import) { Gpx::TrackImporter.new(import, user.id).call }

  let(:user) { create(:user) }
  let(:file_path) { Rails.root.join('spec/fixtures/files/gpx/gpx_mixed_track_and_waypoints.gpx') }
  let(:file) { Rack::Test::UploadedFile.new(file_path, 'application/xml') }
  let(:import) { create(:import, user:, name: 'mixed.gpx', source: 'gpx') }

  before { import.file.attach(file) }

  it 'creates Points for the trkpts' do
    expect { run_import }.to change { Point.count }.by(3)
  end

  it 'creates Places for the waypoints with source :gpx_waypoint' do
    expect { run_import }.to change { Place.where(user: user, source: :gpx_waypoint).count }.by(2)
    expect(Place.where(user: user).pluck(:name)).to contain_exactly('Start Marker', 'End Marker')
  end

  it 'does not raise even though waypoints have no timestamps' do
    expect { run_import }.not_to raise_error
  end
end

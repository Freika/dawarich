# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'GPX waypoints (<wpt>) imported as Places' do
  subject(:run_import) { Gpx::TrackImporter.new(import, user.id).call }

  let(:user) { create(:user) }
  let(:file_path) { Rails.root.join('spec/fixtures/files/gpx/gpx_waypoints_only.gpx') }
  let(:file) { Rack::Test::UploadedFile.new(file_path, 'application/xml') }
  let(:import) { create(:import, user:, name: 'favourites.gpx', source: 'gpx') }

  before { import.file.attach(file) }

  it 'creates one Place per <wpt> with source :gpx_waypoint' do
    expect { run_import }.to change {
      user.reload
      Place.where(user: user).count
    }.by(3)

    places = Place.where(user: user, source: :gpx_waypoint)
    expect(places.count).to eq(3)
    expect(places.pluck(:name)).to contain_exactly('Brandenburg Gate', 'Eiffel Tower', 'Imported waypoint')
  end

  it 'creates no Points (waypoints have no timestamps and do not belong on the timeline)' do
    expect { run_import }.not_to(change { Point.count })
  end

  it 'persists coordinates from lat/lon attributes' do
    run_import

    brandenburg = Place.find_by(user: user, name: 'Brandenburg Gate')
    expect(brandenburg.longitude.to_f).to be_within(0.000001).of(13.404954)
    expect(brandenburg.latitude.to_f).to be_within(0.000001).of(52.520008)
  end
end

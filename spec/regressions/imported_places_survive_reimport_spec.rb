# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Re-importing a waypoint file' do
  let(:user) { create(:user) }
  let(:file_path) { Rails.root.join('spec/fixtures/files/gpx/gpx_waypoints_only.gpx') }

  def run_import(name)
    import = create(:import, user:, name:, source: 'gpx')
    import.file.attach(Rack::Test::UploadedFile.new(file_path, 'application/xml'))
    Gpx::TrackImporter.new(import, user.id).call
    import
  end

  it 'does not duplicate places that were already imported' do
    run_import('favourites.gpx')

    expect { run_import('favourites-again.gpx') }.not_to(change { Place.where(user: user).count })
  end

  it 'does not report the file as timestampless when every waypoint already exists' do
    run_import('favourites.gpx')

    expect { run_import('favourites-again.gpx') }.not_to raise_error
  end

  it 'shows imported places on the map without needing a tag or a confirmed visit' do
    run_import('favourites.gpx')

    expect(Place.map_visible(user).pluck(:name)).to include('Brandenburg Gate', 'Eiffel Tower')
  end

  it 'locks imported names so nightly reverse geocoding cannot rename them' do
    run_import('favourites.gpx')

    place = Place.find_by(user: user, name: 'Brandenburg Gate')
    expect(place).to be_name_locked
  end

  it 'names a waypoint that carries no name' do
    run_import('favourites.gpx')

    expect(Place.where(user: user).pluck(:name)).to include(Places::GpxWaypointImporter::DEFAULT_NAME)
  end

  it 'hands ownership to the newest import so deleting an older one keeps the places' do
    first = run_import('favourites.gpx')
    run_import('favourites-again.gpx')

    expect { first.destroy! }.not_to(change { Place.where(user: user).count })
  end

  it 'still reports the places when every waypoint already existed' do
    run_import('favourites.gpx')
    second = create(:import, user:, name: 'favourites-again.gpx', source: 'gpx')
    second.file.attach(Rack::Test::UploadedFile.new(file_path, 'application/xml'))

    Imports::Create.new(user, second).call

    expect(second.reload.places.count).to eq(3)
  end
end

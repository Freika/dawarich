# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Imported places belong to their import' do
  let(:user) { create(:user) }
  let(:file_path) { Rails.root.join('spec/fixtures/files/gpx/gpx_waypoints_only.gpx') }
  let(:import) { create(:import, user:, name: 'favourites.gpx', source: 'gpx') }

  before do
    import.file.attach(Rack::Test::UploadedFile.new(file_path, 'application/xml'))
    Imports::Create.new(user, import).call
  end

  it 'records which import created each place' do
    expect(Place.where(user: user).pluck(:import_id).uniq).to eq([import.id])
  end

  it 'removes the places when the import is deleted' do
    expect { import.destroy! }.to change { Place.where(user: user).count }.from(3).to(0)
  end

  it 'tells the user where the untimed locations went, since the points count stays zero' do
    expect(import.reload.points.count).to eq(0)
    expect(Notification.where(user_id: user.id).pluck(:title)).to include('Places imported')
  end
end

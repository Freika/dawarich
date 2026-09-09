# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'A GPX holding no waypoints does not offer extraction', type: :request do
  let(:user) { create(:user) }

  before { sign_in user }

  def gpx_import(raw_data)
    create(:import, user: user, source: :gpx, name: "track-#{SecureRandom.hex(4)}.gpx", raw_data: raw_data)
  end

  it 'explains why instead of showing a trigger that can only find nothing' do
    import = gpx_import('trackpoints_seen' => 40)

    get import_path(import)

    expect(response.body).to include('no waypoints to import as places')
    expect(response.body).not_to include("extraction-dialog-#{import.id}")
  end

  it 'still offers the trigger when the file holds waypoints' do
    import = gpx_import('trackpoints_seen' => 40, 'waypoints_seen' => 2)

    get import_path(import)

    expect(response.body).to include("extraction-dialog-#{import.id}")
  end

  it 'refuses a hand-rolled extraction request for it' do
    import = gpx_import('trackpoints_seen' => 40)

    expect(Imports::ExtractionPolicy.new(user, import).create?).to be false
  end
end

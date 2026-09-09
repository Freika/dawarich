# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'An imported waypoint never widens a privacy zone' do
  let(:user) { create(:user) }
  let(:import) do
    filename = 'gpx_waypoints_only.gpx'
    path = Rails.root.join('spec/fixtures/files/gpx', filename)
    record = create(:import, user: user, source: :gpx, name: filename)
    record.file.attach(io: File.open(path), filename: filename, content_type: 'application/gpx+xml')
    record
  end

  context 'when the user already has a privacy tag whose name matches a waypoint category' do
    before { create(:tag, user: user, name: 'Food', privacy_radius_meters: 500) }

    it 'still imports the waypoint as a place' do
      EnhancedImport::ExtractJob.new.perform(import.id)

      expect(Place.find_by(name: 'Cafe Riquet')).to be_present
    end

    it 'leaves that place untagged so the privacy zone does not grow' do
      EnhancedImport::ExtractJob.new.perform(import.id)

      expect(Place.find_by(name: 'Cafe Riquet').tag_names).to be_empty
    end

    it 'adds no new redaction circles to shared links' do
      expect { EnhancedImport::ExtractJob.new.perform(import.id) }
        .not_to(change { Users::PrivacyZones.new(user).call.length })
    end
  end

  context 'when the matching tag carries no privacy radius' do
    before { create(:tag, user: user, name: 'Food') }

    it 'tags the place as normal' do
      EnhancedImport::ExtractJob.new.perform(import.id)

      expect(Place.find_by(name: 'Cafe Riquet').tag_names).to eq(['Food'])
    end
  end
end

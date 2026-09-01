# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'GPX waypoints are imported as places, never as timeline points' do
  let(:user) { create(:user) }

  def build_import(filename)
    path = Rails.root.join('spec/fixtures/files/gpx', filename)
    import = create(:import, user: user, source: :gpx, name: filename)
    import.file.attach(
      io: File.open(path),
      filename: filename,
      content_type: 'application/gpx+xml'
    )
    import
  end

  describe 'a favourites file holding only waypoints' do
    let(:import) { build_import('gpx_waypoints_only.gpx') }

    it 'creates one place per waypoint and no points' do
      expect { EnhancedImport::ExtractJob.new.perform(import.id) }
        .to change { Place.where(user_id: user.id).count }.by(3)

      expect(Point.where(user_id: user.id).count).to eq(0)
    end

    it 'records the waypoint origin on each place' do
      EnhancedImport::ExtractJob.new.perform(import.id)

      expect(Place.where(user_id: user.id).pluck(:source).uniq).to eq(['gpx_waypoint'])
    end

    it 'attributes the places to the import that produced them' do
      EnhancedImport::ExtractJob.new.perform(import.id)

      expect(Place.where(user_id: user.id).pluck(:import_id).uniq).to eq([import.id])
    end

    it 'keeps the waypoint name and coordinates' do
      EnhancedImport::ExtractJob.new.perform(import.id)
      place = Place.find_by(name: 'Augustusplatz')

      expect(place.latitude.to_f).to be_within(0.00001).of(51.3397)
      expect(place.longitude.to_f).to be_within(0.00001).of(12.3731)
    end

    it 'reports the places it created' do
      EnhancedImport::ExtractJob.new.perform(import.id)

      expect(import.reload.extraction_counts[:places]).to eq(3)
    end
  end

  describe 'waypoint categories' do
    let(:import) { build_import('gpx_waypoints_only.gpx') }

    it 'turns each category into a tag on the place' do
      EnhancedImport::ExtractJob.new.perform(import.id)

      expect(Place.find_by(name: 'Cafe Riquet').tag_names).to eq(['Food'])
    end

    it 'reuses a tag the user already had rather than duplicating it' do
      existing = create(:tag, user: user, name: 'Food')

      EnhancedImport::ExtractJob.new.perform(import.id)

      expect(user.tags.where(name: 'Food').count).to eq(1)
      expect(Place.find_by(name: 'Cafe Riquet').tags).to eq([existing])
    end

    it 'takes the tag colour from the waypoint, dropping the leading alpha channel' do
      EnhancedImport::ExtractJob.new.perform(import.id)

      expect(user.tags.find_by(name: 'Transport').color).to eq('#eecc22')
    end

    it 'keeps a six digit colour as it is' do
      EnhancedImport::ExtractJob.new.perform(import.id)

      expect(user.tags.find_by(name: 'Sights').color).to eq('#10c0f0')
    end

    it 'never repaints a tag the user already styled' do
      create(:tag, user: user, name: 'Transport', color: '#123456')

      EnhancedImport::ExtractJob.new.perform(import.id)

      expect(user.tags.find_by(name: 'Transport').color).to eq('#123456')
    end
  end

  describe 'a waypoint with no category' do
    let(:import) { build_import('gpx_waypoints_uncategorised.gpx') }

    it 'still becomes a place, just without a tag' do
      EnhancedImport::ExtractJob.new.perform(import.id)
      place = Place.find_by(name: 'Nameless corner')

      expect(place).to be_present
      expect(place.tag_names).to be_empty
    end
  end

  describe 'a file holding both a track and waypoints' do
    let(:import) { build_import('gpx_mixed_track_and_waypoints.gpx') }

    it 'imports the trackpoints as points and the waypoints as places' do
      Gpx::TrackImporter.new(import, user.id).call
      EnhancedImport::ExtractJob.new.perform(import.id)

      expect(Point.where(user_id: user.id).count).to eq(3)
      expect(Place.where(user_id: user.id).count).to eq(2)
    end
  end
end

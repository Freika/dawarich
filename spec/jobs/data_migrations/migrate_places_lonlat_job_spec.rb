# frozen_string_literal: true

require 'rails_helper'

RSpec.describe DataMigrations::MigratePlacesLonlatJob, type: :job do
  describe '#perform' do
    let(:user) { create(:user) }

    context 'when places exist for the user' do
      let!(:place1) { create(:place, :without_lonlat, longitude: 10.0, latitude: 20.0) }
      let!(:place2) { create(:place, :without_lonlat, longitude: -73.935242, latitude: 40.730610) }
      let!(:other_place) { create(:place, :without_lonlat, longitude: 15.0, latitude: 25.0) }

      # Create visits to associate places with users
      let!(:visit1) { create(:visit, user: user, place: place1) }
      let!(:visit2) { create(:visit, user: user, place: place2) }
      let!(:other_visit) { create(:visit, place: other_place) } # associated with a different user

      it 'updates lonlat field for all places belonging to the user' do
        # Force a reload to ensure we have the initial state
        place1.reload
        place2.reload

        # Both places should have nil lonlat initially
        expect(place1.lonlat).to be_nil
        expect(place2.lonlat).to be_nil

        # Run the job
        described_class.perform_now(user.id)

        # Reload to get updated state
        place1.reload
        place2.reload
        other_place.reload

        # Check that lonlat is now set correctly
        expect(place1.lonlat).not_to be_nil
        expect(place2.lonlat).not_to be_nil

        # The other user's place should still have nil lonlat
        expect(other_place.lonlat).to be_nil

        # Verify the coordinates
        expect(place1.lonlat.x).to eq(10.0) # longitude
        expect(place1.lonlat.y).to eq(20.0) # latitude

        expect(place2.lonlat.x).to eq(-73.935242) # longitude
        expect(place2.lonlat.y).to eq(40.730610) # latitude
      end

      it 'sets the correct SRID (4326) on the geometry' do
        described_class.perform_now(user.id)
        place1.reload

        expect(place1.lonlat.srid).to eq(4326)
      end
    end

    context 'when no places exist for the user' do
      it 'completes successfully without errors' do
        expect do
          described_class.perform_now(user.id)
        end.not_to raise_error
      end
    end
  end

  describe 'queue' do
    it 'uses the default queue' do
      expect(described_class.queue_name).to eq('default')
    end
  end
end

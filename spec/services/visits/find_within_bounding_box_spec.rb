# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Visits::FindWithinBoundingBox do
  let(:user) { create(:user) }
  let(:other_user) { create(:user) }

  # Define a bounding box for testing
  # This creates a box around central Paris
  let(:sw_lat) { 48.8534 }  # Southwest latitude
  let(:sw_lng) { 2.3380 }   # Southwest longitude
  let(:ne_lat) { 48.8667 }  # Northeast latitude
  let(:ne_lng) { 2.3580 }   # Northeast longitude

  # Create places inside the bounding box
  let!(:place_inside_1) do
    create(:place, latitude: 48.8600, longitude: 2.3500) # Inside the bounding box
  end

  let!(:place_inside_2) do
    create(:place, latitude: 48.8580, longitude: 2.3450) # Inside the bounding box
  end

  # Create places outside the bounding box
  let!(:place_outside_1) do
    create(:place, latitude: 48.8700, longitude: 2.3600) # North of the bounding box
  end

  let!(:place_outside_2) do
    create(:place, latitude: 48.8500, longitude: 2.3300) # Southwest of the bounding box
  end

  # Create visits for the test user
  let!(:visit_inside_1) do
    create(
      :visit,
      user: user,
      place: place_inside_1,
      started_at: 2.hours.ago,
      ended_at: 1.hour.ago
    )
  end

  let!(:visit_inside_2) do
    create(
      :visit,
      user: user,
      place: place_inside_2,
      started_at: 4.hours.ago,
      ended_at: 3.hours.ago
    )
  end

  let!(:visit_outside_1) do
    create(
      :visit,
      user: user,
      place: place_outside_1,
      started_at: 6.hours.ago,
      ended_at: 5.hours.ago
    )
  end

  let!(:visit_outside_2) do
    create(
      :visit,
      user: user,
      place: place_outside_2,
      started_at: 8.hours.ago,
      ended_at: 7.hours.ago
    )
  end

  # Create a visit for another user inside the bounding box
  let!(:other_user_visit_inside) do
    create(
      :visit,
      user: other_user,
      place: place_inside_1,
      started_at: 3.hours.ago,
      ended_at: 2.hours.ago
    )
  end

  describe '#call' do
    let(:params) do
      {
        sw_lat: sw_lat.to_s,
        sw_lng: sw_lng.to_s,
        ne_lat: ne_lat.to_s,
        ne_lng: ne_lng.to_s
      }
    end

    subject(:result) { described_class.new(user, params).call }

    it 'returns visits within the specified bounding box' do
      expect(result).to include(visit_inside_1, visit_inside_2)
      expect(result).not_to include(visit_outside_1, visit_outside_2)
    end

    it 'returns visits in descending order by started_at' do
      expect(result.to_a).to eq([visit_inside_1, visit_inside_2])
    end

    it 'does not include visits from other users' do
      expect(result).not_to include(other_user_visit_inside)
    end

    it 'preloads the place association' do
      expect(result.first.association(:place)).to be_loaded
    end

    context 'with an empty bounding box' do
      let(:params) do
        {
          sw_lat: '0',
          sw_lng: '0',
          ne_lat: '0',
          ne_lng: '0'
        }
      end

      it 'returns an empty collection' do
        expect(result).to be_empty
      end
    end

    context 'with a very large bounding box' do
      let(:params) do
        {
          sw_lat: '-90',
          sw_lng: '-180',
          ne_lat: '90',
          ne_lng: '180'
        }
      end

      it 'returns all visits for the user' do
        expect(result).to include(visit_inside_1, visit_inside_2, visit_outside_1, visit_outside_2)
        expect(result).not_to include(other_user_visit_inside)
      end
    end

    context 'with string coordinates' do
      let(:params) do
        {
          sw_lat: sw_lat.to_s,
          sw_lng: sw_lng.to_s,
          ne_lat: ne_lat.to_s,
          ne_lng: ne_lng.to_s
        }
      end

      it 'converts strings to floats' do
        expect(result).to include(visit_inside_1, visit_inside_2)
      end
    end
  end
end

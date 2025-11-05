# frozen_string_literal: true

require 'rails_helper'

RSpec.describe TripPolicy, type: :policy do
  let(:user) { create(:user) }
  let(:other_user) { create(:user, email: 'other@example.com') }
  let(:trip) { create(:trip, user: user, name: 'My Trip') }
  let(:other_trip) { create(:trip, user: other_user, name: 'Other Trip') }

  describe 'show?' do
    it 'allows users to view their own trips' do
      policy = TripPolicy.new(user, trip)

      expect(policy).to permit(:show)
    end

    it 'denies users from viewing other users trips by default' do
      policy = TripPolicy.new(user, other_trip)

      expect(policy).not_to permit(:show)
    end

    it 'allows anyone to view publicly shared trips' do
      other_trip.enable_sharing!(expiration: '24h')
      policy = TripPolicy.new(user, other_trip)

      expect(policy).to permit(:show)
    end

    it 'allows unauthenticated users to view publicly shared trips' do
      trip.enable_sharing!(expiration: '24h')
      policy = TripPolicy.new(nil, trip)

      expect(policy).to permit(:show)
    end

    it 'denies access to expired shared trips' do
      other_trip.update!(sharing_settings: {
                           'enabled' => true,
                           'expiration' => '1h',
                           'expires_at' => 2.hours.ago.iso8601
                         })
      policy = TripPolicy.new(user, other_trip)

      expect(policy).not_to permit(:show)
    end

    it 'denies unauthenticated users from viewing private trips' do
      policy = TripPolicy.new(nil, trip)

      expect(policy).not_to permit(:show)
    end
  end

  describe 'create?' do
    it 'allows authenticated users to create trips' do
      policy = TripPolicy.new(user, Trip.new)

      expect(policy).to permit(:create)
    end

    it 'denies unauthenticated users from creating trips' do
      policy = TripPolicy.new(nil, Trip.new)

      expect(policy).not_to permit(:create)
    end
  end

  describe 'update?' do
    it 'allows users to update their own trips' do
      policy = TripPolicy.new(user, trip)

      expect(policy).to permit(:update)
    end

    it 'denies users from updating other users trips' do
      policy = TripPolicy.new(user, other_trip)

      expect(policy).not_to permit(:update)
    end

    it 'denies unauthenticated users from updating trips' do
      policy = TripPolicy.new(nil, trip)

      expect(policy).not_to permit(:update)
    end
  end

  describe 'destroy?' do
    it 'allows users to destroy their own trips' do
      policy = TripPolicy.new(user, trip)

      expect(policy).to permit(:destroy)
    end

    it 'denies users from destroying other users trips' do
      policy = TripPolicy.new(user, other_trip)

      expect(policy).not_to permit(:destroy)
    end

    it 'denies unauthenticated users from destroying trips' do
      policy = TripPolicy.new(nil, trip)

      expect(policy).not_to permit(:destroy)
    end
  end

  describe 'update_sharing?' do
    it 'allows users to update sharing settings for their own trips' do
      policy = TripPolicy.new(user, trip)

      expect(policy).to permit(:update_sharing)
    end

    it 'denies users from updating sharing settings for other users trips' do
      policy = TripPolicy.new(user, other_trip)

      expect(policy).not_to permit(:update_sharing)
    end

    it 'denies unauthenticated users from updating sharing settings' do
      policy = TripPolicy.new(nil, trip)

      expect(policy).not_to permit(:update_sharing)
    end
  end

  describe 'Scope' do
    let!(:user_trip1) { create(:trip, user: user, name: 'Trip 1') }
    let!(:user_trip2) { create(:trip, user: user, name: 'Trip 2') }
    let!(:other_user_trip) { create(:trip, user: other_user, name: 'Other Trip') }

    it 'returns only the users trips' do
      scope = TripPolicy::Scope.new(user, Trip).resolve

      expect(scope).to contain_exactly(user_trip1, user_trip2)
      expect(scope).not_to include(other_user_trip)
    end

    it 'returns no trips for unauthenticated users' do
      scope = TripPolicy::Scope.new(nil, Trip).resolve

      expect(scope).to be_empty
    end
  end
end

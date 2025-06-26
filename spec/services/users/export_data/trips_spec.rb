# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Users::ExportData::Trips, type: :service do
  let(:user) { create(:user) }
  let(:service) { described_class.new(user) }

  subject { service.call }

  describe '#call' do
    context 'when user has no trips' do
      it 'returns an empty array' do
        expect(subject).to eq([])
      end
    end

    context 'when user has trips' do
      let!(:trip1) { create(:trip, user: user, name: 'Business Trip', distance: 500) }
      let!(:trip2) { create(:trip, user: user, name: 'Vacation', distance: 1200) }

      it 'returns all user trips' do
        expect(subject).to be_an(Array)
        expect(subject.size).to eq(2)
      end

      it 'excludes user_id and id fields' do
        subject.each do |trip_data|
          expect(trip_data).not_to have_key('user_id')
          expect(trip_data).not_to have_key('id')
        end
      end

      it 'includes expected trip attributes' do
        trip_data = subject.find { |t| t['name'] == 'Business Trip' }

        expect(trip_data).to include(
          'name' => 'Business Trip',
          'distance' => 500
        )
        expect(trip_data).to have_key('created_at')
        expect(trip_data).to have_key('updated_at')
      end
    end

    context 'with multiple users' do
      let(:other_user) { create(:user) }
      let!(:user_trip) { create(:trip, user: user, name: 'User Trip') }
      let!(:other_user_trip) { create(:trip, user: other_user, name: 'Other Trip') }

      subject { service.call }

      it 'only returns trips for the specified user' do
        expect(service.call.size).to eq(1)
        expect(service.call.first['name']).to eq('User Trip')
      end
    end
  end
end

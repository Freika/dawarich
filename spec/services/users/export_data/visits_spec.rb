# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Users::ExportData::Visits, type: :service do
  let(:user) { create(:user) }
  let(:service) { described_class.new(user) }

  subject { service.call }

  describe '#call' do
    context 'when user has no visits' do
      it 'returns an empty array' do
        expect(subject).to eq([])
      end
    end

    context 'when user has visits with places' do
      let(:place) { create(:place, name: 'Office Building', longitude: -73.9851, latitude: 40.7589, source: :manual) }
      let!(:visit_with_place) do
        create(:visit,
          user: user,
          place: place,
          name: 'Work Visit',
          started_at: Time.zone.parse('2024-01-01 08:00:00'),
          ended_at: Time.zone.parse('2024-01-01 17:00:00'),
          duration: 32400,
          status: :suggested
        )
      end

      it 'returns visits with place references' do
        expect(subject).to be_an(Array)
        expect(subject.size).to eq(1)
      end

      it 'excludes user_id, place_id, and id fields' do
        visit_data = subject.first

        expect(visit_data).not_to have_key('user_id')
        expect(visit_data).not_to have_key('place_id')
        expect(visit_data).not_to have_key('id')
      end

      it 'includes visit attributes and place reference' do
        visit_data = subject.first

        expect(visit_data).to include(
          'name' => 'Work Visit',
          'started_at' => visit_with_place.started_at,
          'ended_at' => visit_with_place.ended_at,
          'duration' => 32400,
          'status' => 'suggested'
        )

        expect(visit_data['place_reference']).to eq({
          'name' => 'Office Building',
          'latitude' => '40.7589',
          'longitude' => '-73.9851',
          'source' => 'manual'
        })
      end

      it 'includes created_at and updated_at timestamps' do
        visit_data = subject.first

        expect(visit_data).to have_key('created_at')
        expect(visit_data).to have_key('updated_at')
      end
    end

    context 'when user has visits without places' do
      let!(:visit_without_place) do
        create(:visit,
          user: user,
          place: nil,
          name: 'Unknown Location',
          started_at: Time.zone.parse('2024-01-02 10:00:00'),
          ended_at: Time.zone.parse('2024-01-02 12:00:00'),
          duration: 7200,
          status: :confirmed
        )
      end

      it 'returns visits with null place references' do
        visit_data = subject.first

        expect(visit_data).to include(
          'name' => 'Unknown Location',
          'duration' => 7200,
          'status' => 'confirmed'
        )
        expect(visit_data['place_reference']).to be_nil
      end
    end

    context 'with mixed visits (with and without places)' do
      let(:place) { create(:place, name: 'Gym', longitude: -74.006, latitude: 40.7128) }
      let!(:visit_with_place) { create(:visit, user: user, place: place, name: 'Workout') }
      let!(:visit_without_place) { create(:visit, user: user, place: nil, name: 'Random Stop') }

      it 'returns all visits with appropriate place references' do
        expect(subject.size).to eq(2)

        visit_with_place_data = subject.find { |v| v['name'] == 'Workout' }
        visit_without_place_data = subject.find { |v| v['name'] == 'Random Stop' }

        expect(visit_with_place_data['place_reference']).to be_present
        expect(visit_without_place_data['place_reference']).to be_nil
      end
    end

    context 'with multiple users' do
      let(:other_user) { create(:user) }
      let!(:user_visit) { create(:visit, user: user, name: 'User Visit') }
      let!(:other_user_visit) { create(:visit, user: other_user, name: 'Other User Visit') }

      it 'only returns visits for the specified user' do
        expect(subject.size).to eq(1)
        expect(subject.first['name']).to eq('User Visit')
      end
    end

    context 'performance considerations' do
      let!(:place) { create(:place) }

      it 'includes places to avoid N+1 queries' do
        create_list(:visit, 3, user: user, place: place)

        # This test verifies that we're using .includes(:place)
        expect(user.visits).to receive(:includes).with(:place).and_call_original

        subject
      end
    end
  end
end

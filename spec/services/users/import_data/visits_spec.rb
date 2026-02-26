# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Users::ImportData::Visits, type: :service do
  let(:user) { create(:user) }

  describe '#call' do
    context 'when visits_data is not an array' do
      it 'returns 0 for nil' do
        service = described_class.new(user, nil)
        expect(service.call).to eq(0)
      end

      it 'returns 0 for a hash' do
        service = described_class.new(user, { 'name' => 'test' })
        expect(service.call).to eq(0)
      end
    end

    context 'when visits_data is empty' do
      it 'returns 0' do
        service = described_class.new(user, [])
        expect(service.call).to eq(0)
      end
    end

    context 'with valid visits data' do
      let(:visits_data) do
        [
          {
            'name' => 'Work Visit',
            'started_at' => '2024-01-01T09:00:00Z',
            'ended_at' => '2024-01-01T17:00:00Z',
            'duration' => 28_800,
            'status' => 'confirmed'
          },
          {
            'name' => 'Home Visit',
            'started_at' => '2024-01-01T18:00:00Z',
            'ended_at' => '2024-01-01T22:00:00Z',
            'duration' => 14_400,
            'status' => 'suggested'
          }
        ]
      end

      it 'creates the visits' do
        service = described_class.new(user, visits_data)

        expect { service.call }.to change { user.visits.count }.by(2)
      end

      it 'returns the count of created visits' do
        service = described_class.new(user, visits_data)

        expect(service.call).to eq(2)
      end

      it 'sets the correct attributes' do
        service = described_class.new(user, visits_data)
        service.call

        visit = user.visits.find_by(name: 'Work Visit')
        expect(visit).to be_present
        expect(visit.duration).to eq(28_800)
        expect(visit.status).to eq('confirmed')
      end
    end

    context 'with place_reference' do
      let(:visits_data) do
        [
          {
            'name' => 'Office Visit',
            'started_at' => '2024-01-01T09:00:00Z',
            'ended_at' => '2024-01-01T17:00:00Z',
            'duration' => 28_800,
            'status' => 'confirmed',
            'place_reference' => {
              'name' => 'Office Building',
              'latitude' => '40.7589',
              'longitude' => '-73.9851',
              'source' => 'manual'
            }
          }
        ]
      end

      context 'when place does not exist' do
        it 'creates the place and associates it' do
          service = described_class.new(user, visits_data)

          expect { service.call }.to change { Place.count }.by(1)

          visit = user.visits.find_by(name: 'Office Visit')
          expect(visit.place).to be_present
          expect(visit.place.name).to eq('Office Building')
        end
      end

      context 'when place already exists with exact coordinates' do
        let!(:existing_place) do
          create(:place, name: 'Office Building', latitude: 40.7589, longitude: -73.9851)
        end

        it 'uses the existing place' do
          service = described_class.new(user, visits_data)

          expect { service.call }.not_to(change { Place.count })

          visit = user.visits.find_by(name: 'Office Visit')
          expect(visit.place).to eq(existing_place)
        end
      end

      context 'when place exists with nearby coordinates' do
        let!(:nearby_place) do
          create(:place, name: 'Different Name', latitude: 40.75895, longitude: -73.98515)
        end

        it 'uses the nearby place' do
          service = described_class.new(user, visits_data)

          expect { service.call }.not_to(change { Place.count })

          visit = user.visits.find_by(name: 'Office Visit')
          expect(visit.place).to eq(nearby_place)
        end
      end
    end

    context 'with nil place_reference' do
      let(:visits_data) do
        [
          {
            'name' => 'Unknown Visit',
            'started_at' => '2024-01-01T09:00:00Z',
            'ended_at' => '2024-01-01T17:00:00Z',
            'duration' => 28_800,
            'status' => 'suggested',
            'place_reference' => nil
          }
        ]
      end

      it 'creates the visit without a place' do
        service = described_class.new(user, visits_data)
        service.call

        visit = user.visits.find_by(name: 'Unknown Visit')
        expect(visit).to be_present
        expect(visit.place).to be_nil
      end
    end

    context 'with duplicate visits' do
      let(:visits_data) do
        [
          {
            'name' => 'Duplicate Visit',
            'started_at' => '2024-01-01T09:00:00Z',
            'ended_at' => '2024-01-01T17:00:00Z',
            'duration' => 28_800,
            'status' => 'confirmed'
          }
        ]
      end

      let!(:existing_visit) do
        create(:visit,
               user: user,
               name: 'Duplicate Visit',
               started_at: Time.zone.parse('2024-01-01T09:00:00Z'),
               ended_at: Time.zone.parse('2024-01-01T17:00:00Z'))
      end

      it 'skips the duplicate visit' do
        service = described_class.new(user, visits_data)

        expect { service.call }.not_to(change { user.visits.count })
      end

      it 'returns 0 for skipped visits' do
        service = described_class.new(user, visits_data)

        expect(service.call).to eq(0)
      end
    end

    context 'with invalid visit data' do
      let(:visits_data) do
        [
          { 'not_a_visit' => 'invalid' },
          'string_instead_of_hash',
          nil,
          {
            'name' => 'Valid Visit',
            'started_at' => '2024-01-01T09:00:00Z',
            'ended_at' => '2024-01-01T17:00:00Z',
            'duration' => 28_800,
            'status' => 'confirmed'
          }
        ]
      end

      it 'skips invalid entries and imports valid ones' do
        service = described_class.new(user, visits_data)

        expect(service.call).to eq(1)
        expect(user.visits.find_by(name: 'Valid Visit')).to be_present
      end
    end

    context 'with multiple users' do
      let(:other_user) { create(:user) }
      let!(:other_user_visit) do
        create(:visit,
               user: other_user,
               name: 'Other User Visit',
               started_at: Time.zone.parse('2024-01-01T09:00:00Z'),
               ended_at: Time.zone.parse('2024-01-01T17:00:00Z'))
      end

      let(:visits_data) do
        [
          {
            'name' => 'Other User Visit',
            'started_at' => '2024-01-01T09:00:00Z',
            'ended_at' => '2024-01-01T17:00:00Z',
            'duration' => 28_800,
            'status' => 'confirmed'
          }
        ]
      end

      it 'creates the visit for the target user (not a duplicate across users)' do
        service = described_class.new(user, visits_data)

        expect { service.call }.to change { user.visits.count }.by(1)
      end
    end
  end
end

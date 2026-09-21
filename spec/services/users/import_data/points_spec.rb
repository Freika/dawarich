# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Users::ImportData::Points, type: :service do
  let(:user) { create(:user) }
  let(:service) { described_class.new(user, points_data) }

  describe '#call' do
    context 'when importing points with country information' do
      let(:country) { create(:country, name: 'Germany', iso_a2: 'DE', iso_a3: 'DEU') }
      let(:points_data) do
        [
          {
            'timestamp' => 1_640_995_200,
            'lonlat' => 'POINT(13.4050 52.5200)',
            'city' => 'Berlin',
            'country' => 'Germany', # String field from export
            'country_info' => {
              'name' => 'Germany',
              'iso_a2' => 'DE',
              'iso_a3' => 'DEU'
            }
          }
        ]
      end

      before do
        country # Create the country
      end

      it 'creates points without type errors' do
        expect { service.call }.not_to raise_error
      end

      it 'assigns the correct country association' do
        service.call
        point = user.points.last
        expect(point.country).to eq(country)
      end

      it 'excludes the string country field from attributes' do
        service.call
        point = user.points.last
        # The country association should be set, not the string attribute
        expect(point.read_attribute(:country)).to be_nil
        expect(point.country).to eq(country)
      end
    end

    context 'when country does not exist in database' do
      let(:points_data) do
        [
          {
            'timestamp' => 1_640_995_200,
            'lonlat' => 'POINT(13.4050 52.5200)',
            'city' => 'Berlin',
            'country' => 'NewCountry',
            'country_info' => {
              'name' => 'NewCountry',
              'iso_a2' => 'NC',
              'iso_a3' => 'NCO'
            }
          }
        ]
      end

      it 'does not create country and leaves country_id nil' do
        expect { service.call }.not_to change(Country, :count)

        point = user.points.last
        expect(point.country_id).to be_nil
        expect(point.city).to eq('Berlin')
      end
    end

    context 'when points_data is empty' do
      let(:points_data) { [] }

      it 'returns 0 without errors' do
        expect(service.call).to eq(0)
      end
    end

    context 'when resolving a visit without a custom name' do
      let!(:visit) do
        create(:visit, user: user, name: nil, location_label: 'Detected address',
                       started_at: Time.zone.parse('2024-01-01 10:00:00 UTC'),
                       ended_at: Time.zone.parse('2024-01-01 11:00:00 UTC'))
      end
      let(:points_data) do
        [
          {
            'timestamp' => 1_704_106_800,
            'lonlat' => 'POINT(13.4050 52.5200)',
            'visit_reference' => {
              'name' => nil,
              'location_label' => 'Detected address',
              'started_at' => visit.started_at.iso8601,
              'ended_at' => visit.ended_at.iso8601,
              'place_reference' => nil
            }
          }
        ]
      end

      it 'restores the point-to-visit association' do
        service.call

        expect(user.points.last.visit).to eq(visit)
      end
    end

    context 'when same-window visits belong to different Places' do
      let(:started_at) { Time.zone.parse('2024-01-01 10:00:00 UTC') }
      let(:home) { create(:place, user: user, name: 'Home', latitude: 40, longitude: -74) }
      let(:office) { create(:place, user: user, name: 'Office', latitude: 41, longitude: -75) }
      let!(:home_visit) do
        create(:visit, user: user, place: home, name: nil, location_label: 'Detected stop',
                       started_at: started_at, ended_at: started_at + 1.hour)
      end
      let!(:office_visit) do
        create(:visit, user: user, place: office, name: nil, location_label: 'Detected stop',
                       started_at: started_at, ended_at: started_at + 1.hour)
      end
      let(:points_data) do
        [home, office].each_with_index.map do |place, index|
          {
            'timestamp' => 1_704_106_800 + index,
            'lonlat' => "POINT(#{place.lon} #{place.lat})",
            'visit_reference' => {
              'name' => nil,
              'location_label' => 'Detected stop',
              'started_at' => started_at.iso8601,
              'ended_at' => (started_at + 1.hour).iso8601,
              'place_reference' => {
                'name' => place.name,
                'latitude' => place.lat,
                'longitude' => place.lon
              }
            }
          }
        end
      end

      it 'restores each Point to the Visit at its referenced Place' do
        service.call

        expect(user.points.order(:timestamp).pluck(:visit_id)).to eq([home_visit.id, office_visit.id])
      end
    end

    context 'when points_data is not an array' do
      let(:points_data) { 'invalid' }

      it 'returns 0 without errors' do
        expect(service.call).to eq(0)
      end
    end

    context 'when points have invalid or missing data' do
      let(:points_data) do
        [
          {
            'timestamp' => 1_640_995_200,
            'lonlat' => 'POINT(13.4050 52.5200)',
            'city' => 'Berlin'
          },
          {
            # Missing lonlat but has longitude/latitude (should be reconstructed)
            'timestamp' => 1_640_995_220,
            'longitude' => 11.5820,
            'latitude' => 48.1351,
            'city' => 'Munich'
          },
          {
            # Missing lonlat and coordinates
            'timestamp' => 1_640_995_260,
            'city' => 'Hamburg'
          },
          {
            # Missing timestamp
            'lonlat' => 'POINT(11.5820 48.1351)',
            'city' => 'Stuttgart'
          },
          {
            # Invalid lonlat format
            'timestamp' => 1_640_995_320,
            'lonlat' => 'invalid format',
            'city' => 'Frankfurt'
          }
        ]
      end

      it 'imports valid points and reconstructs lonlat when needed' do
        expect(service.call).to eq(2) # Two valid points (original + reconstructed)
        expect(user.points.count).to eq(2)

        # Check that lonlat was reconstructed properly
        munich_point = user.points.find_by(city: 'Munich')
        expect(munich_point).to be_present
        expect(munich_point.lonlat.to_s).to match(/POINT\s*\(11\.582\s+48\.1351\)/)
      end
    end
  end
end

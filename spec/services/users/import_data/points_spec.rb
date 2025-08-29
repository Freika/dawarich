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
            'timestamp' => 1640995200,
            'lonlat' => 'POINT(13.4050 52.5200)',
            'city' => 'Berlin',
            'country' => 'Germany',  # String field from export
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
            'timestamp' => 1640995200,
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
            'timestamp' => 1640995200,
            'lonlat' => 'POINT(13.4050 52.5200)',
            'city' => 'Berlin'
          },
          {
            # Missing lonlat but has longitude/latitude (should be reconstructed)
            'timestamp' => 1640995220,
            'longitude' => 11.5820,
            'latitude' => 48.1351,
            'city' => 'Munich'
          },
          {
            # Missing lonlat and coordinates
            'timestamp' => 1640995260,
            'city' => 'Hamburg'
          },
          {
            # Missing timestamp
            'lonlat' => 'POINT(11.5820 48.1351)',
            'city' => 'Stuttgart'
          },
          {
            # Invalid lonlat format
            'timestamp' => 1640995320,
            'lonlat' => 'invalid format',
            'city' => 'Frankfurt'
          }
        ]
      end

      it 'imports valid points and reconstructs lonlat when needed' do
        expect(service.call).to eq(2)  # Two valid points (original + reconstructed)
        expect(user.points.count).to eq(2)

        # Check that lonlat was reconstructed properly
        munich_point = user.points.find_by(city: 'Munich')
        expect(munich_point).to be_present
        expect(munich_point.lonlat.to_s).to match(/POINT\s*\(11\.582\s+48\.1351\)/)
      end
    end
  end
end

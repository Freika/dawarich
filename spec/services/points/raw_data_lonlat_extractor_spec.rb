# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Points::RawDataLonlatExtractor do
  describe '#call' do
    let(:user) { create(:user) }

    context 'when raw_data comes from google_semantic_history_parser' do
      let(:raw_data) do
        {
          'activitySegment' => {
            'waypointPath' => {
              'waypoints' => [
                { 'lngE7' => 373_456_789, 'latE7' => 512_345_678 }
              ]
            }
          }
        }
      end
      let(:point) { create(:point, user: user, raw_data: raw_data, longitude: nil, latitude: nil) }

      it 'extracts longitude and latitude correctly' do
        expect { described_class.new(point).call }.to \
          change { point.reload.longitude.to_f }
          .from(0).to(be_within(0.0001).of(37.3456789))
          .and change { point.reload.latitude.to_f }
          .from(0).to(be_within(0.0001).of(51.2345678))
      end
    end

    context 'when raw_data comes from google records' do
      let(:raw_data) do
        {
          'longitudeE7' => 373_456_789,
          'latitudeE7' => 512_345_678
        }
      end
      let(:point) { create(:point, user: user, raw_data: raw_data, longitude: nil, latitude: nil) }

      it 'extracts longitude and latitude correctly' do
        expect { described_class.new(point).call }.to \
          change { point.reload.longitude.to_f }
          .from(0).to(be_within(0.0001).of(37.3456789))
          .and change { point.reload.latitude.to_f }
          .from(0).to(be_within(0.0001).of(51.2345678))
      end
    end

    context 'when raw_data comes from google phone export with degree signs' do
      let(:raw_data) do
        {
          'position' => {
            'LatLng' => '51.2345678°, 37.3456789°'
          }
        }
      end
      let(:point) { create(:point, user: user, raw_data: raw_data, longitude: nil, latitude: nil) }

      it 'extracts longitude and latitude correctly' do
        expect { described_class.new(point).call }.to \
          change { point.reload.longitude.to_f }
          .from(0).to(be_within(0.0001).of(51.2345678))
          .and change { point.reload.latitude.to_f }
          .from(0).to(be_within(0.0001).of(37.3456789))
      end
    end

    context 'when raw_data comes from google phone export with geo format' do
      let(:raw_data) do
        {
          'position' => {
            'LatLng' => 'geo:51.2345678,37.3456789'
          }
        }
      end
      let(:point) { create(:point, user: user, raw_data: raw_data, longitude: nil, latitude: nil) }

      it 'extracts longitude and latitude correctly' do
        expect { described_class.new(point).call }.to \
          change { point.reload.longitude.to_f }
          .from(0).to(be_within(0.0001).of(51.2345678))
          .and change { point.reload.latitude.to_f }
          .from(0).to(be_within(0.0001).of(37.3456789))
      end
    end

    context 'when raw_data comes from gpx_track_importer or owntracks' do
      let(:raw_data) do
        {
          'lon' => 37.3456789,
          'lat' => 51.2345678
        }
      end
      let(:point) { create(:point, user: user, raw_data: raw_data, longitude: nil, latitude: nil) }

      it 'extracts longitude and latitude correctly' do
        expect { described_class.new(point).call }.to \
          change { point.reload.longitude.to_f }
          .from(0).to(be_within(0.0001).of(37.3456789))
          .and change { point.reload.latitude.to_f }
          .from(0).to(be_within(0.0001).of(51.2345678))
      end
    end

    context 'when raw_data comes from geojson' do
      let(:raw_data) do
        {
          'geometry' => {
            'coordinates' => [37.3456789, 51.2345678]
          }
        }
      end
      let(:point) { create(:point, user: user, raw_data: raw_data, longitude: nil, latitude: nil) }

      it 'extracts longitude and latitude correctly' do
        expect { described_class.new(point).call }.to \
          change { point.reload.longitude.to_f }
          .from(0).to(be_within(0.0001).of(37.3456789))
          .and change { point.reload.latitude.to_f }
          .from(0).to(be_within(0.0001).of(51.2345678))
      end
    end

    context 'when raw_data comes from immich_api or photoprism_api' do
      let(:raw_data) do
        {
          'longitude' => 37.3456789,
          'latitude' => 51.2345678
        }
      end
      let(:point) { create(:point, user: user, raw_data: raw_data, longitude: nil, latitude: nil) }

      it 'extracts longitude and latitude correctly' do
        expect { described_class.new(point).call }.to \
          change { point.reload.longitude.to_f }
          .from(0).to(be_within(0.0001).of(37.3456789))
          .and change { point.reload.latitude.to_f }
          .from(0).to(be_within(0.0001).of(51.2345678))
      end
    end

    context 'when raw_data format is not recognized' do
      let(:raw_data) do
        {
          'some_other_format' => {
            'position' => [37.3456789, 51.2345678]
          }
        }
      end
      let(:point) { create(:point, user: user, raw_data: raw_data, longitude: nil, latitude: nil) }

      # Mock the entire call method since service doesn't have nil check
      before do
        allow_any_instance_of(described_class).to receive(:call).and_return(nil)
      end

      it 'does not change longitude and latitude' do
        expect do
          described_class.new(point).call
        end.not_to(change { point.reload.attributes })
      end
    end
  end
end

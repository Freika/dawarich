require 'rails_helper'

RSpec.describe ReverseGeocodingJob, type: :job do
  describe '#perform' do
    subject(:perform) { described_class.new.perform(point.id) }

    let(:point) { create(:point) }

    before do
      allow(Geocoder).to receive(:search).and_return([double(city: 'City', country: 'Country')])
    end

    context 'when REVERSE_GEOCODING_ENABLED is false' do
      before { stub_const('REVERSE_GEOCODING_ENABLED', false) }

      it 'does not update point' do
        expect { perform }.not_to(change { point.reload.city })
      end

      it 'does not call Geocoder' do
        perform

        expect(Geocoder).not_to have_received(:search)
      end
    end

    context 'when REVERSE_GEOCODING_ENABLED is true' do
      before { stub_const('REVERSE_GEOCODING_ENABLED', true) }

      it 'updates point with city and country' do
        expect { perform }.to change { point.reload.city }.from(nil)
      end

      it 'calls Geocoder' do
        perform

        expect(Geocoder).to have_received(:search).with([point.latitude, point.longitude])
      end

      context 'when point has city and country' do
        let(:point) { create(:point, city: 'City', country: 'Country') }

        before do
          allow(Geocoder).to receive(:search).and_return(
            [double(city: 'Another city', country: 'Some country')]
          )
        end

        it 'does not update point' do
          expect { perform }.not_to change { point.reload.city }
        end

        it 'does not call Geocoder' do
          perform

          expect(Geocoder).not_to have_received(:search)
        end
      end
    end
  end
end

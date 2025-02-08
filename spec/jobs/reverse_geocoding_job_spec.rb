# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ReverseGeocodingJob, type: :job do
  describe '#perform' do
    subject(:perform) { described_class.new.perform('Point', point.id) }

    let(:point) { create(:point) }

    before do
      allow(Geocoder).to receive(:search).and_return([double(city: 'City', country: 'Country')])
    end

    context 'when reverse geocoding is disabled' do
      before { allow(DawarichSettings).to receive(:reverse_geocoding_enabled?).and_return(false) }

      it 'does not update point' do
        expect { perform }.not_to(change { point.reload.city })
      end

      it 'does not call ReverseGeocoding::Points::FetchData' do
        allow(ReverseGeocoding::Points::FetchData).to receive(:new).and_call_original

        perform

        expect(ReverseGeocoding::Points::FetchData).not_to have_received(:new)
      end
    end

    context 'when reverse geocoding is enabled' do
      before { allow(DawarichSettings).to receive(:reverse_geocoding_enabled?).and_return(true) }

      let(:stubbed_geocoder) { OpenStruct.new(data: { city: 'City', country: 'Country' }) }

      it 'calls Geocoder' do
        allow(Geocoder).to receive(:search).and_return([stubbed_geocoder])
        allow(ReverseGeocoding::Points::FetchData).to receive(:new).and_call_original

        perform

        expect(ReverseGeocoding::Points::FetchData).to have_received(:new).with(point.id)
      end
    end
  end
end

# frozen_string_literal: true

require 'rails_helper'

RSpec.describe DataMigrations::SetPointsCountryIdsJob, type: :job do
  describe '#perform' do
    let(:point) { create(:point, lonlat: 'POINT(10.0 20.0)', country_id: nil) }
    let(:country) { create(:country) }

    before do
      allow(Country).to receive(:containing_point)
        .with(point.lon, point.lat)
        .and_return(country)
    end

    it 'updates the point with the correct country_id' do
      described_class.perform_now(point.id)

      expect(point.reload.country_id).to eq(country.id)
    end
  end

  describe 'queue' do
    it 'uses the default queue' do
      expect(described_class.queue_name).to eq('default')
    end
  end
end

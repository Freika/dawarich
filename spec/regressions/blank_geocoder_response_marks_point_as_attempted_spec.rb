# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Blank geocoder response marks the point as attempted' do
  subject(:fetch_data) { ReverseGeocoding::Points::FetchData.new(point.id).call }

  let(:point) do
    pt = create(:point)
    pt.update_columns(country_id: nil, country_name: nil, city: nil)
    pt.reload
  end

  context 'when Geocoder returns no results (e.g. point over the ocean)' do
    before { allow(Geocoder).to receive(:search).and_return([]) }

    it 'sets reverse_geocoded_at so the point is not re-queued forever' do
      expect { fetch_data }.to change { point.reload.reverse_geocoded_at }.from(nil)
    end

    it 'removes the point from the not_reverse_geocoded scope' do
      fetch_data
      expect(Point.not_reverse_geocoded).not_to include(point.reload)
    end

    it 'leaves city, country_id, and geodata empty' do
      fetch_data
      point.reload
      expect(point.city).to be_blank
      expect(point.country_id).to be_nil
      expect(point.geodata).to eq({})
    end
  end

  context 'when Geocoder returns a result with an error field' do
    before do
      allow(Geocoder).to receive(:search).and_return(
        [double(city: nil, country: nil, data: { 'error' => 'boom' })]
      )
    end

    it 'does not mark the point as attempted, so it stays eligible for retry' do
      expect { fetch_data }.not_to(change { point.reload.reverse_geocoded_at })
      expect(Point.not_reverse_geocoded).to include(point.reload)
    end
  end
end

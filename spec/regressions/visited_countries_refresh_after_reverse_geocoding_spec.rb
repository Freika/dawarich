# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Visited countries after reverse geocoding', type: :request do
  let(:user) { create(:user) }
  let!(:germany) { create(:country, name: 'Germany', iso_a2: 'DE', iso_a3: 'DEU') }
  let!(:point) do
    create(:point, user:, timestamp: 1_000).tap do |created|
      created.update_columns(country_id: nil, country_name: nil, country: nil, city: nil,
                             reverse_geocoded_at: nil)
    end
  end
  let(:scope) { { api_key: user.api_key, start_at: 900, end_at: 1_200 } }

  before do
    configure_instance_geocoding
    allow(Geocoder).to receive(:search).and_return(
      [double(city: 'Berlin', country: 'Germany', country_code: 'de', data: {})]
    )
  end

  it 'serves the geocoded country to a client revalidating the earlier empty list' do
    get '/api/v1/countries/visited', params: scope
    expect(response.parsed_body).to eq('countries' => [])
    cached_etag = response.headers.fetch('ETag')

    ReverseGeocoding::Points::FetchData.new(point.id).call

    get '/api/v1/countries/visited', params: scope, headers: { 'If-None-Match' => cached_etag }

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to eq('countries' => [{ 'iso_a3' => 'DEU', 'name' => 'Germany' }])
  end

  it 'does not confirm a points tile cached before the geocoding write as fresh' do
    get '/api/v1/tiles/points/0/0/0.mvt', params: scope
    cached_etag = response.headers.fetch('ETag')

    ReverseGeocoding::Points::FetchData.new(point.id).call

    get '/api/v1/tiles/points/0/0/0.mvt', params: scope, headers: { 'If-None-Match' => cached_etag }

    expect(response).not_to have_http_status(:not_modified)
  end
end

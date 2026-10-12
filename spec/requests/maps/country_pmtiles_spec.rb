# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'country PMTiles static delivery', type: :request do
  it 'serves byte ranges required by the PMTiles browser protocol' do
    get '/maps/countries-v2.pmtiles', headers: { 'Range' => 'bytes=0-7' }

    expect(response).to have_http_status(:partial_content)
    expect(response.headers['Content-Range']).to start_with('bytes 0-7/')
    expect(response.body).to eq("PMTiles\x03".b)
  end
end

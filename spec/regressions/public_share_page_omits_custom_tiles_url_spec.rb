# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'custom basemap URL exposure', type: :request do
  let(:tiles_url) { 'https://tiles.internal.example/{z}/{x}/{y}.png' }
  let(:user) do
    create(:user).tap do |u|
      u.settings['maps_maplibre_tiles_url'] = tiles_url
      u.save!
    end
  end
  let!(:stat) { create(:stat, :with_sharing_enabled, user:, year: 2024, month: 6) }

  before do
    create_list(:point, 5, user:, timestamp: Time.new(2024, 6, 15).to_i)
  end

  it 'passes the owner their own custom basemap on the monthly stats page' do
    sign_in user

    get '/stats/2024/6'

    expect(response.body).to include("data-tiles-url=\"#{tiles_url}\"")
  end

  it 'never exposes the custom basemap URL on the publicly shared page' do
    get shared_stat_url(stat.sharing_uuid)

    expect(response).to have_http_status(:success)
    expect(response.body).not_to include('data-tiles-url')
    expect(response.body).not_to include(tiles_url)
  end
end

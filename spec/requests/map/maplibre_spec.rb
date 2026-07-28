# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Map v2 (maplibre)', type: :request do
  let(:user) { create(:user) }

  before { sign_in user }

  describe 'poster studio' do
    it 'renders the poster tab button' do
      get map_v2_path

      expect(response.body).to include('map-button-poster')
    end

    it 'renders the vendored poster theme tokens for the map colour editor' do
      get map_v2_path

      expect(response.body).to include('Blueprint')
    end

    it 'renders the studio date controls on the map page' do
      get map_v2_path

      expect(response.body).to include('data-poster-studio-editor-target="dateStart"')
    end

    it 'defaults the track opacity slider to 100%' do
      get map_v2_path

      slider = Nokogiri::HTML(response.body).at_css('[data-poster-studio-editor-target="trackOpacity"]')
      expect(slider['value']).to eq('100')
    end
  end

  describe 'print ordering' do
    before do
      stub_const('POSTER_SERVICE_URL', 'http://localhost:8123')
      stub_const('POSTER_SERVICE_TOKEN', nil)
      Rails.cache.delete('poster_service_themes')
      stub_request(:get, 'http://localhost:8123/themes')
        .to_return(status: 200, body: [{ key: 'blueprint', name: 'Blueprint', bg: '#1A3A5C',
                                         text: '#E8F4FF', route: '#FF6B4A' }].to_json)
    end

    it 'exposes the production order endpoint by default' do
      get map_v2_path

      expect(response.body)
        .to include('data-poster-studio-editor-print-order-url-value="https://prints.dawarich.app/api/orders"')
    end

    it 'lets PRINT_ORDER_URL override the default' do
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with('PRINT_ORDER_URL', anything)
                                   .and_return('http://localhost:3001/api/orders')

      get map_v2_path

      expect(response.body)
        .to include('data-poster-studio-editor-print-order-url-value="http://localhost:3001/api/orders"')
    end

    it 'renders the order section when the poster_ordering flag is enabled' do
      Flipper.enable(:poster_ordering)

      get map_v2_path

      expect(response.body).to include('Order a printed poster')
    end

    it 'omits the order section when the poster_ordering flag is disabled' do
      Flipper.disable(:poster_ordering)

      get map_v2_path

      expect(response.body).not_to include('Order a printed poster')
    end
  end

  describe 'GET /map/v2 date window (C1)' do
    it 'derives the data window from ?date= when start_at/end_at are absent' do
      get map_v2_path(date: '2026-05-28', panel: 'timeline')

      expect(response).to have_http_status(:ok)
      # The top date-range form must render the requested day so the map,
      # the form, and the Timeline panel all agree (no silent desync).
      expect(response.body).to include('2026-05-28T00:00')
      expect(response.body).to include('2026-05-28T23:59')
    end

    it 'still honors explicit start_at/end_at over ?date=' do
      get map_v2_path(date: '2026-05-28', start_at: '2026-05-20T00:00', end_at: '2026-05-20T23:59')

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('2026-05-20T00:00')
    end

    it 'keeps the Timeline panel open across the date-range form (preserves panel param)' do
      get map_v2_path(date: 'today', panel: 'timeline')

      expect(response.body).to include('name="panel"')
      expect(response.body).to include('value="timeline"')
    end
  end

  describe 'share hub entry' do
    it 'renders a Share button opening the share hub in the share-link-modal frame' do
      get map_v2_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(share_links_hub_path)
      expect(response.body).to include('timeline-share-button')
      expect(response.body).to include('share-link-modal')
    end
  end
end

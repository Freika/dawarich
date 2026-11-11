# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Map v2 (maplibre)', type: :request do
  let(:user) { create(:user) }

  before { sign_in user }

  it 'does not gate map layers for a Lite user on a self-hosted instance' do
    allow(DawarichSettings).to receive(:self_hosted?).and_return(true)
    user.update!(plan: :lite)

    get map_v2_path

    expect(response.body).not_to include('data-maps--maplibre-user-plan-value="lite"')
  end

  it 'hands the map the layers the server gates for Lite' do
    get map_v2_path

    map = Nokogiri::HTML(response.body).at_css('[data-maps--maplibre-gated-layers-value]')
    expect(JSON.parse(map['data-maps--maplibre-gated-layers-value']))
      .to eq(Users::PlanSettingsGate::GATED_MAP_LAYERS)
  end

  describe 'opening a month' do
    def period
      map = Nokogiri::HTML(response.body).at_css('#maps-maplibre-container')
      %w[start end].map { |edge| Time.zone.parse(map["data-maps--maplibre-#{edge}-date-value"]).utc.to_date.to_s }
    end

    before do
      create(:note, user: user, body: 'Old', noted_at: Time.utc(2025, 3, 10, 12), latitude: 52.5, longitude: 13.4)
      create(:note, user: user, body: 'Latest', noted_at: Time.utc(2025, 6, 10, 12), latitude: 52.5, longitude: 13.4)
    end

    it 'opens the month of the latest note for the Diary menu item' do
      get map_v2_path(panel: 'timeline', month: 'latest')

      expect(period).to eq(%w[2025-06-01 2025-06-30])
    end

    it 'takes the month of the latest note from the user time zone' do
      user.update!(settings: user.settings.merge('timezone' => 'Asia/Tokyo'))
      # 16:00 UTC on June 30 is already July 1 in Tokyo.
      create(:note, user: user, body: 'Late', noted_at: Time.utc(2025, 6, 30, 16), latitude: 35.68, longitude: 139.76)

      get map_v2_path(panel: 'timeline', month: 'latest')

      map = Nokogiri::HTML(response.body).at_css('#maps-maplibre-container')
      first_day = Time.zone.parse(map['data-maps--maplibre-start-date-value']).in_time_zone('Asia/Tokyo').to_date
      expect(first_day.to_s).to eq('2025-07-01')
    end

    it 'opens the month asked for, whatever day is to be selected in it' do
      get map_v2_path(panel: 'timeline', month: '2025-03', date: '2025-03-10')

      expect(period).to eq(%w[2025-03-01 2025-03-31])
    end
  end

  it 'renders the place editor only inside the left map panel' do
    get map_v2_path

    document = Nokogiri::HTML(response.body)
    panel = document.at_css('#map-settings-panel [data-tab-content="place"]')
    expect(panel).to be_present
    expect(panel.at_css('[data-controller="place-panel"] turbo-frame#place-drawer')).to be_present
    expect(panel.at_css('[data-action="place-panel#close"]')).to be_present
    expect(document.css('turbo-frame#place-drawer').size).to eq(1)
    expect(document.at_css('#maps-maplibre-container > .place-panel')).to be_nil
  end

  it 'keeps one panel header close control and only Back inside the place editor' do
    get map_v2_path

    document = Nokogiri::HTML(response.body)
    panel = document.at_css('#map-settings-panel')
    expect(panel.css('.panel-header button').size).to eq(1)
    toolbar = panel.at_css('.place-panel__toolbar')
    expect(toolbar.css('button').size).to eq(1)
    expect(toolbar.at_css('button').text.strip).to eq(I18n.t('map.maplibre.settings_panel.back'))
    expect(toolbar.at_css('button')['data-action']).to eq('place-panel#close')
  end

  it 'lets Turbo own the persistent creation form submit state' do
    get map_v2_path

    document = Nokogiri::HTML(response.body)
    submit = document.at_css('[data-place-creation-target="submitButton"]')
    expect(submit['data-turbo-submits-with']).to be_present
    expect(submit['data-disable-with']).to be_nil
  end

  describe 'privacy zones' do
    def fingerprint_value
      map = Nokogiri::HTML(response.body).at_css('[data-controller~="maps--maplibre"]')
      map.attribute('data-maps--maplibre-privacy-zones-fingerprint-value')&.value
    end

    it 'renders the zone fingerprint for tile requests' do
      place = create(:place, user:, latitude: 52.44, longitude: 13.5, lonlat: 'POINT(13.5 52.44)')
      create(:tagging, tag: create(:tag, :privacy_zone, user:), taggable: place)

      get map_v2_path

      expect(fingerprint_value).to eq(Maps::PrivacyZoneMasker.new(user).fingerprint).and be_present
    end

    it 'renders no fingerprint without zones' do
      get map_v2_path

      expect(fingerprint_value).to be_blank
    end
  end

  describe 'unified Places UI' do
    it 'offers one Place workflow and no separate Area controls' do
      get map_v2_path

      document = Nokogiri::HTML(response.body)
      expect(document.at_css('[data-action="click->maps--maplibre#startCreatePlace"]')).to be_present
      expect(document.at_css('[data-action="click->maps--maplibre#startCreateArea"]')).to be_nil
      expect(document.at_css('[data-maps--maplibre-target="areasToggle"]')).to be_nil
      expect(response.body).to include('Select data on map')
    end

    it 'renders the shared Place form with Visit Radius and Visit attachment context' do
      get map_v2_path

      document = Nokogiri::HTML(response.body)
      expect(document.at_css('input[name="place[visit_radius]"]')).to be_present
      expect(document.at_css('input[name="visit_id"]')).to be_present
    end

    it 'offers a Place boundaries toggle within the Places layer controls' do
      get map_v2_path

      document = Nokogiri::HTML(response.body)
      toggle = document.at_css('[data-maps--maplibre-target="placesFilters"] ' \
                               '[data-maps--maplibre-target="placeBoundariesToggle"]')
      expect(toggle['data-action']).to eq('change->maps--maplibre#togglePlaceBoundaries')
    end
  end

  describe 'Lite data window' do
    it 'tells the map where the Lite data window starts' do
      allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
      user.update_column(:plan, User.plans[:lite])

      get map_v2_path

      expect(response.body).to include(
        %(data-maps--maplibre-data-window-start-value="#{user.data_window_start.iso8601}")
      )
    end

    it 'leaves the data window empty for users without one' do
      get map_v2_path

      expect(response.body).to include('data-maps--maplibre-data-window-start-value=""')
    end
  end

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

    it 'renders date and time controls for the video studio' do
      get map_v2_path

      expect(response.body).to include('data-video-studio-target="dateStart"')
      expect(response.body).to include('data-video-studio-target="dateEnd"')
      expect(response.body).to include('video-studio#applyDateTimeRange')
    end

    it 'exposes the user timezone as an IANA identifier' do
      user.update!(settings: user.settings.merge('timezone' => 'Eastern Time (US & Canada)'))

      get map_v2_path

      expect(response.body).to include('data-maps--maplibre-timezone-value="America/New_York"')
      expect(response.body).to include('data-map-controls-timezone-value="America/New_York"')
    end

    it 'defaults the track opacity slider to 100%' do
      get map_v2_path

      slider = Nokogiri::HTML(response.body).at_css('[data-poster-studio-editor-target="trackOpacity"]')
      expect(slider['value']).to eq('100')
    end

    it 'hands the custom tiles settings to both studios' do
      tiles_url = 'https://tiles.example.test/planet/{z}/{x}/{y}.mvt'
      user.update!(settings: user.settings.merge('maps_maplibre_tiles_url' => tiles_url,
                                                 'maps_maplibre_tiles_fallback' => true))

      get map_v2_path

      page = Nokogiri::HTML(response.body)
      %w[poster-studio-editor video-studio].each do |studio|
        root = page.at_css("[data-controller=\"#{studio}\"]")
        expect(root["data-#{studio}-tiles-url-value"]).to eq(tiles_url)
        expect(root["data-#{studio}-tiles-fallback-value"]).to eq('true')
      end
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

    it 'renders the order section on an instance carrying no flag at all' do
      Flipper.remove(:poster_ordering)

      get map_v2_path

      expect(response.body).to include('Order a printed poster')
    end

    it 'renders the order section when a legacy poster_ordering flag is disabled' do
      Flipper.disable(:poster_ordering)

      get map_v2_path

      expect(response.body).to include('Order a printed poster')
    end
  end

  describe 'empty period state' do
    def empty_state
      get map_v2_path
      Nokogiri::HTML(response.body).at_css('[data-testid="map-empty-state"]')
    end

    it 'offers a jump to the day of the latest point, hidden until the map reports an empty period' do
      create(:point, user: user, timestamp: Time.zone.parse('2025-10-16 12:00').to_i)

      state = empty_state

      expect(state['class']).to include('hidden')
      expect(state['href']).to eq(map_v2_path(date: '2025-10-16'))
    end

    it 'keeps the open panel when jumping' do
      create(:point, user: user, timestamp: Time.zone.parse('2025-10-16 12:00').to_i)

      get map_v2_path(panel: 'timeline')
      link = Nokogiri::HTML(response.body).at_css('a[data-testid="map-empty-state"]')

      expect(link['href']).to eq(map_v2_path(date: '2025-10-16', panel: 'timeline'))
    end

    it 'jumps to the latest day outside a Privacy Zone' do
      tag = create(:tag, :privacy_zone, user: user, privacy_radius_meters: 500)
      place = create(:place, user: user, latitude: 52.52, longitude: 13.405, lonlat: 'POINT(13.405 52.52)')
      create(:tagging, tag: tag, taggable: place)
      create(:point, user: user, lonlat: 'POINT(13.405 52.52)', timestamp: Time.zone.parse('2025-10-16 12:00').to_i)
      create(:point, user: user, lonlat: 'POINT(11.57 48.13)', timestamp: Time.zone.parse('2025-09-02 12:00').to_i)

      expect(empty_state['href']).to eq(map_v2_path(date: '2025-09-02'))
    end

    it 'offers no jump when every point is inside a Privacy Zone' do
      tag = create(:tag, :privacy_zone, user: user, privacy_radius_meters: 500)
      place = create(:place, user: user, latitude: 52.52, longitude: 13.405, lonlat: 'POINT(13.405 52.52)')
      create(:tagging, tag: tag, taggable: place)
      create(:point, user: user, lonlat: 'POINT(13.405 52.52)', timestamp: Time.zone.parse('2025-10-16 12:00').to_i)

      expect(empty_state.name).to eq('div')
    end

    it 'reads the latest day in the timezone from settings' do
      user.update!(settings: user.settings.merge('timezone' => 'America/Los_Angeles'))
      create(:point, user: user, timestamp: Time.utc(2025, 10, 16, 3, 0).to_i)

      expect(empty_state['href']).to eq(map_v2_path(date: '2025-10-15'))
    end

    it 'does not claim nothing was recorded when the data is outside the Lite window' do
      allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
      user.update_column(:plan, User.plans[:lite])
      create(:point, user: user, timestamp: 2.years.ago.to_i)

      state = empty_state

      expect(state.name).to eq('div')
      expect(state.text.strip).to eq(I18n.t('map.maplibre.index.no_data_in_period'))
    end

    it 'points an account without any data to the getting-started guide' do
      state = empty_state

      expect(state.name).to eq('button')
      expect(state['onclick']).to eq('getting_started.showModal()')
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

    it 'keeps the Timeline panel open across the day arrows and presets of the period picker' do
      get map_v2_path(date: 'today', panel: 'timeline')

      links = Nokogiri::HTML(response.body).css('.map-period a').map { |link| link['href'] }
      expect(links.size).to eq(5)
      expect(links).to all(include('panel=timeline'))
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

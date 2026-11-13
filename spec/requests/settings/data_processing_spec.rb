# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Settings: Data processing', type: :request do
  let(:user) { create(:user) }

  before do
    sign_in user
    # The cache database outlives the test database, so a key left behind by
    # another run with the same user id would make a queue look busy.
    Rails.cache.delete("recalculation_pending:#{user.id}")
    Rails.cache.delete("anomaly_backfill_pending:#{user.id}")
  end

  def page_html
    Nokogiri::HTML(response.body)
  end

  describe 'GET /settings/data_processing' do
    it 'shows the current track, GPS, city and transportation settings' do
      user.update!(settings: user.settings.merge('minutes_between_routes' => 45, 'gps_accuracy_threshold' => 80))

      get settings_data_processing_path

      expect(page_html.at_css('input[name="settings[minutes_between_routes]"]')['value']).to eq('45')
      expect(page_html.at_css('input[name="settings[gps_accuracy_threshold]"]')['value']).to eq('80')
      expect(page_html.at_css('input[name="settings[min_minutes_spent_in_city]"]')).to be_present
      expect(page_html.css('[data-testid="enabled-modes-fieldset"] input[type=checkbox]')).not_to be_empty
      expect(page_html.at_css('[data-testid="reclassify-history-button"]')).to be_present
    end

    it 'is a tab in the settings navigation' do
      get settings_general_index_path

      expect(page_html.css('nav a.tab').map { _1['href'] }).to include(settings_data_processing_path)
    end
  end

  describe 'PATCH /settings/data_processing' do
    it 'stores numbers and switches with the types the map reads' do
      patch settings_data_processing_path, params: {
        settings: { meters_between_routes: '700', minutes_between_routes: '40', split_tracks_at_midnight: '1',
                    gps_filtering_enabled: '0', gps_accuracy_filter_enabled: '1', gps_accuracy_threshold: '60',
                    min_minutes_spent_in_city: '90' }
      }

      settings = user.reload.settings
      expect(settings).to include('meters_between_routes' => 700, 'minutes_between_routes' => 40,
                                  'split_tracks_at_midnight' => true, 'gps_filtering_enabled' => false,
                                  'gps_accuracy_filter_enabled' => true, 'gps_accuracy_threshold' => 60,
                                  'min_minutes_spent_in_city' => 90)
      expect(response).to redirect_to(settings_data_processing_path)
    end

    it 'keeps the stored number when a field is sent empty or not a positive number' do
      user.update!(settings: user.settings.merge('min_minutes_spent_in_city' => 45, 'meters_between_routes' => 800))

      patch settings_data_processing_path,
            params: { settings: { min_minutes_spent_in_city: '', meters_between_routes: 'abc' } }

      expect(user.reload.settings).to include('min_minutes_spent_in_city' => 45, 'meters_between_routes' => 800)
    end

    it 'accepts a value saved earlier through the API that is off the form step' do
      user.update!(settings: user.settings.merge('gps_accuracy_threshold' => 75, 'min_minutes_spent_in_city' => 7))

      get settings_data_processing_path

      %w[gps_accuracy_threshold min_minutes_spent_in_city].each do |name|
        expect(page_html.at_css("input[name='settings[#{name}]']")['step']).to eq('1')
      end
    end

    it 'saves track and transportation settings in one submit' do
      patch settings_data_processing_path,
            params: { settings: { minutes_between_routes: '50', enabled_transportation_modes: ['', 'walking'] } }

      expect(user.reload.settings).to include('minutes_between_routes' => 50,
                                              'enabled_transportation_modes' => ['walking'])
    end

    it 'saves the detected transportation modes and starts the re-classification' do
      patch settings_data_processing_path,
            params: { settings: { enabled_transportation_modes: ['', 'walking', 'cycling'] } }

      expect(user.reload.settings['enabled_transportation_modes']).to contain_exactly('walking', 'cycling')
      expect(TransportationModes::UserReclassifyJob).to have_been_enqueued.with(user.id)
    end

    it 'saves the other settings while a re-classification runs, when the modes are unchanged' do
      status = Tracks::TransportationRecalculationStatus.new(user.id)
      status.start(total_tracks: 1)
      modes = user.safe_settings.enabled_transportation_modes

      patch settings_data_processing_path,
            params: { settings: { minutes_between_routes: '55', enabled_transportation_modes: ['', *modes.reverse] } }

      expect(user.reload.settings['minutes_between_routes']).to eq(55)
    ensure
      Rails.cache.delete(status.send(:cache_key))
    end

    it 'refuses to switch off every transportation mode' do
      before_modes = user.safe_settings.enabled_transportation_modes

      patch settings_data_processing_path, params: { settings: { enabled_transportation_modes: [''] } }

      expect(user.reload.safe_settings.enabled_transportation_modes).to eq(before_modes)
      expect(flash[:alert]).to eq(I18n.t('services.users.settings_updater.enable_at_least_one_transportation_mode'))
    end
  end

  describe 'POST /settings/data_processing/recalculate' do
    it 'queues one recalculation of tracks, stats and digests' do
      expect do
        post recalculate_settings_data_processing_path
        post recalculate_settings_data_processing_path
      end.to have_enqueued_job(Users::RecalculateDataJob).with(user.id, year: nil).exactly(:once)
    end
  end

  describe 'POST /settings/data_processing/reapply_anomaly_filter' do
    it 'queues one re-evaluation of past points' do
      expect do
        post reapply_anomaly_filter_settings_data_processing_path
        post reapply_anomaly_filter_settings_data_processing_path
      end.to have_enqueued_job(Points::AnomalyBackfillUserJob).with(user.id, reset: true).exactly(:once)
    end
  end

  context 'with a Lite plan on Dawarich Cloud' do
    let(:user) { create(:user, :lite_plan, status: :active, skip_auto_trial: true) }

    before { allow(DawarichSettings).to receive(:self_hosted?).and_return(false) }

    it 'does not queue the heavy rebuilds, as the API does not either' do
      expect do
        post recalculate_settings_data_processing_path
        post reapply_anomaly_filter_settings_data_processing_path
      end.not_to have_enqueued_job
      expect(flash[:alert]).to eq(I18n.t('controllers.application.this_feature_requires_a_pro_plan'))
    end

    it 'shows both rebuild buttons as unavailable and says why' do
      get settings_data_processing_path

      buttons = page_html.css('[data-testid="recalculate-button"], [data-testid="reapply-anomaly-filter-button"]')
      expect(buttons.size).to eq(2)
      expect(buttons.map { _1['disabled'] }).to all(be_present)
      reasons = buttons.map { page_html.at_css("##{_1['aria-describedby']}")&.text }
      expect(reasons).to all(eq(I18n.t('settings.data_processing.show.rebuilds_need_pro')))
    end
  end

  describe 'the map panel' do
    it 'no longer holds data processing settings and points to this page instead' do
      get map_v2_path

      expect(page_html.at_css('input[name="gpsFilteringEnabled"]')).to be_nil
      expect(page_html.at_css('[data-testid="enabled-modes-fieldset"]')).to be_nil
      expect(page_html.css('a').map { _1['href'] }).to include(settings_data_processing_path)
    end
  end
end

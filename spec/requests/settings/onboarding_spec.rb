# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'settings/onboarding', type: :request do
  include ActiveSupport::Testing::TimeHelpers

  context 'when user is authenticated' do
    let!(:user) { create(:user) }

    before do
      sign_in user
    end

    describe 'PATCH /settings/onboarding' do
      it 'sets onboarding_completed to true' do
        patch settings_onboarding_path

        expect(response).to have_http_status(:ok)
        expect(user.reload.settings['onboarding_completed']).to be true
      end

      it 'is idempotent' do
        2.times { patch settings_onboarding_path }

        expect(response).to have_http_status(:ok)
        expect(user.reload.settings['onboarding_completed']).to be true
      end
    end

    describe 'POST /settings/onboarding/event' do
      before { allow(DawarichSettings).to receive(:self_hosted?).and_return(false) }

      def record_step(name, at:)
        travel_to(Time.zone.parse(at)) { post event_settings_onboarding_path, params: { name: } }
      end

      it 'records when the user first reached each onboarding step' do
        record_step('onboarding_shown', at: '2026-10-14 10:00:00 UTC')
        record_step('onboarding_import_selected', at: '2026-10-14 10:01:00 UTC')

        expect(response).to have_http_status(:no_content)
        expect(user.reload.settings['onboarding_events']).to eq(
          'onboarding_shown' => '2026-10-14T10:00:00Z',
          'onboarding_import_selected' => '2026-10-14T10:01:00Z'
        )
      end

      it 'keeps the first occurrence of a repeated step' do
        record_step('onboarding_skipped', at: '2026-10-14 10:00:00 UTC')
        record_step('onboarding_skipped', at: '2026-10-15 10:00:00 UTC')

        expect(user.reload.settings.dig('onboarding_events', 'onboarding_skipped')).to eq('2026-10-14T10:00:00Z')
      end

      it 'records nothing on self-hosted instances' do
        allow(DawarichSettings).to receive(:self_hosted?).and_return(true)

        post event_settings_onboarding_path, params: { name: 'onboarding_shown' }

        expect(response).to have_http_status(:no_content)
        expect(user.reload.settings).not_to have_key('onboarding_events')
      end

      it 'rejects unknown steps without touching settings' do
        post event_settings_onboarding_path, params: { name: 'onboarding_hacked' }

        expect(response).to have_http_status(:unprocessable_content)
        expect(user.reload.settings).not_to have_key('onboarding_events')
      end

      it 'keeps both the recorded step and the completion flag' do
        post event_settings_onboarding_path, params: { name: 'onboarding_skipped' }
        patch settings_onboarding_path

        expect(user.reload.settings).to include('onboarding_completed' => true)
        expect(user.settings['onboarding_events']).to have_key('onboarding_skipped')
      end
    end

    describe 'the onboarding modal on the map' do
      it 'tells the modal where to record steps on Cloud' do
        allow(DawarichSettings).to receive(:self_hosted?).and_return(false)

        get map_v2_path

        expect(response.body).to include(%(data-onboarding-modal-event-url-value="#{event_settings_onboarding_path}"))
      end

      it 'gives the modal nowhere to record steps on self-hosted instances' do
        allow(DawarichSettings).to receive(:self_hosted?).and_return(true)

        get map_v2_path

        expect(response.body).to include('data-onboarding-modal-event-url-value=""')
      end
    end

    describe 'POST /settings/onboarding/demo_data' do
      it 'creates demo data and redirects to map v2' do
        post demo_data_settings_onboarding_path

        expect(response).to have_http_status(:redirect)
        expect(response.location).to include('/map/v2', 'panel=timeline', 'date=')
      end

      it 'is idempotent and redirects to map v2' do
        post demo_data_settings_onboarding_path
        post demo_data_settings_onboarding_path

        expect(response).to have_http_status(:redirect)
        expect(response.location).to include('/map/v2', 'panel=timeline', 'date=')
      end

      context 'when user is on a non-UTC timezone' do
        let!(:user) { create(:user, settings: { 'timezone' => 'Europe/Berlin' }) }

        it 'uses the user timezone for start_at and end_at, not the Rails default' do
          post demo_data_settings_onboarding_path

          expect(response).to have_http_status(:redirect)
          expect(response.location).to match(/start_at=[^&]*(%2B02%3A00|%2B01%3A00)/)
          expect(response.location).to match(/end_at=[^&]*(%2B02%3A00|%2B01%3A00)/)
        end
      end
    end

    describe 'DELETE /settings/onboarding/demo_data' do
      it 'destroys demo data synchronously and redirects to root' do
        post demo_data_settings_onboarding_path

        delete demo_data_settings_onboarding_path

        expect(response).to redirect_to(root_path)
      end

      it 'handles missing demo data gracefully' do
        delete demo_data_settings_onboarding_path

        expect(response).to redirect_to(root_path)
      end

      it 'redirects to root with alert when destroy raises' do
        post demo_data_settings_onboarding_path
        allow_any_instance_of(Import).to receive(:destroy).and_raise(StandardError, 'boom')

        delete demo_data_settings_onboarding_path

        expect(response).to redirect_to(root_path)
        expect(flash[:alert]).to be_present
      end
    end
  end

  context 'when user is not authenticated' do
    it 'redirects to the sign in page' do
      patch settings_onboarding_path

      expect(response).to redirect_to(new_user_session_path)
    end
  end
end

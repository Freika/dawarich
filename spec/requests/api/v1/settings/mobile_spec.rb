# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Settings::Mobile', type: :request do
  let!(:user) { create(:user) }
  let!(:api_key) { user.api_key }

  describe 'GET /api/v1/settings/mobile' do
    it 'returns empty settings when none stored' do
      get "/api/v1/settings/mobile?api_key=#{api_key}"

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['settings']).to eq({})
      expect(response.parsed_body['updated_at']).to be_nil
    end

    it 'returns stored mobile settings with updated_at' do
      user.settings['mobile'] = {
        'tracking_mode' => 'significant',
        'updated_at' => '2026-07-01T10:00:00Z'
      }
      user.save!

      get "/api/v1/settings/mobile?api_key=#{api_key}"

      expect(response.parsed_body['settings']).to eq('tracking_mode' => 'significant')
      expect(response.parsed_body['updated_at']).to eq('2026-07-01T10:00:00Z')
    end

    it 'returns unauthorized without api key' do
      get '/api/v1/settings/mobile'

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'PATCH /api/v1/settings/mobile' do
    it 'stores permitted settings and stamps updated_at' do
      patch "/api/v1/settings/mobile?api_key=#{api_key}",
            params: { settings: { tracking_mode: 'significant', batch_size: 50, auto_start: false } }

      expect(response).to have_http_status(:success)

      mobile = user.reload.settings['mobile']
      expect(mobile['tracking_mode']).to eq('significant')
      expect(mobile['batch_size']).to eq(50)
      expect(mobile['auto_start']).to eq(false)
      expect(Time.iso8601(mobile['updated_at'])).to be_within(5.seconds).of(Time.current)
    end

    it 'returns the stored settings and updated_at' do
      patch "/api/v1/settings/mobile?api_key=#{api_key}",
            params: { settings: { batch_size: 300 } }

      expect(response.parsed_body['settings']['batch_size']).to eq(300)
      expect(response.parsed_body['updated_at']).to be_present
    end

    it 'merges with previously stored mobile settings' do
      patch "/api/v1/settings/mobile?api_key=#{api_key}",
            params: { settings: { tracking_mode: 'significant' } }
      patch "/api/v1/settings/mobile?api_key=#{api_key}",
            params: { settings: { batch_size: 10 } }

      mobile = user.reload.settings['mobile']
      expect(mobile['tracking_mode']).to eq('significant')
      expect(mobile['batch_size']).to eq(10)
    end

    it 'strips unknown keys' do
      patch "/api/v1/settings/mobile?api_key=#{api_key}",
            params: { settings: { tracking_mode: 'precise', bogus: 'nope' } }

      expect(user.reload.settings['mobile']).not_to have_key('bogus')
    end

    it 'drops invalid tracking_mode values' do
      patch "/api/v1/settings/mobile?api_key=#{api_key}",
            params: { settings: { tracking_mode: 'teleport', batch_size: 5 } }

      mobile = user.reload.settings['mobile']
      expect(mobile).not_to have_key('tracking_mode')
      expect(mobile['batch_size']).to eq(5)
    end

    it 'clamps numeric values' do
      patch "/api/v1/settings/mobile?api_key=#{api_key}",
            params: { settings: { batch_size: 99_999, distance_filter: 0 } }

      mobile = user.reload.settings['mobile']
      expect(mobile['batch_size']).to eq(1000)
      expect(mobile['distance_filter']).to eq(1)
    end

    it 'ignores blank numeric values instead of clamping them to the minimum' do
      patch "/api/v1/settings/mobile?api_key=#{api_key}",
            params: { settings: { distance_filter: 50 } }
      patch "/api/v1/settings/mobile?api_key=#{api_key}",
            params: { settings: { batch_size: 20, distance_filter: '' } }

      mobile = user.reload.settings['mobile']
      expect(mobile['batch_size']).to eq(20)
      expect(mobile['distance_filter']).to eq(50)
    end

    it 'casts boolean values' do
      patch "/api/v1/settings/mobile?api_key=#{api_key}",
            params: { settings: { upload_automatically: 'true' } }

      expect(user.reload.settings['mobile']['upload_automatically']).to eq(true)
    end

    it 'does not overwrite a stored boolean with a blank value' do
      patch "/api/v1/settings/mobile?api_key=#{api_key}",
            params: { settings: { upload_automatically: 'true' } }
      patch "/api/v1/settings/mobile?api_key=#{api_key}",
            params: { settings: { upload_automatically: '' } }

      expect(user.reload.settings['mobile']['upload_automatically']).to eq(true)
    end

    it 'does not touch non-mobile settings' do
      user.settings['route_opacity'] = 0.9
      user.save!

      patch "/api/v1/settings/mobile?api_key=#{api_key}",
            params: { settings: { batch_size: 5 } }

      expect(user.reload.settings['route_opacity']).to eq(0.9)
    end

    it 'rejects inactive users' do
      user.update(status: :inactive, active_until: 1.day.ago)

      patch "/api/v1/settings/mobile?api_key=#{api_key}",
            params: { settings: { batch_size: 5 } }

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'mobile namespace isolation' do
    it 'does not leak into the web settings response' do
      patch "/api/v1/settings/mobile?api_key=#{api_key}",
            params: { settings: { tracking_mode: 'significant' } }

      get "/api/v1/settings?api_key=#{api_key}"

      expect(response.parsed_body['settings']).not_to have_key('mobile')
    end
  end
end

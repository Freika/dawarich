# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Mobile settings concurrent writes', type: :request do
  let(:user) { create(:user) }
  let(:headers) { { 'Authorization' => "Bearer #{user.api_key}" } }

  # A second request commits between this request loading the user and merging
  # its own change into the settings column.
  def interleave_concurrent_write
    allow_any_instance_of(Api::V1::Settings::MobileController)
      .to receive(:sanitized_params).and_wrap_original do |original, *args|
        unless @interleaved
          @interleaved = true
          concurrent = User.find(user.id)
          concurrent.update!(
            settings: concurrent.settings.merge('maps' => { 'distance_unit' => 'mi' })
          )
        end
        original.call(*args)
      end
  end

  it 'does not discard a concurrent write to another settings section' do
    user.update!(settings: (user.settings || {}).merge('maps' => { 'distance_unit' => 'km' }))
    interleave_concurrent_write

    patch '/api/v1/settings/mobile',
          params: { settings: { batch_size: 300 } },
          headers: headers

    expect(response).to have_http_status(:ok)
    user.reload
    expect(user.settings.dig('mobile', 'batch_size')).to eq(300)
    expect(user.settings.dig('maps', 'distance_unit')).to eq('mi')
  end

  it 'does not discard a concurrent mobile field written by another device' do
    user.update!(settings: (user.settings || {}).merge('mobile' => { 'tracking_mode' => 'precise' }))
    allow_any_instance_of(Api::V1::Settings::MobileController)
      .to receive(:sanitized_params).and_wrap_original do |original, *args|
        unless @interleaved
          @interleaved = true
          concurrent = User.find(user.id)
          mobile = concurrent.settings['mobile'].merge('tracking_mode' => 'significant')
          concurrent.update!(settings: concurrent.settings.merge('mobile' => mobile))
        end
        original.call(*args)
      end

    patch '/api/v1/settings/mobile',
          params: { settings: { batch_size: 300 } },
          headers: headers

    user.reload
    expect(user.settings.dig('mobile', 'batch_size')).to eq(300)
    expect(user.settings.dig('mobile', 'tracking_mode')).to eq('significant')
  end
end

# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Geocoding::BackfillInstanceSettings, 'review regressions' do
  # `false.blank?` is true, so the old guard dropped use_https: false and the
  # registry default (true) took over — flipping a plain-HTTP Nominatim to
  # HTTPS the first time the flag was enabled.
  it 'carries use_https false across rather than dropping it' do
    user = create(:user)
    setting = user.service_settings.new(service: :geocoding, provider: 'nominatim',
                                        config: { 'host' => 'nominatim.internal', 'use_https' => false },
                                        active: true)
    setting.save!

    described_class.call

    expect(InstanceSetting.find_by(key: 'nominatim_api_use_https')&.value).to be(false)
  end

  # Driven through .call with real disagreeing rows rather than send() on a
  # private method: hand-building the signature tuple would keep passing if
  # `signature` ever gained or reordered a field while the log regained the key.
  it 'never writes a decrypted api key into the log when configurations disagree' do
    messages = []
    allow(Rails.logger).to receive(:warn) { |m| messages << m }

    a = create(:user).service_settings.new(service: :geocoding, provider: 'photon',
                                           config: { 'host' => 'a.example.com' }, active: true)
    a.api_key = 'PLAINTEXT-KEY-A'
    a.save!
    b = create(:user).service_settings.new(service: :geocoding, provider: 'photon',
                                           config: { 'host' => 'b.example.com' }, active: true)
    b.api_key = 'PLAINTEXT-KEY-B'
    b.save!

    described_class.call

    expect(messages.join).not_to include('PLAINTEXT-KEY')
    expect(messages.join).to include('[redacted]')
    expect(messages.join).to include('a.example.com')
    expect(InstanceSetting.where(key: 'photon_api_host')).to be_empty
  end
end

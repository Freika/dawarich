require 'rails_helper'

RSpec.describe Subscription::HandleRevenueCatWebhook do
  let(:user) { create(:user, status: :pending_payment) }

  def event(type, overrides = {})
    {
      'event' => {
        'type' => type,
        'app_user_id' => user.id.to_s,
        'product_id' => 'dawarich.pro.yearly',
        'expiration_at_ms' => 7.days.from_now.to_i * 1000,
        'store' => 'APP_STORE'
      }.merge(overrides)
    }
  end

  describe 'INITIAL_PURCHASE' do
    it 'transitions pending_payment user to trial on Apple IAP' do
      described_class.new(event('INITIAL_PURCHASE')).call
      user.reload
      expect(user.status).to eq('trial')
      expect(user.plan).to eq('pro')
      expect(user.subscription_source).to eq('apple_iap')
      expect(user.active_until).to be_within(5.seconds).of(7.days.from_now)
    end

    it 'maps product_id to plan correctly' do
      described_class.new(event('INITIAL_PURCHASE', 'product_id' => 'dawarich.lite.yearly')).call
      expect(user.reload.plan).to eq('lite')
    end

    it 'uses google_play for PLAY_STORE events' do
      described_class.new(event('INITIAL_PURCHASE', 'store' => 'PLAY_STORE')).call
      expect(user.reload.subscription_source).to eq('google_play')
    end
  end

  describe 'RENEWAL' do
    it 'sets status to active and extends active_until' do
      described_class.new(event('RENEWAL', 'expiration_at_ms' => 1.year.from_now.to_i * 1000)).call
      user.reload
      expect(user.status).to eq('active')
      expect(user.active_until).to be_within(5.seconds).of(1.year.from_now)
    end
  end

  describe 'CANCELLATION' do
    it 'marks the user cancelled but keeps entitlement until expiration' do
      user.update!(status: :active, subscription_source: :apple_iap, active_until: 10.days.from_now)
      described_class.new(event('CANCELLATION')).call
      # User remains active until active_until passes; CANCELLATION just signals intent to not renew.
      expect(user.reload.status).to eq('active')
    end
  end

  describe 'EXPIRATION' do
    it 'demotes the user to inactive when sub expires' do
      user.update!(status: :active, subscription_source: :apple_iap)
      described_class.new(event('EXPIRATION')).call
      expect(user.reload.status).to eq('inactive')
    end
  end

  describe 'cross-platform conflict' do
    it 'does not overwrite a paddle-sourced active sub with an IAP event' do
      user.update!(status: :active, subscription_source: :paddle, active_until: 1.year.from_now)
      original_until = user.active_until

      described_class.new(event('INITIAL_PURCHASE')).call

      user.reload
      expect(user.subscription_source).to eq('paddle')
      expect(user.active_until).to be_within(5.seconds).of(original_until)
    end
  end

  describe 'unknown user' do
    it 'raises to trigger retry' do
      expect {
        described_class.new(event('INITIAL_PURCHASE', 'app_user_id' => '99999999')).call
      }.to raise_error(described_class::UnknownUser)
    end
  end

  describe 'unknown event type' do
    it 'is a no-op' do
      expect {
        described_class.new(event('SOMETHING_WEIRD')).call
      }.not_to change { user.reload.attributes }
    end
  end
end

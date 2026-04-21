# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Subscription::HandleRevenueCatWebhook do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { create(:user, status: :pending_payment) }

  def event(type, overrides = {})
    {
      'event' => {
        'id' => SecureRandom.uuid,
        'type' => type,
        'app_user_id' => user.id.to_s,
        'product_id' => 'dawarich.pro.yearly',
        'expiration_at_ms' => 7.days.from_now.to_i * 1000,
        'event_timestamp_ms' => Time.current.to_i * 1000,
        'store' => 'APP_STORE',
        'period_type' => 'TRIAL'
      }.merge(overrides)
    }
  end

  before { Rails.cache.clear }

  describe 'INITIAL_PURCHASE' do
    it 'transitions pending_payment user to trial on Apple IAP with TRIAL period_type' do
      described_class.new(event('INITIAL_PURCHASE', 'period_type' => 'TRIAL')).call
      user.reload
      expect(user.status).to eq('trial')
      expect(user.plan).to eq('pro')
      expect(user.subscription_source).to eq('apple_iap')
      expect(user.active_until).to be_within(5.seconds).of(7.days.from_now)
    end

    it 'transitions to active when period_type is NORMAL' do
      described_class.new(event('INITIAL_PURCHASE', 'period_type' => 'NORMAL')).call
      expect(user.reload.status).to eq('active')
    end

    it 'maps product_id to plan correctly' do
      described_class.new(event('INITIAL_PURCHASE', 'product_id' => 'dawarich.lite.yearly')).call
      expect(user.reload.plan).to eq('lite')
    end

    it 'uses google_play for PLAY_STORE events' do
      described_class.new(event('INITIAL_PURCHASE', 'store' => 'PLAY_STORE')).call
      expect(user.reload.subscription_source).to eq('google_play')
    end

    it 'raises UnknownProductId for unknown product instead of silently downgrading' do
      expect do
        described_class.new(event('INITIAL_PURCHASE', 'product_id' => 'dawarich.unknown')).call
      end.to raise_error(Subscription::HandleRevenueCatWebhook::UnknownProductId)
    end

    it 'raises when store is missing (does not default to apple_iap)' do
      expect do
        described_class.new(event('INITIAL_PURCHASE', 'store' => nil)).call
      end.to raise_error(KeyError)
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
      expect(user.reload.status).to eq('active')
    end
  end

  describe 'EXPIRATION' do
    it 'demotes the user to inactive when sub expires' do
      user.update!(status: :active, subscription_source: :apple_iap, active_until: 1.hour.ago)
      described_class.new(event('EXPIRATION', 'expiration_at_ms' => 1.hour.ago.to_i * 1000)).call
      expect(user.reload.status).to eq('inactive')
    end

    it 'does not demote when stale EXPIRATION arrives after a more recent RENEWAL' do
      user.update!(status: :active, subscription_source: :apple_iap, active_until: 1.year.from_now)

      # Stale EXPIRATION event (timestamp older than current active_until)
      stale_event = event(
        'EXPIRATION',
        'event_timestamp_ms' => 1.month.ago.to_i * 1000,
        'expiration_at_ms' => 1.month.ago.to_i * 1000
      )
      described_class.new(stale_event).call

      user.reload
      expect(user.status).to eq('active')
      expect(user.active_until).to be_within(5.seconds).of(1.year.from_now)
    end

    it 'does not clobber active_until with an older expiration timestamp' do
      user.update!(status: :active, subscription_source: :apple_iap, active_until: 1.year.from_now)

      # Event with fresh timestamp but older expiration
      ev = event(
        'EXPIRATION',
        'event_timestamp_ms' => (2.years.from_now.to_i * 1000),
        'expiration_at_ms' => (1.month.from_now.to_i * 1000)
      )
      described_class.new(ev).call

      user.reload
      expect(user.active_until).to be_within(5.seconds).of(1.year.from_now)
    end
  end

  describe 'idempotency' do
    it 'is a no-op for a duplicate event id' do
      first_event = event('INITIAL_PURCHASE', 'period_type' => 'NORMAL')
      described_class.new(first_event).call

      user.reload
      original_updated_at = user.updated_at

      # Replay the same event - should be a no-op
      travel 1.minute do
        described_class.new(first_event).call
        user.reload
        expect(user.updated_at).to be_within(1.second).of(original_updated_at)
      end
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
      expect do
        described_class.new(event('INITIAL_PURCHASE', 'app_user_id' => '99999999')).call
      end.to raise_error(described_class::UnknownUser)
    end
  end

  describe 'unknown event type' do
    it 'is a no-op' do
      expect do
        described_class.new(event('SOMETHING_WEIRD')).call
      end.not_to(change { user.reload.attributes })
    end
  end
end

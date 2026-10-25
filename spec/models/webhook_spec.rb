# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Webhook do
  let(:user) { create(:user) }
  let(:place) { create(:place, :geofence, user:) }

  it 'generates a secret on create' do
    expect(create(:webhook, user:).secret).to match(/\A\h{64}\z/)
  end

  it 'never serializes the secret' do
    expect(create(:webhook, user:).as_json).not_to have_key('secret')
  end

  describe '#health' do
    it 'is inactive when switched off, failing after a failed delivery and active otherwise' do
      expect(build(:webhook, user:, active: false, consecutive_failures: 5).health).to eq(:inactive)
      expect(build(:webhook, user:, consecutive_failures: 1).health).to eq(:failing)
      expect(build(:webhook, user:).health).to eq(:active)
    end
  end

  describe '#subscribed_to?' do
    it 'follows the active flag, event types and the place filter' do
      other = create(:place, :geofence, user:)

      expect(build(:webhook, user:).subscribed_to?(place:, event_type: 'enter')).to be(true)
      expect(build(:webhook, user:, active: false).subscribed_to?(place:, event_type: 'enter')).to be(false)
      expect(build(:webhook, user:, event_types: [1]).subscribed_to?(place:, event_type: 'enter')).to be(false)
      expect(build(:webhook, user:, place_ids: [other.id]).subscribed_to?(place:, event_type: 'leave')).to be(false)
      expect(build(:webhook, user:, place_ids: [place.id]).subscribed_to?(place:, event_type: 'leave')).to be(true)
    end
  end

  describe 'url' do
    def webhook_with(url)
      build(:webhook, user:, url:)
    end

    context 'on cloud' do
      before { allow(DawarichSettings).to receive(:self_hosted?).and_return(false) }

      it 'accepts a public https address and rejects plain http, private and mapped addresses' do
        stub_host_addresses('hooks.example.org', '203.0.113.20')
        stub_host_addresses('internal.example.org', '10.0.0.5')

        expect(webhook_with('https://hooks.example.org/x')).to be_valid
        expect(webhook_with('http://hooks.example.org/x')).not_to be_valid
        expect(webhook_with('https://10.0.0.1/x')).not_to be_valid
        expect(webhook_with('https://[::ffff:127.0.0.1]/x')).not_to be_valid
        expect(webhook_with('https://internal.example.org/x')).not_to be_valid
      end
    end

    context 'when self-hosted' do
      before { allow(DawarichSettings).to receive(:self_hosted?).and_return(true) }

      it 'accepts a home network address but never the cloud metadata address' do
        expect(webhook_with('http://192.168.1.10:8123/api/webhook/x')).to be_valid
        expect(webhook_with('http://169.254.169.254/latest')).not_to be_valid
      end
    end

    it 'reports a host that does not resolve' do
      stub_unresolvable_host('nowhere.invalid')

      expect(webhook_with('https://nowhere.invalid/x')).not_to be_valid
    end
  end

  describe 'filters' do
    it 'needs at least one known event type' do
      expect(build(:webhook, user:, event_types: [])).not_to be_valid
      expect(build(:webhook, user:, event_types: [7])).not_to be_valid
      expect(build(:webhook, user:, event_types: [1])).to be_valid
    end

    it 'understands event type names and rejects unknown ones' do
      expect(build(:webhook, user:, event_types: %w[leave]).event_types).to eq([1])
      expect(build(:webhook, user:, event_types: %w[linger])).not_to be_valid
    end

    it 'accepts only the user\'s own places' do
      expect(build(:webhook, user:, place_ids: [create(:place, :geofence).id])).not_to be_valid
      expect(build(:webhook, user:, place_ids: [place.id])).to be_valid
    end
  end

  it 'allows at most ten webhooks per user' do
    create_list(:webhook, 10, user:)

    expect(build(:webhook, user:)).not_to be_valid
  end

  it 'resets the failure count when re-activated' do
    webhook = create(:webhook, user:, active: false, consecutive_failures: 5)

    webhook.update!(active: true)

    expect(webhook.reload.consecutive_failures).to eq(0)
  end

  it 'regenerates its secret' do
    webhook = create(:webhook, user:)

    expect { webhook.regenerate_secret! }.to(change { webhook.reload.secret })
  end
end

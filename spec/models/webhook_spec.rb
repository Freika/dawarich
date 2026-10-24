# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Webhook do
  let(:user) { create(:user) }
  let(:area) { create(:area, user:) }

  it 'generates a secret on create' do
    expect(create(:webhook, user:).secret).to match(/\A\h{64}\z/)
  end

  it 'never serializes the secret' do
    expect(create(:webhook, user:).as_json).not_to have_key('secret')
  end

  describe '#subscribed_to?' do
    it 'follows the active flag, event types and the area filter' do
      other = create(:area, user:)

      expect(build(:webhook, user:).subscribed_to?(area:, event_type: 'enter')).to be(true)
      expect(build(:webhook, user:, active: false).subscribed_to?(area:, event_type: 'enter')).to be(false)
      expect(build(:webhook, user:, event_types: [1]).subscribed_to?(area:, event_type: 'enter')).to be(false)
      expect(build(:webhook, user:, area_ids: [other.id]).subscribed_to?(area:, event_type: 'leave')).to be(false)
      expect(build(:webhook, user:, area_ids: [area.id]).subscribed_to?(area:, event_type: 'leave')).to be(true)
    end
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

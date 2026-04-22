# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Webhook, type: :model do
  describe 'validations' do
    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_presence_of(:url) }
  end

  describe 'associations' do
    it { is_expected.to belong_to(:user) }
    it { is_expected.to have_many(:webhook_deliveries).dependent(:destroy) }
  end

  describe 'secret generation' do
    it 'generates a secret on create when missing' do
      webhook = build(:webhook, secret: nil)
      webhook.valid?
      expect(webhook.secret).to be_present
      expect(webhook.secret.length).to be >= 32
    end

    it 'does not overwrite an existing secret' do
      webhook = build(:webhook, secret: 'preset-secret-value')
      webhook.valid?
      expect(webhook.secret).to eq('preset-secret-value')
    end
  end

  describe '#regenerate_secret!' do
    it 'replaces the existing secret' do
      webhook = create(:webhook)
      old = webhook.secret
      webhook.regenerate_secret!
      expect(webhook.secret).not_to eq(old)
    end
  end

  describe 'URL validation' do
    before { allow(DawarichSettings).to receive(:self_hosted?).and_return(false) }

    it 'rejects private IPs on cloud' do
      w = build(:webhook, url: 'https://192.168.1.1/hook')
      expect(w).not_to be_valid
      expect(w.errors[:url]).to be_present
    end

    it 'accepts https public URLs' do
      expect(build(:webhook, url: 'https://example.com/hook')).to be_valid
    end
  end

  describe '#subscribed_to?' do
    let(:user) { create(:user) }
    let(:area) { create(:area, user: user) }
    let(:webhook) { build(:webhook, user: user, area_ids: area_ids, event_types: event_types) }

    context 'when area_ids is empty (all areas)' do
      let(:area_ids) { [] }
      let(:event_types) { [0] }

      it 'matches any area' do
        expect(webhook.subscribed_to?(area: area, event_type: 'enter')).to be true
      end
    end

    context 'when area_ids contains the area' do
      let(:area_ids) { [area.id] }
      let(:event_types) { [0] }

      it 'matches' do
        expect(webhook.subscribed_to?(area: area, event_type: 'enter')).to be true
      end
    end

    context 'when event_type is not subscribed' do
      let(:area_ids) { [] }
      let(:event_types) { [0] }

      it 'does not match' do
        expect(webhook.subscribed_to?(area: area, event_type: 'leave')).to be false
      end
    end

    context 'when webhook is inactive' do
      let(:area_ids) { [] }
      let(:event_types) { [0] }

      it 'does not match' do
        webhook.active = false
        expect(webhook.subscribed_to?(area: area, event_type: 'enter')).to be false
      end
    end
  end
end

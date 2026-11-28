# frozen_string_literal: true

require 'rails_helper'

RSpec.describe WebhookPolicy do
  let(:user) { create(:user) }
  let(:webhook) { build(:webhook, user:) }

  it 'lets the owner manage the webhook' do
    expect(described_class.new(user, webhook)).to have_attributes(create?: true, update?: true, destroy?: true)
  end

  it 'never lets someone else touch it' do
    expect(described_class.new(create(:user), webhook).update?).to be(false)
  end

  context 'on cloud' do
    before { allow(DawarichSettings).to receive(:self_hosted?).and_return(false) }

    it 'refuses Lite and allows Pro and Family' do
      paid = { active_until: 1.year.from_now }

      expect(described_class.new(create(:user, plan: :lite), Webhook).create?).to be(false)
      expect(described_class.new(create(:user, plan: :pro, **paid), Webhook).create?).to be(true)
      expect(described_class.new(create(:user, plan: :family, **paid), Webhook).create?).to be(true)
    end
  end
end

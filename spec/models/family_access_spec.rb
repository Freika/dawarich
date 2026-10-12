# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Family, '#access_live?' do
  let(:owner) { create(:user, plan: :family, status: :active, active_until: 1.year.from_now, skip_auto_trial: true) }
  let(:family) { create(:family, creator: owner) }
  let!(:owner_membership) { create(:family_membership, :owner, user: owner, family: family) }

  context 'on cloud' do
    before { allow(DawarichSettings).to receive(:self_hosted?).and_return(false) }

    it 'is live while the recorded period runs' do
      family.update!(access_until: 1.day.from_now)

      expect(family.access_live?).to be true
    end

    it 'is over once the recorded period passes' do
      family.update!(access_until: 1.day.ago)

      expect(family.access_live?).to be false
    end

    it 'falls back to the owner plan and period when no period is recorded' do
      expect(family.access_live?).to be true
    end

    it 'is over when the fallback owner has left the family plan' do
      owner.update!(plan: :pro)

      expect(family.reload.access_live?).to be false
    end

    it 'is over when the fallback owner period has passed' do
      owner.update!(active_until: 1.day.ago)

      expect(family.reload.access_live?).to be false
    end

    it 'prefers the recorded period over the owner current plan' do
      family.update!(access_until: 1.day.from_now)
      owner.update!(plan: :pro)

      expect(family.reload.access_live?).to be true
    end
  end

  it 'is always live on self-hosted instances' do
    allow(DawarichSettings).to receive(:self_hosted?).and_return(true)
    family.update!(access_until: 1.day.ago)

    expect(family.access_live?).to be true
  end
end

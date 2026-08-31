# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Family members are treated as entitled users', type: :model do
  before { allow(DawarichSettings).to receive(:self_hosted?).and_return(false) }

  let(:owner) do
    create(:user, plan: :family, status: :trial, active_until: 7.days.from_now, skip_auto_trial: true)
  end
  let(:family) { create(:family, creator: owner) }
  let!(:owner_membership) { create(:family_membership, :owner, user: owner, family: family) }
  let(:member) do
    create(:user, plan: :lite, status: :inactive, active_until: nil, skip_auto_trial: true).tap do |user|
      create(:family_membership, user: user, family: family)
    end
  end

  describe 'background work fan-out' do
    it 'includes a member whose owner is paying' do
      expect(User.active_or_trial).to include(member)
    end

    it 'still includes the owner' do
      member

      expect(User.active_or_trial).to include(owner)
    end

    it 'drops the member once the owner lapses' do
      member
      owner.update!(status: :inactive, active_until: 1.day.ago)

      expect(User.active_or_trial).not_to include(member)
    end

    it 'drops the member once the owner leaves the family plan' do
      member
      owner.update!(plan: :pro)

      expect(User.active_or_trial).not_to include(member)
    end

    it 'still excludes an unrelated inactive user' do
      stranger = create(:user, status: :inactive, active_until: nil, skip_auto_trial: true)

      expect(User.active_or_trial).not_to include(stranger)
    end

    it 'excludes a soft-deleted member' do
      member.update!(deleted_at: Time.current)

      expect(User.active_or_trial).not_to include(member)
    end
  end

  describe 'subscription prompts' do
    it 'stops nagging a member to subscribe' do
      expect(member.can_subscribe?).to be false
    end

    it 'starts nagging again once the owner lapses' do
      member
      owner.update!(status: :inactive, active_until: 1.day.ago)

      expect(member.reload.can_subscribe?).to be true
    end

    it 'leaves the owner able to convert their own trial' do
      member

      expect(owner.can_subscribe?).to be true
    end

    it 'leaves an unrelated lapsed user able to subscribe' do
      stranger = create(:user, status: :inactive, active_until: nil, skip_auto_trial: true)

      expect(stranger.can_subscribe?).to be true
    end
  end

  describe 'access still comes from the owner, not from stored state' do
    it 'gives the member family access while the owner pays' do
      expect(member.entitlements.effective_plan).to eq(:family)
    end

    it 'drops the member to their own lite plan when the owner lapses' do
      member
      owner.update!(status: :inactive, active_until: 1.day.ago)

      expect(member.reload.entitlements.effective_plan).to eq(:lite)
    end
  end
end

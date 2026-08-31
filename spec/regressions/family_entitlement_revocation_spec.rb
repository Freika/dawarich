# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Family entitlement revocation', type: :model do
  before do
    allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
    ActiveJob::Base.queue_adapter = :test
  end

  let(:owner) do
    create(:user, plan: :family, status: :active, active_until: 1.year.from_now, skip_auto_trial: true)
  end
  let(:family) { create(:family, creator: owner) }
  let!(:owner_membership) { create(:family_membership, :owner, user: owner, family: family) }

  def add_member(**attrs)
    create(:user, { plan: :lite, status: :inactive, active_until: nil, skip_auto_trial: true }.merge(attrs))
      .tap { |user| create(:family_membership, user: user, family: family) }
  end

  describe 'a member who leaves while the plan is still running' do
    let!(:member) { add_member }

    before { Families::SyncMembers.new(family: family.reload).call }

    it 'holds the mirrored plan while still a member' do
      expect(member.reload).to be_pro
      expect(member.reload.active_until).to be_future
    end

    it 'loses the mirrored subscription on leaving' do
      member.reload.family_membership.destroy!

      expect(member.reload.active_until).to be_nil
      expect(member.reload).to be_inactive
      expect(member.reload).to be_lite
    end

    it 'loses it when the owner removes them too' do
      Family::Membership.find_by(user_id: member.id).destroy!

      expect(member.reload.active_until).to be_nil
    end
  end

  describe 'a member who pays for themselves' do
    let!(:member) do
      add_member(plan: :pro, status: :active, active_until: 2.years.from_now, subscription_source: :paddle)
    end

    it 'keeps their own subscription when leaving' do
      Family::Membership.find_by(user_id: member.id).destroy!

      expect(member.reload).to be_active
      expect(member.reload.active_until).to be_future
    end
  end

  describe 'the owner dissolving their own family' do
    it 'keeps the owner subscription intact' do
      owner_membership.destroy!

      expect(owner.reload).to be_active
      expect(owner.reload).to be_family
      expect(owner.reload.active_until).to be_future
    end
  end

  describe 'when the owner moves off the family plan but their period is still paid' do
    let!(:member) { add_member }

    before { Families::SyncMembers.new(family: family.reload).call }

    it 'keeps the member on until the period the owner already paid for ends' do
      owner.update!(plan: :pro)

      Families::SyncMembers.new(family: family.reload).call

      expect(member.reload).to be_active
      expect(member.reload.active_until).to be_future
    end

    it 'leaves the member family access intact until then' do
      owner.update!(plan: :pro)

      Families::SyncMembers.new(family: family.reload).call

      expect(member.reload.entitlements.families?).to be true
    end

    it 'lapses the member once that paid period runs out' do
      owner.update!(plan: :pro)
      Families::SyncMembers.new(family: family.reload).call
      family.reload.update!(access_until: 1.day.ago)

      Families::SyncMembers.new(family: family.reload).call

      expect(member.reload).to be_inactive
      expect(member.reload.active_until).to be_past
    end

    it 'does not extend the family when the owner renews on a non-family plan' do
      owner.update!(plan: :pro)
      Families::SyncMembers.new(family: family.reload).call
      family.reload.update!(access_until: 1.day.ago)
      owner.update!(active_until: 1.year.from_now)

      Families::SyncMembers.new(family: family.reload).call

      expect(member.reload).to be_inactive
    end
  end
end

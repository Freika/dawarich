# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Family invitation subscription synchronization' do
  let(:owner) { create(:user, plan: :family, active_until: 1.month.from_now, status: :active, skip_auto_trial: true) }
  let(:family) { create(:family, creator: owner, access_until: owner.active_until) }
  let!(:owner_membership) { create(:family_membership, :owner, family: family, user: owner) }
  let(:invitee) { create(:user, plan: :lite, status: :inactive, skip_auto_trial: true) }
  let!(:invitation) { create(:family_invitation, family: family, invited_by: owner, email: invitee.email) }
  let(:service) { Families::AcceptInvitation.new(invitation: invitation, user: invitee) }

  before { allow(DawarichSettings).to receive(:self_hosted?).and_return(false) }

  %i[family lite].each do |plan|
    it "rejects an expired owner with plan #{plan} before the queued sync runs" do
      owner.update!(plan: plan, status: :inactive, active_until: 1.day.ago)

      expect { expect(service.call).to be(false) }.not_to change(Family::Membership, :count)
      expect(invitation.reload).to be_pending
      expect(invitee.reload).to be_lite
      expect(invitee.notifications).not_to exist
      expect(Families::LapseNotificationJob).not_to have_been_enqueued
      expect(family.reload.access_until).to be_past
    end
  end

  it 'accepts a renewed family owner before the queued sync runs' do
    family.update!(access_until: 1.day.ago)

    expect(service.call).to be(true)

    expect(invitation.reload).to be_accepted
    expect(invitee.reload).to be_active
    expect(invitee).to be_pro
    expect(invitee.active_until).to be_within(1.second).of(owner.active_until)
    expect(Families::LapseNotificationJob).not_to have_been_enqueued
  end

  it 'keeps the recorded paid-through period after a downgrade without extending it' do
    paid_until = family.access_until
    owner.update!(plan: :pro, active_until: 1.year.from_now)

    expect(service.call).to be(true)
    expect(invitee.reload.active_until).to be_within(1.second).of(paid_until)
  end

  it 'keeps paid access if a callback omits the expiry date' do
    paid_until = family.access_until
    owner.update!(active_until: nil)

    expect(service.call).to be(true)
    expect(invitee.reload.active_until).to be_within(1.second).of(paid_until)
  end

  it 'also clears stale access when the background sync sees an expired downgrade' do
    owner.update!(plan: :lite, status: :inactive, active_until: 1.day.ago)

    Families::SyncMembers.new(family: family).call

    expect(family.reload.access_until).to be_past
    expect(family.access_live?).to be(false)
  end
end

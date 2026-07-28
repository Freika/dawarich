# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Families::Memberships::Destroy do
  let(:user) { create(:user) }
  let(:family) { create(:family, creator: user) }
  let(:service) { described_class.new(user: user) }

  describe '#call' do
    context 'when user is a member (not owner)' do
      let(:member) { create(:user) }
      let!(:owner_membership) { create(:family_membership, user: user, family: family, role: :owner) }
      let!(:member_membership) { create(:family_membership, user: member, family: family, role: :member) }
      let(:service) { described_class.new(user: member) }

      it 'removes the membership' do
        result = service.call
        expect(result).to be_truthy, "Expected service to succeed but got error: #{service.error_message}"
        expect(Family::Membership.count).to eq(1) # Only owner should remain
        expect(member.reload.family_membership).to be_nil
      end

      it 'sends notification to member who left' do
        expect { service.call }.to change(Notification, :count).by(2)

        member_notification = member.notifications.last
        expect(member_notification.title).to eq('Left Family')
        expect(member_notification.content).to include(family.name)
      end

      it 'sends notification to family owner' do
        service.call

        owner_notification = user.notifications.last
        expect(owner_notification.title).to eq('Family Member Left')
        expect(owner_notification.content).to include(member.email)
        expect(owner_notification.content).to include(family.name)
      end

      it 'returns true' do
        expect(service.call).to be true
      end
    end

    context 'effective access lifecycle (cloud, family-plan owner)' do
      let(:user) { create(:user, plan: :family, skip_auto_trial: true) }
      let(:family) { create(:family, creator: user) }
      let(:member) { create(:user, plan: :lite, skip_auto_trial: true) }
      let!(:owner_membership) { create(:family_membership, user: user, family: family, role: :owner) }
      let!(:member_membership) { create(:family_membership, user: member, family: family, role: :member) }
      let(:service) { described_class.new(user: user, member_to_remove: member) }

      before { allow(DawarichSettings).to receive(:self_hosted?).and_return(false) }

      it 'revokes full access when the member is removed, without deleting their data' do
        recent_point = create(:point, user: member, timestamp: 1.month.ago.to_i)
        old_point = create(:point, user: member, timestamp: 2.years.ago.to_i)

        expect(member.full_access?).to be true

        service.call
        member.reload

        expect(member.full_access?).to be false
        expect(member.plan_restricted?).to be true
        expect(member.points).to include(recent_point, old_point)
        expect(member.scoped_points).to include(recent_point)
        expect(member.scoped_points).not_to include(old_point)
      end
    end

    context 'when user is family owner with no other members' do
      let!(:membership) { create(:family_membership, user: user, family: family, role: :owner) }

      it 'prevents owner from leaving' do
        expect { service.call }.not_to change(Family::Membership, :count)
        expect(user.reload.family_membership).to be_present
      end

      it 'does not delete the family' do
        expect { service.call }.not_to change(Family, :count)
      end

      it 'returns false' do
        expect(service.call).to be false
      end

      it 'sets error message' do
        service.call
        expect(service.error_message).to include('cannot remove their own membership')
      end
    end

    context 'when user is family owner with other members' do
      let(:member) { create(:user) }
      let!(:owner_membership) { create(:family_membership, user: user, family: family, role: :owner) }
      let!(:member_membership) { create(:family_membership, user: member, family: family, role: :member) }

      it 'returns false' do
        expect(service.call).to be false
      end

      it 'does not remove membership' do
        expect { service.call }.not_to change(Family::Membership, :count)
        expect(user.reload.family_membership).to be_present
      end
    end

    context 'when user is not in a family' do
      it 'returns false' do
        expect(service.call).to be false
      end

      it 'does not create any notifications' do
        expect { service.call }.not_to change(Notification, :count)
      end
    end
  end
end

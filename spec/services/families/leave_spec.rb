# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Families::Leave do
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
        expect(FamilyMembership.count).to eq(1) # Only owner should remain
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

    context 'when user is family owner with no other members' do
      let!(:membership) { create(:family_membership, user: user, family: family, role: :owner) }

      it 'removes the membership' do
        expect { service.call }.to change(FamilyMembership, :count).by(-1)
        expect(user.reload.family_membership).to be_nil
      end

      it 'deletes the family' do
        expect { service.call }.to change(Family, :count).by(-1)
      end

      it 'returns true' do
        expect(service.call).to be true
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
        expect { service.call }.not_to change(FamilyMembership, :count)
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

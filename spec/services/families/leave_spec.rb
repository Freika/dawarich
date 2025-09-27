# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Families::Leave do
  let(:user) { create(:user) }
  let(:family) { create(:family, creator: user) }
  let(:service) { described_class.new(user: user) }

  describe '#call' do
    context 'when user is a member (not owner)' do
      let(:member) { create(:user) }
      let!(:membership) { create(:family_membership, user: member, family: family, role: :member) }
      let(:service) { described_class.new(user: member) }

      it 'removes the membership' do
        expect { service.call }.to change(FamilyMembership, :count).by(-1)
        expect(member.reload.family_membership).to be_nil
      end

      it 'sends notification' do
        expect { service.call }.to change(Notification, :count).by(1)
        notification = Notification.last
        expect(notification.user).to eq(member)
        expect(notification.title).to eq('Left Family')
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

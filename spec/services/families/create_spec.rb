# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Families::Create do
  let(:user) { create(:user) }
  let(:service) { described_class.new(user: user, name: 'Test Family') }

  describe '#call' do
    context 'when user is not in a family' do
      it 'creates a family successfully' do
        expect { service.call }.to change(Family, :count).by(1)
        expect(service.family.name).to eq('Test Family')
        expect(service.family.creator).to eq(user)
      end

      it 'creates owner membership' do
        service.call
        membership = user.family_membership
        expect(membership.role).to eq('owner')
        expect(membership.family).to eq(service.family)
      end

      it 'returns true on success' do
        expect(service.call).to be true
      end
    end

    context 'when user is already in a family' do
      before { create(:family_membership, user: user) }

      it 'returns false' do
        expect(service.call).to be false
      end

      it 'does not create a family' do
        expect { service.call }.not_to change(Family, :count)
      end

      it 'does not create a membership' do
        expect { service.call }.not_to change(FamilyMembership, :count)
      end
    end
  end
end

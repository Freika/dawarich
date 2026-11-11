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
        membership = user.reload.family_membership
        expect(membership.role).to eq('owner')
        expect(membership.family).to eq(service.family)
      end

      it 'returns true on success' do
        expect(service.call).to be true
      end

      it 'does not notify the creator, who is already told by the page' do
        expect { service.call }.not_to change(Notification, :count)
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
        expect { service.call }.not_to change(Family::Membership, :count)
      end

      it 'sets appropriate error message' do
        service.call
        expect(service.error_message).to eq('You must leave your current family before creating a new one')
      end
    end

    context 'when user has already created a family before' do
      before do
        # User creates and then deletes their family membership, but family still exists
        old_family = create(:family, creator: user)
        membership = create(:family_membership, user: user, family: old_family, role: :owner)
        membership.destroy! # User leaves the family but family still exists
        user.reload # Ensure user association is refreshed
      end

      it 'returns false' do
        expect(service.call).to be false
      end

      it 'does not create a family' do
        expect { service.call }.not_to change(Family, :count)
      end

      it 'does not create a membership' do
        expect { service.call }.not_to change(Family::Membership, :count)
      end

      it 'sets appropriate error message' do
        service.call
        expect(service.error_message).to eq('You have already created a family. Each user can only create one family')
      end
    end

    context 'when cloud and the user is not on the family plan' do
      let(:user) { create(:user, plan: :pro, skip_auto_trial: true) }

      before { allow(DawarichSettings).to receive(:self_hosted?).and_return(false) }

      it 'returns false and does not create a family' do
        expect(service.call).to be false
        expect { service.call }.not_to change(Family, :count)
        expect(service.error_message).to eq('Family feature requires an active subscription')
      end
    end

    context 'when cloud and the user is on the family plan' do
      let(:user) { create(:user, plan: :family, skip_auto_trial: true) }

      before { allow(DawarichSettings).to receive(:self_hosted?).and_return(false) }

      it 'creates a family' do
        expect { service.call }.to change(Family, :count).by(1)
      end
    end
  end

  describe '#error_code' do
    it 'is nil after a successful call' do
      service.call
      expect(service.error_code).to be_nil
    end

    it 'is invalid_name for a blank name' do
      service = described_class.new(user: user, name: '  ')
      service.call
      expect(service.error_code).to eq(:invalid_name)
    end

    it 'is invalid_name for a name over 50 characters' do
      service = described_class.new(user: user, name: 'a' * 51)
      service.call
      expect(service.error_code).to eq(:invalid_name)
    end

    it 'is already_in_family for a member of a family' do
      create(:family_membership, user: user)
      service.call
      expect(service.error_code).to eq(:already_in_family)
    end

    it 'is family_already_created for a user who created a family before' do
      create(:family, creator: user)
      service.call
      expect(service.error_code).to eq(:family_already_created)
    end

    it 'is family_plan_required on cloud without the family plan' do
      allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
      user.update!(plan: :pro)
      service.call
      expect(service.error_code).to eq(:family_plan_required)
    end

    [
      ActiveRecord::RecordInvalid.new,
      ActiveRecord::RecordNotUnique.new('duplicate'),
      StandardError.new('boom')
    ].each do |error|
      it "is unexpected_error when #{error.class} is raised" do
        allow(Family).to receive(:create!).and_raise(error)
        allow(ExceptionReporter).to receive(:call)
        expect(service.call).to be false
        expect(service.error_code).to eq(:unexpected_error)
      end
    end
  end
end

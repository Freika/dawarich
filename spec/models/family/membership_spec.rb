# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Family::Membership, type: :model do
  describe 'associations' do
    it { is_expected.to belong_to(:family) }
    it { is_expected.to belong_to(:user) }
  end

  describe 'validations' do
    subject { build(:family_membership) }

    it { is_expected.to validate_presence_of(:user_id) }
    it { is_expected.to validate_uniqueness_of(:user_id) }
    it { is_expected.to validate_presence_of(:role) }
  end

  describe 'enums' do
    it { is_expected.to define_enum_for(:role).with_values(owner: 0, member: 1) }
  end

  describe 'one family per user constraint' do
    let(:user) { create(:user) }
    let(:family1) { create(:family) }
    let(:family2) { create(:family) }

    it 'allows a user to be in one family' do
      membership1 = build(:family_membership, family: family1, user: user)
      expect(membership1).to be_valid
    end

    it 'prevents a user from being in multiple families' do
      create(:family_membership, family: family1, user: user)
      membership2 = build(:family_membership, family: family2, user: user)

      expect(membership2).not_to be_valid
      expect(membership2.errors[:user_id]).to include('has already been taken')
    end
  end

  describe 'role assignment' do
    let(:family) { create(:family) }

    context 'when created as owner' do
      let(:membership) { create(:family_membership, :owner, family: family) }

      it 'can be created' do
        expect(membership.role).to eq('owner')
        expect(membership.owner?).to be true
      end
    end

    context 'when created as member' do
      let(:membership) { create(:family_membership, family: family, role: :member) }

      it 'can be created' do
        expect(membership.role).to eq('member')
        expect(membership.member?).to be true
      end
    end

    it 'defaults to member role' do
      membership = create(:family_membership, family: family)
      expect(membership.role).to eq('member')
    end
  end
end

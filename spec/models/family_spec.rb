# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Family, type: :model do
  let(:user) { create(:user) }

  describe 'associations' do
    it { is_expected.to have_many(:family_memberships).dependent(:destroy) }
    it { is_expected.to have_many(:members).through(:family_memberships).source(:user) }
    it { is_expected.to have_many(:family_invitations).dependent(:destroy) }
    it { is_expected.to belong_to(:creator).class_name('User') }
  end

  describe 'validations' do
    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_length_of(:name).is_at_most(50) }
  end

  describe 'constants' do
    it 'defines MAX_MEMBERS' do
      expect(Family::MAX_MEMBERS).to eq(5)
    end
  end

  describe '#can_add_members?' do
    let(:family) { create(:family, creator: user) }

    context 'when not in self-hosted mode' do
      before do
        allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
      end

      context 'when family has fewer than max members' do
        before do
          create(:family_membership, family: family, user: user, role: :owner)
          create_list(:family_membership, 3, family: family, role: :member)
        end

        it 'returns true' do
          expect(family.can_add_members?).to be true
        end
      end

      context 'when family has max members' do
        before do
          create(:family_membership, family: family, user: user, role: :owner)
          create_list(:family_membership, 4, family: family, role: :member)
        end

        it 'returns false' do
          expect(family.can_add_members?).to be false
        end
      end

      context 'when family has pending invitations that would reach max' do
        before do
          create(:family_membership, family: family, user: user, role: :owner)
          create_list(:family_membership, 3, family: family, role: :member)
          create(:family_invitation, family: family, invited_by: user, status: :pending)
        end

        it 'returns false' do
          expect(family.can_add_members?).to be false
        end
      end

      context 'when family has no members' do
        it 'returns true' do
          expect(family.can_add_members?).to be true
        end
      end
    end

    context 'when in self-hosted mode' do
      before do
        allow(DawarichSettings).to receive(:self_hosted?).and_return(true)
      end

      context 'when family has fewer than max members' do
        before do
          create(:family_membership, family: family, user: user, role: :owner)
          create_list(:family_membership, 3, family: family, role: :member)
        end

        it 'returns true' do
          expect(family.can_add_members?).to be true
        end
      end

      context 'when family has max members' do
        before do
          create(:family_membership, family: family, user: user, role: :owner)
          create_list(:family_membership, 4, family: family, role: :member)
        end

        it 'returns true (no limit in self-hosted mode)' do
          expect(family.can_add_members?).to be true
        end
      end

      context 'when family has more than max members' do
        before do
          create(:family_membership, family: family, user: user, role: :owner)
          create_list(:family_membership, 10, family: family, role: :member)
        end

        it 'returns true (no limit in self-hosted mode)' do
          expect(family.can_add_members?).to be true
        end
      end

      context 'when family has pending invitations that would exceed max' do
        before do
          create(:family_membership, family: family, user: user, role: :owner)
          create_list(:family_membership, 4, family: family, role: :member)
          create_list(:family_invitation, 5, family: family, invited_by: user, status: :pending)
        end

        it 'returns true (no limit in self-hosted mode)' do
          expect(family.can_add_members?).to be true
        end
      end
    end
  end

  describe 'family creation' do
    let(:family) { Family.new(name: 'Test Family', creator: user) }

    it 'can be created with valid attributes' do
      expect(family).to be_valid
    end

    it 'requires a name' do
      family.name = nil

      expect(family).not_to be_valid
      expect(family.errors[:name]).to include("can't be blank")
    end

    it 'requires a creator' do
      family.creator = nil

      expect(family).not_to be_valid
    end

    it 'rejects names longer than 50 characters' do
      long_name = 'a' * 51
      family.name = long_name

      expect(family).not_to be_valid
      expect(family.errors[:name]).to include('is too long (maximum is 50 characters)')
    end
  end

  describe 'members association' do
    let(:family) { create(:family, creator: user) }
    let(:member1) { create(:user) }
    let(:member2) { create(:user) }

    before do
      create(:family_membership, family: family, user: user, role: :owner)
      create(:family_membership, family: family, user: member1, role: :member)
      create(:family_membership, family: family, user: member2, role: :member)
    end

    it 'includes all family members' do
      expect(family.members).to include(user, member1, member2)
      expect(family.members.count).to eq(3)
    end
  end

  describe 'family invitations association' do
    let(:family) { create(:family, creator: user) }

    it 'destroys associated invitations when family is destroyed' do
      invitation = create(:family_invitation, family: family, invited_by: user)

      expect { family.destroy }.to change(Family::Invitation, :count).by(-1)
      expect(Family::Invitation.find_by(id: invitation.id)).to be_nil
    end
  end

  describe 'family memberships association' do
    let(:family) { create(:family, creator: user) }

    it 'destroys associated memberships when family is destroyed' do
      membership = create(:family_membership, family: family, user: user, role: :owner)

      expect { family.destroy }.to change(Family::Membership, :count).by(-1)
      expect(Family::Membership.find_by(id: membership.id)).to be_nil
    end
  end

  describe '#full?' do
    let(:family) { create(:family, creator: user) }

    context 'when not in self-hosted mode' do
      before do
        allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
      end

      context 'when family has fewer than max members' do
        before do
          create(:family_membership, family: family, user: user, role: :owner)
          create_list(:family_membership, 3, family: family, role: :member)
        end

        it 'returns false' do
          expect(family.full?).to be false
        end
      end

      context 'when family has exactly max members' do
        before do
          create(:family_membership, family: family, user: user, role: :owner)
          create_list(:family_membership, 4, family: family, role: :member)
        end

        it 'returns true' do
          expect(family.full?).to be true
        end
      end

      context 'when family has pending invitations that would reach max' do
        before do
          create(:family_membership, family: family, user: user, role: :owner)
          create_list(:family_membership, 3, family: family, role: :member)
          create(:family_invitation, family: family, invited_by: user, status: :pending)
        end

        it 'returns true' do
          expect(family.full?).to be true
        end
      end
    end

    context 'when in self-hosted mode' do
      before do
        allow(DawarichSettings).to receive(:self_hosted?).and_return(true)
      end

      context 'when family has fewer than max members' do
        before do
          create(:family_membership, family: family, user: user, role: :owner)
          create_list(:family_membership, 3, family: family, role: :member)
        end

        it 'returns false' do
          expect(family.full?).to be false
        end
      end

      context 'when family has exactly max members' do
        before do
          create(:family_membership, family: family, user: user, role: :owner)
          create_list(:family_membership, 4, family: family, role: :member)
        end

        it 'returns false (no limit in self-hosted mode)' do
          expect(family.full?).to be false
        end
      end

      context 'when family has more than max members' do
        before do
          create(:family_membership, family: family, user: user, role: :owner)
          create_list(:family_membership, 10, family: family, role: :member)
        end

        it 'returns false (no limit in self-hosted mode)' do
          expect(family.full?).to be false
        end
      end

      context 'when family has pending invitations that would exceed max' do
        before do
          create(:family_membership, family: family, user: user, role: :owner)
          create_list(:family_membership, 4, family: family, role: :member)
          create_list(:family_invitation, 5, family: family, invited_by: user, status: :pending)
        end

        it 'returns false (no limit in self-hosted mode)' do
          expect(family.full?).to be false
        end
      end
    end
  end
end

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

  describe 'leaving a family' do
    let(:family) { create(:family) }
    let(:member) { create(:user) }
    let!(:membership) { create(:family_membership, family: family, user: member, role: :member) }

    before { allow(DawarichSettings).to receive(:self_hosted?).and_return(false) }

    it 'stops location sharing even when the member had turned family off' do
      member.update_family_location_sharing!(true, duration: 'permanent')
      member.update!(settings: member.settings.merge('family_enabled' => false))

      membership.destroy!

      expect(member.reload.settings.dig('family', 'location_sharing', 'enabled')).not_to be true
    end

    it 'drops a member holding only the inherited grant to the free tier' do
      member.update!(plan: :pro, status: :active, active_until: 1.month.from_now, subscription_source: :none)

      membership.destroy!

      expect(member.reload).to have_attributes(plan: 'lite', status: 'inactive', active_until: nil)
    end

    it 'keeps the paid period of a member whose own subscription has lapsed pending renewal' do
      lapsed_at = 2.days.ago.change(usec: 0)
      member.update!(plan: :pro, status: :active, active_until: lapsed_at, subscription_source: :paddle)

      membership.destroy!

      expect(member.reload.active_until).to be_within(1.second).of(lapsed_at)
      expect(member.reload.plan).to eq('pro')
    end

    it 'leaves a member holding their own live subscription untouched' do
      member.update!(plan: :pro, status: :active, active_until: 1.month.from_now, subscription_source: :paddle)

      membership.destroy!

      expect(member.reload.plan).to eq('pro')
    end
  end

  describe 'Family Members map layer' do
    it 'turns the layer on next to the default layers for a user who never chose any' do
      user = create(:user)

      create(:family_membership, user: user)

      expect(user.reload.settings['enabled_map_layers']).to eq(['Tracks', 'Heatmap', 'Family Members'])
    end

    it 'keeps the layers the user already chose' do
      user = create(:user, settings: { 'enabled_map_layers' => ['Points'] })

      create(:family_membership, user: user)

      expect(user.reload.settings['enabled_map_layers']).to eq(['Points', 'Family Members'])
    end

    it 'is turned off again when the user leaves the family' do
      user = create(:user, settings: { 'enabled_map_layers' => ['Points'] })
      membership = create(:family_membership, user: user)

      membership.destroy!

      expect(user.reload.settings['enabled_map_layers']).to eq(['Points'])
    end

    it 'is turned on for the creator of a new family' do
      creator = create(:user, plan: :family)

      Families::Create.new(user: creator, name: 'Home').call

      expect(creator.reload.settings['enabled_map_layers']).to include('Family Members')
    end
  end
end

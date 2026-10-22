# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Entitlements do
  let(:user) { create(:user) }
  let(:entitlements) { described_class.for(user) }

  describe 'when self-hosted' do
    before { allow(DawarichSettings).to receive(:self_hosted?).and_return(true) }

    it 'grants every capability regardless of plan' do
      user.update!(plan: :lite)

      expect(entitlements.full_access?).to be true
      expect(entitlements.restricted?).to be false
      expect(entitlements.write_api?).to be true
      expect(entitlements.pro_api?).to be true
      expect(entitlements.integrations?).to be true
      expect(entitlements.public_sharing?).to be true
      expect(entitlements.families?).to be true
    end

    it 'has no data window' do
      user.update!(plan: :lite)

      expect(entitlements.data_window).to be_nil
      expect(entitlements.data_window_start).to be_nil
    end

    it 'has no points limit' do
      expect(entitlements.unlimited_points?).to be true
      expect(entitlements.points_limit).to be_nil
    end

    it 'reports the user own plan as effective plan' do
      user.update!(plan: :lite)

      expect(entitlements.effective_plan).to eq(:lite)
    end
  end

  describe 'when cloud-hosted' do
    before { allow(DawarichSettings).to receive(:self_hosted?).and_return(false) }

    context 'with a pro user' do
      before { user.update!(plan: :pro) }

      it 'grants pro capabilities' do
        expect(entitlements.full_access?).to be true
        expect(entitlements.restricted?).to be false
        expect(entitlements.write_api?).to be true
        expect(entitlements.pro_api?).to be true
        expect(entitlements.integrations?).to be true
        expect(entitlements.public_sharing?).to be true
      end

      it 'does not grant family creation' do
        expect(entitlements.families?).to be false
      end

      it 'has no data window' do
        expect(entitlements.data_window).to be_nil
        expect(entitlements.data_window_start).to be_nil
      end

      it 'caps points at the paid plan limit' do
        expect(entitlements.unlimited_points?).to be false
        expect(entitlements.points_limit).to eq(DawarichSettings::BASIC_PAID_PLAN_LIMIT)
      end
    end

    context 'with a lite user' do
      before { user.update!(plan: :lite) }

      it 'denies pro capabilities' do
        expect(entitlements.full_access?).to be false
        expect(entitlements.restricted?).to be true
        expect(entitlements.write_api?).to be false
        expect(entitlements.pro_api?).to be false
        expect(entitlements.integrations?).to be false
        expect(entitlements.public_sharing?).to be false
        expect(entitlements.families?).to be false
      end

      it 'applies the 12-month data window' do
        expect(entitlements.data_window).to eq(DawarichSettings::LITE_DATA_WINDOW)
        expect(entitlements.data_window_start)
          .to be_within(5.seconds).of(DawarichSettings::LITE_DATA_WINDOW.ago)
      end

      it 'caps points at the paid plan limit' do
        expect(entitlements.unlimited_points?).to be false
        expect(entitlements.points_limit).to eq(DawarichSettings::BASIC_PAID_PLAN_LIMIT)
      end
    end

    context 'with a trial user' do
      let(:user) { create(:user, status: :trial, active_until: 7.days.from_now) }

      it 'grants pro capabilities during the trial' do
        expect(entitlements.full_access?).to be true
        expect(entitlements.restricted?).to be false
        expect(entitlements.write_api?).to be true
        expect(entitlements.pro_api?).to be true
        expect(entitlements.data_window).to be_nil
      end
    end

    context 'with a family plan owner' do
      let(:user) { create(:user, plan: :family, skip_auto_trial: true) }

      before do
        family = create(:family, creator: user)
        create(:family_membership, :owner, family: family, user: user)
      end

      it 'grants pro capabilities and family creation' do
        expect(entitlements.full_access?).to be true
        expect(entitlements.write_api?).to be true
        expect(entitlements.families?).to be true
        expect(entitlements.data_window).to be_nil
      end

      it 'revokes family creation once the owner own subscription lapses' do
        user.update!(status: :inactive, active_until: 1.day.ago)

        expect(entitlements.families?).to be false
      end

      it 'reports family as effective plan' do
        expect(entitlements.effective_plan).to eq(:family)
      end
    end

    context 'with a lite user who belongs to a family with a family-plan owner' do
      let(:owner) { create(:user, plan: :family, skip_auto_trial: true) }
      let(:user) { create(:user, plan: :lite, skip_auto_trial: true) }

      before do
        family = create(:family, creator: owner)
        create(:family_membership, :owner, family: family, user: owner)
        create(:family_membership, family: family, user: user)
      end

      it 'inherits full access through the family' do
        expect(entitlements.effective_plan).to eq(:family)
        expect(entitlements.full_access?).to be true
        expect(entitlements.restricted?).to be false
        expect(entitlements.write_api?).to be true
        expect(entitlements.data_window).to be_nil
      end
    end

    context 'with a lite user whose family owner subscription lapsed' do
      let(:user) { create(:user, plan: :lite, skip_auto_trial: true) }

      def build_family_with_owner(active_until:, status: :inactive)
        owner = create(:user, plan: :family, skip_auto_trial: true, status: status,
                              active_until: active_until)
        family = create(:family, creator: owner)
        create(:family_membership, :owner, family: family, user: owner)
        create(:family_membership, family: family, user: user)
      end

      it 'reverts the member to their raw plan once the owner subscription lapses' do
        build_family_with_owner(active_until: 1.day.ago)

        expect(entitlements.effective_plan).to eq(:lite)
        expect(entitlements.full_access?).to be false
      end

      it 'keeps family access while a cancelled owner is still inside the paid period' do
        build_family_with_owner(active_until: 10.days.from_now)

        expect(entitlements.effective_plan).to eq(:family)
      end

      it 'grants family access while the owner is on a trial' do
        build_family_with_owner(active_until: 7.days.from_now, status: :trial)

        expect(entitlements.effective_plan).to eq(:family)
      end

      it 'reverts the member when the owner has no subscription window at all' do
        build_family_with_owner(active_until: nil)

        expect(entitlements.effective_plan).to eq(:lite)
      end
    end
  end
end

# frozen_string_literal: true

require 'rails_helper'

RSpec.describe FamilyPolicy, type: :policy do
  describe 'create?' do
    context 'when self-hosted' do
      before { allow(DawarichSettings).to receive(:self_hosted?).and_return(true) }

      it 'permits any user not already in a family' do
        user = create(:user, plan: :lite, skip_auto_trial: true)

        expect(FamilyPolicy.new(user, Family)).to permit(:create)
      end
    end

    context 'when cloud' do
      before { allow(DawarichSettings).to receive(:self_hosted?).and_return(false) }

      it 'permits a user on the family plan' do
        user = create(:user, plan: :family, skip_auto_trial: true)

        expect(FamilyPolicy.new(user, Family)).to permit(:create)
      end

      it 'denies a pro user' do
        user = create(:user, plan: :pro, skip_auto_trial: true)

        expect(FamilyPolicy.new(user, Family)).not_to permit(:create)
      end

      it 'denies a lite user' do
        user = create(:user, plan: :lite, skip_auto_trial: true)

        expect(FamilyPolicy.new(user, Family)).not_to permit(:create)
      end

      it 'denies a family-plan user who is already in a family' do
        user = create(:user, plan: :family, skip_auto_trial: true)
        family = create(:family, creator: user)
        create(:family_membership, :owner, family: family, user: user)

        expect(FamilyPolicy.new(user, Family)).not_to permit(:create)
      end
    end
  end
end

# frozen_string_literal: true

require 'rails_helper'

RSpec.describe DawarichSettings do
  describe '.family_feature_available_for?' do
    context 'when self-hosted' do
      before { allow(described_class).to receive(:self_hosted?).and_return(true) }

      it 'is available regardless of plan' do
        user = create(:user, plan: :lite)

        expect(described_class.family_feature_available_for?(user)).to be true
      end

      it 'is available without a user' do
        expect(described_class.family_feature_available_for?(nil)).to be true
      end
    end

    context 'when running on cloud' do
      before { allow(described_class).to receive(:self_hosted?).and_return(false) }

      it 'is available to subscribers on the family plan' do
        user = create(:user, plan: :family, skip_auto_trial: true)

        expect(described_class.family_feature_available_for?(user)).to be true
      end

      it 'is not available on the pro plan' do
        user = create(:user, plan: :pro, skip_auto_trial: true)

        expect(described_class.family_feature_available_for?(user)).to be false
      end

      it 'is not available on the lite plan' do
        user = create(:user, plan: :lite, skip_auto_trial: true)

        expect(described_class.family_feature_available_for?(user)).to be false
      end

      it 'is not available without a user' do
        expect(described_class.family_feature_available_for?(nil)).to be false
      end

      it 'is available to members of a family they did not pay for' do
        owner = create(:user, plan: :family, skip_auto_trial: true)
        family = create(:family, creator: owner)
        member = create(:user, plan: :pro, skip_auto_trial: true)
        create(:family_membership, user: member, family: family)

        expect(described_class.family_feature_available_for?(member)).to be true
      end

      it 'does not leak one user answer into the next' do
        subscriber = create(:user, plan: :family, skip_auto_trial: true)
        non_subscriber = create(:user, plan: :pro, skip_auto_trial: true)

        expect(described_class.family_feature_available_for?(subscriber)).to be true
        expect(described_class.family_feature_available_for?(non_subscriber)).to be false
        expect(described_class.family_feature_available_for?(subscriber)).to be true
      end
    end
  end

  describe '.features_for' do
    it 'reports family availability for the given user' do
      allow(described_class).to receive(:self_hosted?).and_return(false)
      subscriber = create(:user, plan: :family, skip_auto_trial: true)
      non_subscriber = create(:user, plan: :pro, skip_auto_trial: true)

      expect(described_class.features_for(subscriber)[:family]).to be true
      expect(described_class.features_for(non_subscriber)[:family]).to be false
    end
  end
end

require 'rails_helper'

RSpec.describe Signup::BucketVariant do
  let(:user) { create(:user) }

  context 'feature disabled' do
    before { Flipper.disable(:reverse_trial_signup) }

    it 'returns legacy_trial for everyone' do
      expect(described_class.new(user).call).to eq('legacy_trial')
    end
  end

  context 'feature enabled 100%' do
    before { Flipper.enable(:reverse_trial_signup) }

    it 'returns reverse_trial for everyone' do
      expect(described_class.new(user).call).to eq('reverse_trial')
    end
  end

  context 'feature enabled for specific actor' do
    before do
      Flipper.disable(:reverse_trial_signup)
      Flipper.enable_actor(:reverse_trial_signup, user)
    end

    it 'returns reverse_trial for that actor' do
      expect(described_class.new(user).call).to eq('reverse_trial')
    end

    it 'returns legacy_trial for a different actor' do
      other = create(:user)
      expect(described_class.new(other).call).to eq('legacy_trial')
    end
  end

  context 'feature enabled at 50% of actors' do
    before do
      Flipper.disable(:reverse_trial_signup)
      Flipper.enable_percentage_of_actors(:reverse_trial_signup, 50)
    end

    it 'is deterministic for the same user across calls' do
      result1 = described_class.new(user).call
      result2 = described_class.new(user).call
      expect(result1).to eq(result2)
    end
  end
end

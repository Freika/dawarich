# frozen_string_literal: true

require 'rails_helper'

RSpec.describe DataMigrations::BackfillOnboardingCompletedJob, type: :job do
  describe '#perform' do
    it 'sets onboarding_completed for users with points' do
      user = create(:user, points_count: 100, settings: {})

      described_class.perform_now

      user.reload
      expect(user.settings['onboarding_completed']).to be true
    end

    it 'does not change users who already have onboarding_completed' do
      user = create(:user, points_count: 50, settings: { 'onboarding_completed' => true })

      described_class.perform_now

      user.reload
      expect(user.settings['onboarding_completed']).to be true
    end

    it 'skips users with zero points' do
      user = create(:user, points_count: 0, settings: {})

      described_class.perform_now

      user.reload
      expect(user.settings['onboarding_completed']).to be_nil
    end

    it 'preserves existing settings when adding onboarding_completed' do
      user = create(:user, points_count: 10, settings: { 'route_opacity' => 0.8, 'theme' => 'dark' })

      described_class.perform_now

      user.reload
      expect(user.settings['onboarding_completed']).to be true
      expect(user.settings['route_opacity']).to eq(0.8)
      expect(user.settings['theme']).to eq('dark')
    end
  end
end

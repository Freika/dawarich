# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Visits::Detection::Policy do
  let(:user) { create(:user) }

  describe '.for' do
    it 'derives thresholds from the user settings' do
      user.update!(settings: user.settings.merge(
        'visit_radius_meters' => 120,
        'visit_min_points' => 4,
        'visit_min_duration_minutes' => 7,
        'merge_threshold_minutes' => 20
      ))

      policy = described_class.for(user)

      expect(policy.stay_radius_m).to eq(120)
      expect(policy.min_points).to eq(4)
      expect(policy.min_dwell_s).to eq(7 * 60)
      expect(policy.merge_gap_s).to eq(20 * 60)
    end

    it 'exposes fixed internals unaffected by the retired stay_max_gap setting' do
      user.update!(settings: user.settings.merge('stay_max_gap_minutes' => 300))

      policy = described_class.for(user)

      expect(policy.sweep_gap_s).to eq(60 * 60)
      expect(policy.bridge_cap_s).to eq(7.days.to_i)
      expect(policy.snap_max_s).to eq(15 * 60)
      expect(policy.attribution_radius_m).to eq(50)
    end

    it 'returns a frozen value object' do
      expect(described_class.for(user)).to be_frozen
    end

    it 'reads settings once at construction, not per accessor' do
      policy = described_class.for(user)
      user.update!(settings: user.settings.merge('visit_radius_meters' => 999))

      expect(policy.stay_radius_m).not_to eq(999)
    end
  end
end

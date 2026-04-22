# frozen_string_literal: true

require 'rails_helper'

RSpec.describe GeofenceEvents::Evaluator::StateStore do
  let(:user) { create(:user) }
  let(:area) { create(:area, user: user) }

  before { described_class.reset!(user) }

  describe '.currently_inside' do
    it 'returns empty set initially' do
      expect(described_class.currently_inside(user)).to be_empty
    end

    it 'returns area ids after apply enter' do
      described_class.apply(user, area, :enter)
      expect(described_class.currently_inside(user)).to include(area.id)
    end

    it 'removes area id after apply leave' do
      described_class.apply(user, area, :enter)
      described_class.apply(user, area, :leave)
      expect(described_class.currently_inside(user)).not_to include(area.id)
    end
  end

  describe 'isolation between users' do
    it 'does not leak across users' do
      other = create(:user)
      described_class.apply(user, area, :enter)
      expect(described_class.currently_inside(other)).to be_empty
    end
  end
end

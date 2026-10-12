# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Flight, type: :model do
  describe 'associations' do
    it { is_expected.to belong_to(:user) }
  end

  describe 'validations' do
    subject { build(:flight) }

    it { is_expected.to validate_presence_of(:external_id) }

    it 'is unique per user + external_id' do
      flight = create(:flight)
      dup = build(:flight, user: flight.user, external_id: flight.external_id)
      expect(dup).not_to be_valid
    end
  end
end

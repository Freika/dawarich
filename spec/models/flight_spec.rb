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

  describe '#mask_window' do
    it 'returns [departure, arrival] epoch seconds when both present' do
      flight = build(:flight,
                     departure_time: Time.utc(2026, 4, 20, 10),
                     arrival_time: Time.utc(2026, 4, 20, 12))
      expect(flight.mask_window).to eq([Time.utc(2026, 4, 20, 10).to_i, Time.utc(2026, 4, 20, 12).to_i])
    end

    it 'returns nil when a time is missing' do
      expect(build(:flight, departure_time: nil).mask_window).to be_nil
    end
  end
end

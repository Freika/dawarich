# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Cache::PreheatInsightsDigests do
  include ActiveSupport::Testing::TimeHelpers

  it 'builds only completed years when the user has current-year stats' do
    travel_to Time.utc(2026, 6, 15) do
      user = create(:user)
      create(:stat, user:, year: 2025, month: 12)
      create(:stat, user:, year: 2026, month: 1)
      allow(Users::Digests::CalculateYear).to receive(:new) do |_user_id, year|
        double(call: create(:users_digest, user:, year:))
      end

      described_class.new(user).call

      expect(Users::Digests::CalculateYear).to have_received(:new).with(user.id, 2025)
      expect(Users::Digests::CalculateYear).not_to have_received(:new).with(user.id, 2026)
    end
  end
end

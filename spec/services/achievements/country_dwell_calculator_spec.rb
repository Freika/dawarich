# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Achievements::CountryDwellCalculator do
  let(:user) { create(:user) }
  let(:base_ts) { DateTime.new(2026, 1, 1).to_i }

  before do
    country = create(:country, name: 'Testland', iso_a2: 'TT', iso_a3: 'TST')
    6.times do |index|
      create(:point, user: user, country: country, timestamp: base_ts + (index * 600))
    end
  end

  it 'does not include points after the captured cursor' do
    result = described_class.new(user, through: base_ts + 1800).call

    expect(result['TT']).to eq(1800)
  end
end

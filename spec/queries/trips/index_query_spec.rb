# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Trips::IndexQuery do
  let(:user) { create(:user) }

  describe 'origin filter' do
    before { stub_host_addresses('trek.example.test', '93.184.216.34') }

    let!(:manual) { create(:trip, user:) }
    let!(:managed) { create(:trip, user:, trip_source: create(:trip_source, user:), source_identifier: 'abc') }
    let!(:detected) { create(:trip, user:, origin: :detected) }

    it 'returns every trip without the parameter' do
      expect(described_class.new(user, {}).call).to contain_exactly(manual, managed, detected)
    end

    it 'returns Detected Trips for origin=detected' do
      expect(described_class.new(user, { origin: 'detected' }).call).to contain_exactly(detected)
    end

    it 'counts Managed Trips as created by the user' do
      expect(described_class.new(user, { origin: 'manual' }).call).to contain_exactly(manual, managed)
    end

    it 'ignores an unknown value and reports the filter as active only for a known one' do
      expect(described_class.new(user, { origin: 'x' }).filters).to have_attributes(origin: nil, active?: false)
      expect(described_class.new(user, { origin: 'detected' }).filters.active?).to be(true)
    end
  end
end

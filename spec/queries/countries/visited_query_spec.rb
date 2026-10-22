# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Countries::VisitedQuery do
  let(:user) { create(:user) }
  let(:country) { create(:country, name: 'Germany', iso_a2: 'DE', iso_a3: 'DEU') }

  it 'returns unique canonical countries within the selected history scope' do
    create(:point, user:, country:, country_name: 'Deutschland', timestamp: 1_000)
    create(:point, user:, country:, timestamp: 1_100)
    create(:point, user:, country:, timestamp: 9_000)

    result = described_class.new(user:, start_at: 900, end_at: 1_200).call

    expect(result).to eq([{ iso_a3: 'DEU', name: 'Germany' }])
  end

  it 'excludes anomalies and respects import filtering' do
    import = create(:import, user:)
    create(:point, user:, country:, timestamp: 1_000, import:)
    create(:point, user:, country:, timestamp: 1_010, anomaly: true)

    result = described_class.new(user:, start_at: 900, end_at: 1_200, import_id: import.id).call

    expect(result.map { |item| item[:iso_a3] }).to eq(['DEU'])
  end

  it 'counts trackless Points and preserves legacy country-name precedence' do
    first = create(:point, user:, track: nil, timestamp: 1_000)
    second = create(:point, user:, track: nil, timestamp: 1_010)
    first.update_columns(country: nil, country_id: nil, country_name: 'United States')
    second.update_columns(country: 'France', country_id: nil, country_name: 'United States')

    result = described_class.new(user:, start_at: 900, end_at: 1_200).call

    expect(result).to eq([{ iso_a3: 'USA', name: 'United States of America' }])
  end

  it 'returns no country outside the selected history scope' do
    create(:point, user:, country:, timestamp: 1_000)

    result = described_class.new(user:, start_at: 2_000, end_at: 3_000).call

    expect(result).to be_empty
  end
end

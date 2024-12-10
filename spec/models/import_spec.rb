# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Import, type: :model do
  describe 'associations' do
    it { is_expected.to have_many(:points).dependent(:destroy) }
    it { is_expected.to belong_to(:user) }
  end

  describe 'enums' do
    it do
      is_expected.to define_enum_for(:source).with_values(
        google_semantic_history: 0,
        owntracks: 1,
        google_records: 2,
        google_phone_takeout: 3,
        gpx: 4,
        immich_api: 5,
        geojson: 6,
        photoprism_api: 7
      )
    end
  end

  describe '#years_and_months_tracked' do
    let(:import) { create(:import) }
    let(:timestamp) { Time.zone.local(2024, 11, 1) }
    let!(:points) { create_list(:point, 3, import:, timestamp:) }

    it 'returns years and months tracked' do
      expect(import.years_and_months_tracked).to eq([[2024, 11]])
    end
  end
end

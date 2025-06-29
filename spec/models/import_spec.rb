# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Import, type: :model do
  describe 'associations' do
    it { is_expected.to have_many(:points).dependent(:destroy) }
    it { is_expected.to belong_to(:user) }
  end

  describe 'validations' do
    subject { build(:import, name: 'test import') }

    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_uniqueness_of(:name).scoped_to(:user_id) }
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
        photoprism_api: 7,
        user_data_archive: 8
      )
    end
  end

  describe '#years_and_months_tracked' do
    let(:import) { create(:import) }
    let(:timestamp) { Time.zone.local(2024, 11, 1) }
    let!(:points) do
      (1..3).map do |i|
        create(:point, import:, timestamp: timestamp + i.minutes)
      end
    end

    it 'returns years and months tracked' do
      expect(import.years_and_months_tracked).to eq([[2024, 11]])
    end
  end

  describe '#migrate_to_new_storage' do
    let(:raw_data) { Rails.root.join('spec/fixtures/files/geojson/export.json') }
    let(:import) { create(:import, source: 'geojson', raw_data:) }

    it 'attaches the file to the import' do
      import.migrate_to_new_storage

      expect(import.file.attached?).to be_truthy
    end

    context 'when file is attached' do
      it 'is a importable file' do
        import.migrate_to_new_storage

        expect { import.process! }.to change(Point, :count).by(10)
      end
    end
  end
end

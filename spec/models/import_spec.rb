# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Import, type: :model do
  let(:user) { create(:user) }
  subject(:import) { create(:import, user:) }

  describe 'associations' do
    it { is_expected.to have_many(:points).dependent(:destroy) }
    it 'belongs to a user' do
      expect(user).to be_present
      expect(import.user).to eq(user)
    end
  end

  describe 'validations' do
    it { is_expected.to validate_presence_of(:name) }

    it 'validates uniqueness of name scoped to user_id' do
      create(:import, name: 'test_name', user: user)

      duplicate_import = build(:import, name: 'test_name', user: user)
      expect(duplicate_import).not_to be_valid
      expect(duplicate_import.errors[:name]).to include('has already been taken')

      other_user = create(:user)
      different_user_import = build(:import, name: 'test_name', user: other_user)
      expect(different_user_import).to be_valid
    end

    describe 'file size validation' do
      context 'when user is a trial user' do
        let(:user) do
          user = create(:user)
          user.update!(status: :trial)
          user
        end

        it 'validates file size limit for large files' do
          import = build(:import, user: user)
          mock_file = double(attached?: true, blob: double(byte_size: 12.megabytes))
          allow(import).to receive(:file).and_return(mock_file)

          expect(import).not_to be_valid
          expect(import.errors[:file]).to include('is too large. Trial users can only upload files up to 10MB.')
        end

        it 'allows files under the size limit' do
          import = build(:import, user: user)
          mock_file = double(attached?: true, blob: double(byte_size: 5.megabytes))
          allow(import).to receive(:file).and_return(mock_file)

          expect(import).to be_valid
        end
      end

      context 'when user is a paid user' do
        let(:user) { create(:user, status: :active) }
        let(:import) { build(:import, user: user) }

        it 'does not validate file size limit' do
          allow(import).to receive(:file).and_return(double(attached?: true, blob: double(byte_size: 12.megabytes)))

          expect(import).to be_valid
        end
      end
    end

    describe 'import count validation' do
      context 'when user is a trial user' do
        let(:user) do
          user = create(:user)
          user.update!(status: :trial)
          user
        end

        it 'allows imports when under the limit' do
          3.times { |i| create(:import, user: user, name: "import_#{i}") }
          new_import = build(:import, user: user, name: 'new_import')

          expect(new_import).to be_valid
        end

        it 'prevents creating more than 5 imports' do
          5.times { |i| create(:import, user: user, name: "import_#{i}") }
          new_import = build(:import, user: user, name: 'import_6')

          expect(new_import).not_to be_valid
          expect(new_import.errors[:base]).to include('Trial users can only create up to 5 imports. Please subscribe to import more files.')
        end
      end

      context 'when user is an active user' do
        let(:user) { create(:user, status: :active) }

        it 'does not validate import count limit' do
          7.times { |i| create(:import, user: user, name: "import_#{i}") }
          new_import = build(:import, user: user, name: 'import_8')

          expect(new_import).to be_valid
        end
      end
    end
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
        user_data_archive: 8,
        kml: 9,
        google_photos_api: 10
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

  describe '#recalculate_stats' do
    let(:import) { create(:import, user:) }
    let!(:point1) { create(:point, import:, user:, timestamp: Time.zone.local(2024, 11, 15).to_i) }
    let!(:point2) { create(:point, import:, user:, timestamp: Time.zone.local(2024, 12, 5).to_i) }

    it 'enqueues stats calculation jobs for each tracked month' do
      expect do
        import.send(:recalculate_stats)
      end.to have_enqueued_job(Stats::CalculatingJob)
        .with(user.id, 2024, 11)
        .and have_enqueued_job(Stats::CalculatingJob).with(user.id, 2024, 12)
    end

    context 'when import has no points' do
      let(:empty_import) { create(:import, user:) }

      it 'does not enqueue any jobs' do
        expect do
          empty_import.send(:recalculate_stats)
        end.not_to have_enqueued_job(Stats::CalculatingJob)
      end
    end
  end
end

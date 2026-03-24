# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Csv::Importer do
  let(:user) { create(:user) }
  let(:import) { create(:import, user: user, source: :csv) }

  describe '#call' do
    context 'with GPSLogger CSV' do
      let(:file_path) { Rails.root.join('spec/fixtures/files/csv/gpslogger.csv').to_s }

      before { described_class.new(import, user.id, file_path).call }

      it 'creates 3 points' do
        expect(user.points.count).to eq(3)
      end

      it 'parses coordinates correctly' do
        point = user.points.order(:timestamp).first
        expect(point.lat).to be_within(0.01).of(52.52)
        expect(point.lon).to be_within(0.01).of(13.405)
      end

      it 'sets import_id on points' do
        expect(user.points.where(import_id: import.id).count).to eq(3)
      end
    end

    context 'with semicolon EU CSV' do
      let(:file_path) { Rails.root.join('spec/fixtures/files/csv/semicolon_eu.csv').to_s }

      before { described_class.new(import, user.id, file_path).call }

      it 'creates 3 points despite comma decimals' do
        expect(user.points.count).to eq(3)
      end
    end

    context 'with Unix timestamps CSV' do
      let(:file_path) { Rails.root.join('spec/fixtures/files/csv/unix_timestamps.csv').to_s }

      before { described_class.new(import, user.id, file_path).call }

      it 'creates 3 points' do
        expect(user.points.count).to eq(3)
      end

      it 'parses Unix timestamps' do
        point = user.points.order(:timestamp).first
        expect(point.timestamp).to be > Time.zone.parse('2024-01-01').to_i
      end
    end

    context 'with rows missing required fields' do
      it 'skips invalid rows and imports valid ones' do
        file = Tempfile.new(['mixed', '.csv'])
        file.write("lat,lon,time\n52.52,13.405,2024-06-15T10:30:00Z\n,,\n52.53,13.406,2024-06-15T10:31:00Z\n")
        file.rewind

        import2 = create(:import, user: user, source: :csv)
        described_class.new(import2, user.id, file.path).call
        expect(user.points.where(import_id: import2.id).count).to eq(2)
      ensure
        file&.close
        file&.unlink
      end
    end
  end
end

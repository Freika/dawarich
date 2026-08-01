# frozen_string_literal: true

require 'rails_helper'

# Google phone Timeline exports taken after mid-June 2026 carry both the
# aggregated `semanticSegments` and the raw `rawSignals` stream for the same
# period. Ingesting both interleaves two independently sampled timelines whose
# gaps do not line up, which erases the pauses track segmentation relies on and
# welds whole weeks into a single track.
RSpec.describe 'Google phone takeout with overlapping rawSignals' do
  subject(:import_file) { GoogleMaps::PhoneTakeoutImporter.new(import, user.id).call }

  let(:user) { create(:user) }
  let(:import) { create(:import, user:, name: 'phone_takeout.json') }

  before do
    import.file.attach(
      io: File.open(file_path), filename: 'phone_takeout.json', content_type: 'application/json'
    )
  end

  def imported_latitudes
    Point.where(user_id: user.id).pluck(Arel.sql('ST_Y(lonlat::geometry)')).map { |lat| lat.round(4) }.sort
  end

  context 'when the export contains both semanticSegments and rawSignals' do
    let(:file_path) do
      Rails.root.join('spec/fixtures/files/google/edge_cases/phone_takeout_semantic_and_raw_signals.json')
    end

    it 'imports only the semanticSegments points' do
      expect { import_file }.to change { Point.count }.by(2)
    end

    it 'keeps the timelinePath coordinates and drops the raw positions' do
      import_file

      expect(imported_latitudes).to eq([52.52, 52.521])
    end

    it 'tells the user how many raw signals were skipped and that nothing was lost' do
      import_file

      notification = Notification.find_by(user_id: user.id, title: 'Raw location signals skipped')
      expect(notification).to be_present
      expect(notification.content).to include('2 raw location signals')
      expect(notification.content).to include('No timeline data was lost')
    end
  end

  context 'when rawSignals appear before semanticSegments in the file' do
    let(:file_path) do
      Rails.root.join('spec/fixtures/files/google/edge_cases/phone_takeout_raw_signals_before_semantic.json')
    end

    it 'still drops the raw positions regardless of key order' do
      import_file

      expect(imported_latitudes).to eq([52.52, 52.521])
    end
  end

  # The key can be present while the array is empty — Google's server-side aggregation
  # lags behind fresher on-device signals. Skipping rawSignals on mere key presence would
  # import nothing at all, and the import would report success.
  context 'when semanticSegments is present but empty' do
    let(:file_path) do
      Rails.root.join('spec/fixtures/files/google/edge_cases/phone_takeout_empty_semantic_with_raw_signals.json')
    end

    it 'falls back to the raw positions instead of importing nothing' do
      expect { import_file }.to change { Point.count }.by(2)
    end

    it 'keeps the raw position coordinates' do
      import_file

      expect(imported_latitudes).to eq([52.5205, 52.5207])
    end

    it 'does not claim raw signals were skipped once they have been replayed' do
      import_file

      expect(Notification.where(user_id: user.id, title: 'Raw location signals skipped')).to be_empty
    end
  end

  context 'when the export contains rawSignals only' do
    let(:file_path) do
      Rails.root.join('spec/fixtures/files/google/edge_cases/phone_takeout_raw_signals_only.json')
    end

    it 'imports the raw positions' do
      expect { import_file }.to change { Point.count }.by(2)
    end

    it 'keeps the raw position coordinates' do
      import_file

      expect(imported_latitudes).to eq([52.5205, 52.5207])
    end
  end
end

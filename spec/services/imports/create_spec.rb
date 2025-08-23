# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Imports::Create do
  let(:user) { create(:user) }
  let(:service) { described_class.new(user, import) }

  describe '#call' do
    describe 'status transitions' do
      let(:import) { create(:import, source: 'owntracks', status: 'created') }
      let(:file_path) { Rails.root.join('spec/fixtures/files/owntracks/2024-03.rec') }

      before do
        import.file.attach(io: File.open(file_path), filename: '2024-03.rec', content_type: 'application/octet-stream')
      end

      it 'sets status to processing at start' do
        service.call

        expect(import.reload.status).to eq('processing').or eq('completed')
      end

      it 'updates the import source' do
        service.call

        expect(import.reload.source).to eq('owntracks')
      end

      context 'when import succeeds' do
        it 'sets status to completed' do
          service.call
          expect(import.reload.status).to eq('completed')
        end
      end

      context 'when import fails' do
        before do
          allow(OwnTracks::Importer).to receive(:new).with(import, user.id, kind_of(String)).and_raise(StandardError)
        end

        it 'sets status to failed' do
          service.call
          expect(import.reload.status).to eq('failed')
        end
      end
    end

    context 'when source is google_semantic_history' do
      let(:import) { create(:import, source: 'google_semantic_history') }
      let(:file_path) { Rails.root.join('spec/fixtures/files/google/semantic_history.json') }
      let(:file) { Rack::Test::UploadedFile.new(file_path, 'application/json') }

      before do
        import.file.attach(io: File.open(file_path), filename: 'semantic_history.json',
                           content_type: 'application/json')
      end

      it 'calls the GoogleMaps::SemanticHistoryImporter' do
        expect(GoogleMaps::SemanticHistoryImporter).to \
          receive(:new).with(import, user.id, kind_of(String)).and_return(double(call: true))
        service.call
      end

      it 'updates the import points count' do
        expect { service.call }.to have_enqueued_job(Import::UpdatePointsCountJob).with(import.id)
      end
    end

    context 'when source is google_phone_takeout' do
      let(:import) { create(:import, source: 'google_phone_takeout') }
      let(:file_path) { Rails.root.join('spec/fixtures/files/google/phone-takeout_w_3_duplicates.json') }

      before do
        import.file.attach(io: File.open(file_path), filename: 'phone-takeout_w_3_duplicates.json',
                           content_type: 'application/json')
      end

      it 'calls the GoogleMaps::PhoneTakeoutImporter' do
        expect(GoogleMaps::PhoneTakeoutImporter).to \
          receive(:new).with(import, user.id, kind_of(String)).and_return(double(call: true))
        service.call
      end
    end

    context 'when source is owntracks' do
      let(:import) { create(:import, source: 'owntracks', name: '2024-03.rec') }
      let(:file_path) { Rails.root.join('spec/fixtures/files/owntracks/2024-03.rec') }
      let(:file) { Rack::Test::UploadedFile.new(file_path, 'application/octet-stream') }

      before do
        import.file.attach(io: File.open(file_path), filename: '2024-03.rec', content_type: 'application/octet-stream')
      end

      it 'calls the OwnTracks::Importer' do
        expect(OwnTracks::Importer).to \
          receive(:new).with(import, user.id, kind_of(String)).and_return(double(call: true))
        service.call
      end

      context 'when import is successful' do
        it 'schedules stats creating' do
          Sidekiq::Testing.inline! do
            expect { service.call }.to \
              have_enqueued_job(Stats::CalculatingJob).with(user.id, 2024, 3)
          end
        end

        it 'schedules visit suggesting' do
          Sidekiq::Testing.inline! do
            expect { service.call }.to have_enqueued_job(VisitSuggestingJob)
          end
        end
      end

      context 'when import fails' do
        before do
          allow(OwnTracks::Importer).to receive(:new).with(import, user.id, kind_of(String)).and_raise(StandardError)
        end

        context 'when self-hosted' do
          before do
            allow(DawarichSettings).to receive(:self_hosted?).and_return(true)
          end

          after do
            allow(DawarichSettings).to receive(:self_hosted?).and_call_original
          end

          it 'creates a failed notification' do
            service.call

            expect(user.notifications.last.content).to \
              include('Import "2024-03.rec" failed: StandardError, stacktrace: ')
          end
        end

        context 'when not self-hosted' do
          before do
            allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
          end

          after do
            allow(DawarichSettings).to receive(:self_hosted?).and_call_original
          end

          it 'does not create a failed notification' do
            service.call

            expect(user.notifications.last.content).to \
              include('Import "2024-03.rec" failed, please contact us at hi@dawarich.com')
          end
        end
      end
    end

    context 'when source is gpx' do
      let(:import) { create(:import, source: 'gpx') }
      let(:file_path) { Rails.root.join('spec/fixtures/files/gpx/gpx_track_single_segment.gpx') }
      let(:file) { Rack::Test::UploadedFile.new(file_path, 'application/octet-stream') }

      before do
        import.file.attach(io: File.open(file_path), filename: 'gpx_track_single_segment.gpx',
                           content_type: 'application/octet-stream')
      end

      it 'calls the Gpx::TrackImporter' do
        expect(Gpx::TrackImporter).to \
          receive(:new).with(import, user.id, kind_of(String)).and_return(double(call: true))
        service.call
      end
    end

    context 'when source is geojson' do
      let(:import) { create(:import, source: 'geojson') }
      let(:file_path) { Rails.root.join('spec/fixtures/files/geojson/export.json') }

      before do
        import.file.attach(io: File.open(file_path), filename: 'export.json',
                           content_type: 'application/json')
      end

      it 'calls the Geojson::Importer' do
        expect(Geojson::Importer).to \
          receive(:new).with(import, user.id, kind_of(String)).and_return(double(call: true))
        service.call
      end
    end

    context 'when source is immich_api' do
      let(:import) { create(:import, source: 'immich_api') }
      let(:file_path) { Rails.root.join('spec/fixtures/files/immich/geodata.json') }

      before do
        import.file.attach(io: File.open(file_path), filename: 'geodata.json',
                           content_type: 'application/json')
      end

      it 'calls the Photos::Importer' do
        expect(Photos::Importer).to \
          receive(:new).with(import, user.id, kind_of(String)).and_return(double(call: true))

        service.call
      end
    end

    context 'when source is photoprism_api' do
      let(:import) { create(:import, source: 'photoprism_api') }
      let(:file_path) { Rails.root.join('spec/fixtures/files/immich/geodata.json') }

      before do
        import.file.attach(io: File.open(file_path), filename: 'geodata.json',
                           content_type: 'application/json')
      end

      it 'calls the Photos::Importer' do
        expect(Photos::Importer).to \
          receive(:new).with(import, user.id, kind_of(String)).and_return(double(call: true))
        service.call
      end
    end
  end
end

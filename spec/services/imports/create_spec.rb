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

      it 'increments points counter by delta' do
        service.call

        expect(user.reload.points_count).to eq(user.points.count)
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

        it 'sets the error message' do
          service.call
          expect(import.reload.error_message).to eq('StandardError')
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

      it 'completes the import and creates points' do
        expect { service.call }.to change { import.points.count }.from(0)

        expect(import.reload.status).to eq('completed')
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

      it 'completes the import and creates points' do
        expect { service.call }.to change { import.points.count }.from(0)

        expect(import.reload.status).to eq('completed')
      end
    end

    context 'when source is owntracks' do
      let(:import) { create(:import, source: 'owntracks', name: '2024-03.rec') }
      let(:file_path) { Rails.root.join('spec/fixtures/files/owntracks/2024-03.rec') }
      let(:file) { Rack::Test::UploadedFile.new(file_path, 'application/octet-stream') }

      before do
        import.file.attach(io: File.open(file_path), filename: '2024-03.rec', content_type: 'application/octet-stream')
      end

      it 'completes the import and creates points' do
        expect { service.call }.to change { import.points.count }.from(0)

        expect(import.reload.status).to eq('completed')
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

      it 'completes the import and creates points' do
        expect { service.call }.to change { import.points.count }.from(0)

        expect(import.reload.status).to eq('completed')
      end
    end

    context 'when source is geojson' do
      let(:import) { create(:import, source: 'geojson') }
      let(:file_path) { Rails.root.join('spec/fixtures/files/geojson/export.json') }

      before do
        import.file.attach(io: File.open(file_path), filename: 'export.json',
                           content_type: 'application/json')
      end

      it 'completes the import and creates points' do
        expect { service.call }.to change { import.points.count }.from(0)

        expect(import.reload.status).to eq('completed')
      end
    end

    context 'when source is immich_api' do
      let(:import) { create(:import, source: 'immich_api') }
      let(:file_path) { Rails.root.join('spec/fixtures/files/immich/geodata.json') }

      before do
        import.file.attach(io: File.open(file_path), filename: 'geodata.json',
                           content_type: 'application/json')
      end

      it 'completes the import and creates points' do
        expect { service.call }.to change { import.points.count }.from(0)

        expect(import.reload.status).to eq('completed')
      end
    end

    context 'when source is photoprism_api' do
      let(:import) { create(:import, source: 'photoprism_api') }
      let(:file_path) { Rails.root.join('spec/fixtures/files/immich/geodata.json') }

      before do
        import.file.attach(io: File.open(file_path), filename: 'geodata.json',
                           content_type: 'application/json')
      end

      it 'completes the import and creates points' do
        expect { service.call }.to change { import.points.count }.from(0)

        expect(import.reload.status).to eq('completed')
      end
    end

    context 'when source is csv' do
      let(:import) { create(:import, source: 'csv') }
      let(:file_path) { Rails.root.join('spec/fixtures/files/csv/gpslogger.csv') }

      before do
        import.file.attach(io: File.open(file_path), filename: 'gpslogger.csv',
                           content_type: 'text/csv')
      end

      it 'completes the import and creates points' do
        expect { service.call }.to change { import.points.count }.from(0)

        expect(import.reload.status).to eq('completed')
      end
    end

    context 'when source is tcx' do
      let(:import) { create(:import, source: 'tcx') }
      let(:file_path) { Rails.root.join('spec/fixtures/files/tcx/running.tcx') }

      before do
        import.file.attach(io: File.open(file_path), filename: 'running.tcx',
                           content_type: 'application/octet-stream')
      end

      it 'completes the import and creates points' do
        expect { service.call }.to change { import.points.count }.from(0)

        expect(import.reload.status).to eq('completed')
      end
    end

    context 'when source is fit' do
      let(:import) { create(:import, source: 'fit') }

      before do
        temp = Tempfile.new(['cycling', '.fit'])
        generate_fit_fixture(temp.path)
        import.file.attach(io: File.open(temp.path), filename: 'cycling.fit',
                           content_type: 'application/octet-stream')
      end

      it 'completes the import and creates points' do
        expect { service.call }.to change { import.points.count }.from(0)

        expect(import.reload.status).to eq('completed')
      end
    end

    describe 'archive dispatch' do
      let(:gpx_content) do
        File.read(Rails.root.join('spec/fixtures/files/gpx/gpx_track_single_segment.gpx'))
      end

      context 'when the stored blob is a single-entry zip wrapping one supported file' do
        let(:import) { create(:import) }
        let(:zip_path) do
          path = Rails.root.join('tmp', "single_#{SecureRandom.hex(4)}.zip").to_s
          ::Zip::File.open(path, create: true) do |zf|
            zf.get_output_stream('track.gpx') { |f| f.write(gpx_content) }
          end
          path
        end

        before do
          import.file.attach(io: File.open(zip_path), filename: 'track.gpx.zip',
                             content_type: 'application/zip')
        end

        after { File.delete(zip_path) if File.exist?(zip_path) }

        it 'imports points from the inner file and completes' do
          expect { service.call }.to change { import.points.count }.from(0)
          expect(import.reload.status).to eq('completed')
          expect(import.reload.source).to eq('gpx')
        end
      end

      context 'when the stored blob is a multi-entry zip' do
        let(:import) { create(:import, user:) }
        let(:zip_path) do
          path = Rails.root.join('tmp', "multi_#{SecureRandom.hex(4)}.zip").to_s
          ::Zip::File.open(path, create: true) do |zf|
            zf.get_output_stream('a.gpx') { |f| f.write(gpx_content) }
            zf.get_output_stream('b.gpx') { |f| f.write(gpx_content) }
          end
          path
        end

        before do
          import.file.attach(io: File.open(zip_path), filename: 'archive.zip',
                             content_type: 'application/zip')
        end

        after { File.delete(zip_path) if File.exist?(zip_path) }

        it 'delegates to ZipExtractor which spawns per-entry sub-imports' do
          expect { service.call }.to change { user.imports.count }.by(1) # +2 -1 destroyed
        end
      end

      context 'when the stored blob is a corrupted zip' do
        let(:import) { create(:import) }
        let(:bogus_path) do
          path = Rails.root.join('tmp', "bogus_#{SecureRandom.hex(4)}.zip").to_s
          File.binwrite(path, "PK\x03\x04garbage-not-really-a-zip")
          path
        end

        before do
          import.file.attach(io: File.open(bogus_path), filename: 'bad.zip',
                             content_type: 'application/zip')
        end

        after { File.delete(bogus_path) if File.exist?(bogus_path) }

        it 'does not crash -- falls through to source detection on the raw file and marks failed' do
          service.call
          expect(import.reload.status).to eq('failed')
        end
      end
    end
  end
end

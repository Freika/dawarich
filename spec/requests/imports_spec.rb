# frozen_string_literal: true

require 'rails_helper'
require 'zip'

RSpec.describe 'Imports', type: :request do
  describe 'GET /imports' do
    context 'when user is logged in' do
      let(:user) { create(:user) }

      before do
        sign_in user
      end

      it 'returns http success' do
        get imports_path

        expect(response).to have_http_status(200)
      end

      context 'when user has imports' do
        let!(:import) { create(:import, user:) }

        it 'displays imports' do
          get imports_path

          expect(response.body).to include(import.name)
        end
      end

      context 'when other users have imports' do
        let!(:other_user) { create(:user) }
        let!(:other_import) { create(:import, user: other_user) }
        let!(:user_import) { create(:import, user: user) }

        it 'only displays current users imports' do
          get imports_path

          expect(response.body).to include(user_import.name)
          expect(response.body).not_to include(other_import.name)
        end
      end
    end
  end

  describe 'GET /imports/:id' do
    let(:user) { create(:user) }
    let(:other_user) { create(:user) }
    let(:import) { create(:import, user: user) }
    let(:other_import) { create(:import, user: other_user) }

    context 'when user is logged in' do
      before { sign_in user }

      it 'allows viewing own import' do
        get import_path(import)
        expect(response).to have_http_status(200)
      end

      it 'prevents viewing other users import' do
        get import_path(other_import)

        expect(response).to redirect_to(root_path)
        expect(flash[:alert]).to eq('You are not authorized to perform this action.')
      end
    end

    context 'when user is not logged in' do
      it 'redirects to login' do
        get import_path(import)
        expect(response).to redirect_to(new_user_session_path)
      end
    end
  end

  describe 'GET /imports/:id/download' do
    let(:user) { create(:user) }
    let(:import) { create(:import, user:, name: 'holiday.gpx') }
    let(:gpx_content) { '<gpx><trk><name>Holiday</name></trk></gpx>' }
    let(:zip_path) { create_zip('original.gpx' => gpx_content) }

    before { attach_file(import, zip_path, 'original.gpx.zip', client_wrapped: true) }

    after { File.delete(zip_path) if File.exist?(zip_path) }

    context 'when user is logged in' do
      before { sign_in user }

      it 'downloads the extracted inner file using the renamed import name' do
        get download_import_path(import)

        expect(response).to have_http_status(:ok)
        expect(response.headers['Content-Disposition']).to include('filename="holiday.gpx"')
        expect(response.body).to eq(gpx_content)
        expect(response.body.b).not_to start_with(Archive::Unzipper::ZIP_MAGIC)
      end

      it 'prevents downloading another user\'s import' do
        sign_in create(:user)

        get download_import_path(import)

        expect(response).to redirect_to(root_path)
        expect(flash[:alert]).to eq('You are not authorized to perform this action.')
      end
    end

    context 'when the import is a genuine zip upload' do
      let(:import) { create(:import, user:, name: 'tracks.zip') }
      let(:zip_path) { create_zip('a.gpx' => gpx_content, 'b.gpx' => gpx_content) }

      before do
        import.file.purge
        attach_file(import, zip_path, 'tracks.zip', client_wrapped: false)
        sign_in user
      end

      it 'downloads the original zip without extracting an entry' do
        get download_import_path(import)
        follow_redirect!

        expect(response).to have_http_status(:ok)
        expect(response.headers['Content-Disposition']).to include('filename="tracks.zip"')
        expect(response.body.b).to start_with(Archive::Unzipper::ZIP_MAGIC)
      end
    end

    context 'when the import is a legacy unmarked KML wrapper' do
      let(:import) { create(:import, user:, name: 'route.kml.zip') }
      let(:kml_content) { '<kml><Document><name>Route</name></Document></kml>' }
      let(:zip_path) { create_zip('route.kml' => kml_content) }

      before do
        import.file.purge
        import.file.attach(io: File.open(zip_path), filename: 'route.kml.zip', content_type: 'application/zip')
        sign_in user
      end

      it 'detects the wrapper and downloads the inner KML with its original filename' do
        get download_import_path(import)

        expect(response).to have_http_status(:ok)
        expect(response.headers['Content-Disposition']).to include('filename="route.kml"')
        expect(response.body).to eq(kml_content)
      end
    end

    context 'when user is not logged in' do
      it 'redirects to login' do
        get download_import_path(import)

        expect(response).to redirect_to(new_user_session_path)
      end
    end
  end

  describe 'GET /imports/new' do
    let(:user) { create(:user) }

    context 'when user is active' do
      before do
        allow(user).to receive(:active?).and_return(true)
        sign_in user
      end

      it 'allows access to new import form' do
        get new_import_path
        expect(response).to have_http_status(200)
      end
    end

    context 'when user is inactive' do
      before do
        allow(user).to receive(:active?).and_return(false)
        sign_in user
      end

      it 'prevents access to new import form' do
        get new_import_path

        expect(response).to redirect_to(root_path)
        expect(flash[:alert]).to eq('You are not authorized to perform this action.')
      end
    end

    context 'when user is not logged in' do
      it 'redirects to login' do
        get new_import_path
        expect(response).to redirect_to(new_user_session_path)
      end
    end
  end

  describe 'POST /imports' do
    context 'when user is logged in' do
      let(:user) { create(:user) }

      before { sign_in user }

      context 'when importing owntracks data' do
        let(:file) { fixture_file_upload('owntracks/2024-03.rec', 'text/plain') }
        let(:blob) { create_blob_for_file(file) }
        let(:signed_id) { generate_signed_id_for_blob(blob) }

        it 'queues import job' do
          allow(ActiveStorage::Blob).to receive(:find_signed).with(signed_id).and_return(blob)

          expect do
            post imports_path, params: { import: { source: 'owntracks', files: [signed_id] } }
          end.to have_enqueued_job(Import::ProcessJob).on_queue('imports').at_least(1).times
        end

        it 'creates a new import' do
          allow(ActiveStorage::Blob).to receive(:find_signed).with(signed_id).and_return(blob)

          expect do
            post imports_path, params: { import: { source: 'owntracks', files: [signed_id] } }
          end.to change(user.imports, :count).by(1)

          expect(response).to redirect_to(imports_path)
        end
      end

      context 'when importing gpx data' do
        let(:file) { fixture_file_upload('gpx/gpx_track_single_segment.gpx', 'application/gpx+xml') }
        let(:blob) { create_blob_for_file(file) }
        let(:signed_id) { generate_signed_id_for_blob(blob) }

        it 'queues import job' do
          allow(ActiveStorage::Blob).to receive(:find_signed).with(signed_id).and_return(blob)

          expect do
            post imports_path, params: { import: { source: 'gpx', files: [signed_id] } }
          end.to have_enqueued_job(Import::ProcessJob).on_queue('imports').at_least(1).times
        end

        it 'creates a new import' do
          allow(ActiveStorage::Blob).to receive(:find_signed).with(signed_id).and_return(blob)

          expect do
            post imports_path, params: { import: { source: 'gpx', files: [signed_id] } }
          end.to change(user.imports, :count).by(1)

          expect(response).to redirect_to(imports_path)
        end
      end

      context 'when importing client-wrapped files' do
        it 'uses the original GPX filename as the visible import name' do
          blob = create_blob_from_zip('track.gpx.zip', 'track.gpx' => '<gpx/>')

          post imports_path, params: { import: { files: [upload_descriptor(blob, 'track.gpx', true)] } }

          created_import = user.imports.order(:id).last
          expect(created_import.name).to eq('track.gpx')
          expect(created_import.file.blob.metadata['dawarich_client_wrapped']).to be(true)
        end

        it 'uses the original KML filename as the visible import name' do
          blob = create_blob_from_zip('route.kml.zip', 'route.kml' => '<kml/>')

          post imports_path, params: { import: { files: [upload_descriptor(blob, 'route.kml', true)] } }

          expect(user.imports.order(:id).last.name).to eq('route.kml')
        end

        it 'keeps a genuine zip filename and marks it as unwrapped' do
          blob = create_blob_from_zip('tracks.zip', 'a.gpx' => '<gpx/>', 'b.gpx' => '<gpx/>')

          post imports_path, params: { import: { files: [upload_descriptor(blob, 'tracks.zip', false)] } }

          created_import = user.imports.order(:id).last
          expect(created_import.name).to eq('tracks.zip')
          expect(created_import.file.blob.metadata['dawarich_client_wrapped']).to be(false)
        end
      end

      context 'when an error occurs during import creation' do
        let(:file1) { fixture_file_upload('owntracks/2024-03.rec', 'text/plain') }
        let(:file2) { fixture_file_upload('gpx/gpx_track_single_segment.gpx', 'application/gpx+xml') }
        let(:blob1) { create_blob_for_file(file1) }
        let(:blob2) { create_blob_for_file(file2) }
        let(:signed_id1) { generate_signed_id_for_blob(blob1) }
        let(:signed_id2) { generate_signed_id_for_blob(blob2) }

        it 'deletes any created imports' do
          allow(ActiveStorage::Blob).to receive(:find_signed).with(signed_id1).and_return(blob1)

          allow(ActiveStorage::Blob).to receive(:find_signed).with(signed_id2).and_raise(StandardError, 'Test error')

          allow(ExceptionReporter).to receive(:call)

          expect do
            post imports_path, params: { import: { source: 'owntracks', files: [signed_id1, signed_id2] } }
          end.not_to change(Import, :count)

          expect(response).to have_http_status(422)
          expect(flash[:alert]).not_to be_nil
        end
      end
    end

    context 'when user is inactive' do
      let(:user) { create(:user) }

      before do
        user.update(status: :inactive, active_until: 1.day.ago)
        sign_in user
      end

      it 'blocks import creation' do
        post imports_path, params: { import: { source: 'owntracks', files: [] } }

        expect(response).to redirect_to(root_path)
        expect(flash[:notice]).to eq('Your account is not active.')
      end
    end
  end

  describe 'GET /imports/new' do
    context 'when user is logged in' do
      let(:user) { create(:user) }

      before { sign_in user }

      it 'returns http success' do
        get new_import_path

        expect(response).to have_http_status(200)
      end

      context 'when user is a trial user' do
        let(:user) { create(:user, status: :trial) }

        it 'returns http success' do
          get new_import_path

          expect(response).to have_http_status(200)
        end
      end
    end
  end

  describe 'DELETE /imports/:id' do
    context 'when user is logged in' do
      let(:user) { create(:user) }
      let!(:import) { create(:import, user:) }

      before { sign_in user }

      it 'deletes the import' do
        expect do
          delete import_path(import)
        end.to have_enqueued_job(Imports::DestroyJob).with(import.id)

        expect(response).to redirect_to(imports_path)
        expect(import.reload).to be_deleting
      end
    end
  end

  describe 'GET /imports/:id/edit' do
    context 'when user is logged in' do
      let(:user) { create(:user) }
      let(:import) { create(:import, user:) }

      before { sign_in user }

      it 'returns http success' do
        get edit_import_path(import)

        expect(response).to have_http_status(200)
      end
    end
  end

  describe 'PATCH /imports/:id' do
    context 'when user is logged in' do
      let(:user) { create(:user) }
      let(:import) { create(:import, user:) }

      before { sign_in user }

      it 'updates the import' do
        patch import_path(import), params: { import: { name: 'New Name' } }

        expect(import.reload.name).to eq('New Name')
        expect(response).to redirect_to(imports_path)
      end
    end
  end

  def create_blob_for_file(file)
    ActiveStorage::Blob.create_and_upload!(
      io: file.open,
      filename: file.original_filename,
      content_type: file.content_type
    )
  end

  def generate_signed_id_for_blob(blob)
    blob.signed_id
  end

  def create_zip(entries)
    path = Rails.root.join('tmp', "request_import_#{SecureRandom.hex(4)}.zip").to_s
    ::Zip::File.open(path, create: true) do |zip|
      entries.each do |filename, content|
        zip.get_output_stream(filename) { |entry| entry.write(content) }
      end
    end
    path
  end

  def create_blob_from_zip(filename, entries)
    path = create_zip(entries)
    ActiveStorage::Blob.create_and_upload!(
      io: File.open(path), filename:, content_type: 'application/zip'
    )
  ensure
    File.delete(path) if path && File.exist?(path)
  end

  def upload_descriptor(blob, original_filename, client_wrapped)
    {
      signed_id: blob.signed_id,
      original_filename:,
      client_wrapped:
    }.to_json
  end

  def attach_file(import, path, filename, client_wrapped:)
    import.file.attach(io: File.open(path), filename:, content_type: 'application/zip')
    import.file.blob.update!(
      metadata: import.file.blob.metadata.merge(
        'dawarich_client_wrapped' => client_wrapped,
        'dawarich_original_filename' => filename.delete_suffix('.zip')
      )
    )
  end
end

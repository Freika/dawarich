# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Imports', type: :request do
  let!(:user) { create(:user) }
  let(:api_key) { user.api_key }

  describe 'GET /api/v1/imports' do
    context 'with valid api_key' do
      let!(:imports) { create_list(:import, 3, user: user) }

      it 'returns a list of imports' do
        get api_v1_imports_url(api_key: api_key)

        expect(response).to have_http_status(:ok)

        json = JSON.parse(response.body)
        expect(json.size).to eq(3)
        expect(json.first).to include('id', 'name', 'source', 'status', 'created_at')
      end

      it 'returns pagination headers' do
        get api_v1_imports_url(api_key: api_key, page: 1, per_page: 2)

        expect(response).to have_http_status(:ok)
        expect(response.headers['X-Current-Page']).to eq('1')
        expect(response.headers['X-Total-Pages']).to eq('2')
      end

      it 'does not return other users imports' do
        other_user = create(:user)
        create(:import, user: other_user)

        get api_v1_imports_url(api_key: api_key)

        json = JSON.parse(response.body)
        expect(json.size).to eq(3)
      end
    end

    context 'with invalid api_key' do
      it 'returns unauthorized' do
        get api_v1_imports_url(api_key: 'invalid')

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe 'GET /api/v1/imports/:id' do
    let!(:import) { create(:import, user: user) }

    context 'with valid api_key' do
      it 'returns the import' do
        get api_v1_import_url(import, api_key: api_key)

        expect(response).to have_http_status(:ok)

        json = JSON.parse(response.body)
        expect(json['id']).to eq(import.id)
        expect(json['name']).to eq(import.name)
        expect(json['status']).to eq(import.status)
      end
    end

    context 'when import belongs to another user' do
      let(:other_import) { create(:import, user: create(:user)) }

      it 'returns not found' do
        get api_v1_import_url(other_import, api_key: api_key)

        expect(response).to have_http_status(:not_found)
      end
    end

    context 'with invalid api_key' do
      it 'returns unauthorized' do
        get api_v1_import_url(import, api_key: 'invalid')

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe 'POST /api/v1/imports' do
    context 'with a valid GPX file' do
      let(:file) { fixture_file_upload('gpx/gpx_track_single_segment.gpx', 'application/gpx+xml') }

      it 'creates an import and enqueues processing' do
        expect do
          post api_v1_imports_url(api_key: api_key), params: { file: file }
        end.to change(user.imports, :count)
          .by(1)
          .and have_enqueued_job(Import::ProcessJob).on_queue('imports')

        expect(response).to have_http_status(:created)

        json = JSON.parse(response.body)
        expect(json['name']).to eq('gpx_track_single_segment.gpx')
        expect(json['status']).to eq('created')
      end

      it 'handles duplicate filenames by appending timestamp' do
        create(:import, user: user, name: 'gpx_track_single_segment.gpx')

        post api_v1_imports_url(api_key: api_key), params: { file: file }

        expect(response).to have_http_status(:created)

        json = JSON.parse(response.body)
        expect(json['name']).to match(/gpx_track_single_segment_\d{8}_\d{6}\.gpx/)
      end
    end

    context 'with an unsupported file type' do
      it 'returns unprocessable entity with file type error' do
        tmpfile = Tempfile.new(['malicious', '.exe'])
        tmpfile.write('not a valid import file')
        tmpfile.rewind

        file = Rack::Test::UploadedFile.new(tmpfile.path, 'application/octet-stream')

        post api_v1_imports_url(api_key: api_key), params: { file: file }

        expect(response).to have_http_status(:unprocessable_entity)

        json = JSON.parse(response.body)
        expect(json['error']).to include('Unsupported file type')
        expect(json['error']).to include('.exe')
      ensure
        tmpfile&.close
        tmpfile&.unlink
      end
    end

    context 'without a file' do
      it 'returns unprocessable entity' do
        post api_v1_imports_url(api_key: api_key)

        expect(response).to have_http_status(:unprocessable_entity)

        json = JSON.parse(response.body)
        expect(json['error']).to include('file')
      end
    end

    context 'with invalid api_key' do
      let(:file) { fixture_file_upload('gpx/gpx_track_single_segment.gpx', 'application/gpx+xml') }

      it 'returns unauthorized' do
        post api_v1_imports_url(api_key: 'invalid'), params: { file: file }

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when user is inactive' do
      let(:file) { fixture_file_upload('gpx/gpx_track_single_segment.gpx', 'application/gpx+xml') }

      before { user.update(status: :inactive, active_until: 1.day.ago) }

      it 'returns unauthorized' do
        post api_v1_imports_url(api_key: api_key), params: { file: file }

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when user is inactive but active_until is in the future' do
      let(:file) { fixture_file_upload('gpx/gpx_track_single_segment.gpx', 'application/gpx+xml') }

      before { user.update(status: :inactive, active_until: 1.day.from_now) }

      it 'returns unauthorized' do
        post api_v1_imports_url(api_key: api_key), params: { file: file }

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end
end

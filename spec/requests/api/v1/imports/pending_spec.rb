# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'POST /api/v1/imports/pending' do
  include ActiveSupport::Testing::TimeHelpers

  before { allow(DawarichSettings).to receive(:self_hosted?).and_return(false) }

  context 'on a self-hosted instance' do
    before { allow(DawarichSettings).to receive(:self_hosted?).and_return(true) }

    it 'returns 404 — the tools handoff is Cloud-only' do
      post '/api/v1/imports/pending',
           params: { file: fixture_file_upload('sample-export.zip', 'application/zip'),
                     original_filename: 'sample-export.zip' },
           headers: { 'Origin' => 'https://dawarich.app' }

      expect(response).to have_http_status(:not_found)
    end
  end

  context 'with an empty file' do
    it 'rejects a 0-byte upload at intake' do
      empty = Rack::Test::UploadedFile.new(StringIO.new(''), 'application/zip',
                                           original_filename: 'empty.zip')
      post '/api/v1/imports/pending',
           params: { file: empty, original_filename: 'empty.zip' },
           headers: { 'Origin' => 'https://dawarich.app' }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to eq('File is empty')
    end
  end
  let(:valid_origin) { 'https://dawarich.app' }
  let(:file) do
    Rack::Test::UploadedFile.new(
      Rails.root.join('spec/fixtures/files/sample-export.zip'),
      'application/zip'
    )
  end
  let(:headers) { { 'HTTP_ORIGIN' => valid_origin } }
  let(:params) { { file: file, original_filename: 'records.zip', source_hint: 'google_records' } }

  context 'with valid request' do
    it 'returns 201' do
      post '/api/v1/imports/pending', params: params, headers: headers
      expect(response).to have_http_status(:created)
    end

    it 'returns claim_ticket, expires_at, and claim_url in the response' do
      post '/api/v1/imports/pending', params: params, headers: headers
      body = JSON.parse(response.body)
      expect(body).to include('claim_ticket', 'expires_at', 'claim_url')
      expect(body['claim_ticket']).to match(/\A[0-9a-f-]{36}\z/)
      expect(body['claim_url']).to include("import_ticket=#{body['claim_ticket']}")
      expect(body['claim_url']).to start_with('http://www.example.com/users/sign_up')
    end

    it 'creates a PendingImport with attached file' do
      expect { post '/api/v1/imports/pending', params: params, headers: headers }
        .to change(PendingImport, :count).by(1)
      pending = PendingImport.last
      expect(pending.file).to be_attached
      expect(pending.original_filename).to eq('records.zip')
      expect(pending.origin).to eq(valid_origin)
      expect(pending.source_hint).to eq('google_records')
    end

    it 'sets expires_at to approximately 24 hours from now' do
      post '/api/v1/imports/pending', params: params, headers: headers
      pending = PendingImport.last
      expect(pending.expires_at).to be_within(1.minute).of(24.hours.from_now)
    end
  end

  context 'origin enforcement' do
    it 'returns 403 when Origin header is missing' do
      post '/api/v1/imports/pending', params: params
      expect(response).to have_http_status(:forbidden)
    end

    it 'returns 403 when Origin is not in allowlist' do
      post '/api/v1/imports/pending', params: params, headers: { 'HTTP_ORIGIN' => 'https://evil.example.com' }
      expect(response).to have_http_status(:forbidden)
    end

    it 'accepts requests from *.dawarich.pages.dev' do
      post '/api/v1/imports/pending', params: params,
                                      headers: { 'HTTP_ORIGIN' => 'https://preview-abc.dawarich.pages.dev' }
      expect(response).to have_http_status(:created)
    end
  end

  context 'validation' do
    it 'returns 400 when file param is missing' do
      post '/api/v1/imports/pending',
           params: { original_filename: 'records.zip' },
           headers: headers
      expect(response).to have_http_status(:bad_request)
    end

    it 'returns 400 when original_filename is missing' do
      post '/api/v1/imports/pending', params: { file: file }, headers: headers
      expect(response).to have_http_status(:bad_request)
    end

    it 'returns 422 when file extension is not allowed' do
      bad_file = Rack::Test::UploadedFile.new(
        StringIO.new('hello'), 'text/plain', original_filename: 'notes.txt'
      )
      post '/api/v1/imports/pending',
           params: { file: bad_file, original_filename: 'notes.txt' },
           headers: headers
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'returns 413 when file exceeds 100MB' do
      large = Rack::Test::UploadedFile.new(
        StringIO.new('x' * (101 * 1024 * 1024)),
        'application/zip',
        original_filename: 'huge.zip'
      )
      post '/api/v1/imports/pending',
           params: { file: large, original_filename: 'huge.zip' },
           headers: headers
      expect(response).to have_http_status(:payload_too_large)
    end
  end

  context 'rate limiting' do
    before do
      Rack::Attack.enabled = true
      Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new
      Rack::Attack.reset!
    end

    after do
      Rack::Attack.reset!
      Rack::Attack.enabled = false
    end

    it 'returns 429 after 60 requests from the same IP within an hour' do
      60.times do
        post '/api/v1/imports/pending',
             params: params,
             headers: headers.merge('REMOTE_ADDR' => '1.2.3.4')
      end

      post '/api/v1/imports/pending',
           params: params,
           headers: headers.merge('REMOTE_ADDR' => '1.2.3.4')

      expect(response).to have_http_status(:too_many_requests)
    end
  end

  context 'storage quota' do
    let(:quota_cache) { ActiveSupport::Cache::MemoryStore.new }

    before do
      allow(Rails).to receive(:cache).and_return(quota_cache)
      stub_const('Api::V1::Imports::PendingController::STORAGE_QUOTA_BYTES', file.size)
    end

    it 'rejects uploads that exceed the aggregate daily byte quota' do
      post '/api/v1/imports/pending', params: params, headers: headers
      expect(response).to have_http_status(:created)

      expect do
        post '/api/v1/imports/pending', params: params, headers: headers
      end.not_to change(PendingImport, :count)

      expect(response).to have_http_status(:too_many_requests)
      expect(response.parsed_body['error']).to eq('Pending import storage capacity exceeded')
    end

    it 'releases the original quota reservation when persistence fails after midnight' do
      allow_any_instance_of(PendingImport).to receive(:save!) do
        travel 2.seconds
        raise ActiveRecord::RecordInvalid
      end

      travel_to(Time.utc(2026, 7, 10, 23, 59, 59)) do
        post '/api/v1/imports/pending', params: params, headers: headers

        expect(response).to have_http_status(:internal_server_error)
        expect(quota_cache.read('pending_imports/storage_bytes/2026-07-10')).to eq(0)
        expect(quota_cache.read('pending_imports/storage_bytes/2026-07-11')).to be_nil
      end
    end
  end
end

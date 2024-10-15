# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Imports', type: :request do
  before do
    stub_request(:any, 'https://api.github.com/repos/Freika/dawarich/tags')
      .to_return(status: 200, body: '[{"name": "1.0.0"}]', headers: {})
  end

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
    end
  end

  describe 'POST /imports' do
    context 'when user is logged in' do
      let(:user) { create(:user) }

      before { sign_in user }

      context 'when importing owntracks data' do
        let(:file) { fixture_file_upload('owntracks/2024-03.rec', 'application/json') }

        it 'queues import job' do
          expect do
            post imports_path, params: { import: { source: 'owntracks', files: [file] } }
          end.to have_enqueued_job(ImportJob).on_queue('imports').at_least(1).times
        end

        it 'creates a new import' do
          expect do
            post imports_path, params: { import: { source: 'owntracks', files: [file] } }
          end.to change(user.imports, :count).by(1)

          expect(response).to redirect_to(imports_path)
        end
      end

      context 'when importing gpx data' do
        let(:file) { fixture_file_upload('gpx/gpx_track_single_segment.gpx', 'application/gpx+xml') }

        it 'queues import job' do
          expect do
            post imports_path, params: { import: { source: 'gpx', files: [file] } }
          end.to have_enqueued_job(ImportJob).on_queue('imports').at_least(1).times
        end

        it 'creates a new import' do
          expect do
            post imports_path, params: { import: { source: 'gpx', files: [file] } }
          end.to change(user.imports, :count).by(1)

          expect(response).to redirect_to(imports_path)
        end
      end
    end
  end
end

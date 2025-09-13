# frozen_string_literal: true

require 'rails_helper'

RSpec.describe '/exports', type: :request do
  let(:user) { create(:user) }
  let(:params) { { start_at: 1.day.ago, end_at: Time.zone.now } }

  before do
    stub_request(:any, 'https://api.github.com/repos/Freika/dawarich/tags')
      .to_return(status: 200, body: '[{"name": "1.0.0"}]', headers: {})
  end

  describe 'GET /index' do
    context 'when user is not logged in' do
      it 'redirects to the login page' do
        get exports_url

        expect(response).to redirect_to(new_user_session_url)
      end
    end

    context 'when user is logged in' do
      before do
        sign_in user
      end

      it 'renders a successful response' do
        get exports_url

        expect(response).to be_successful
      end
    end
  end

  describe 'POST /create' do
    before { sign_in user }

    context 'with valid parameters' do
      let(:points) do
        (1..10).map do |i|
          create(:point, user:, timestamp: 1.day.ago + i.minutes)
        end
      end

      it 'creates a new Export' do
        expect { post exports_url, params: }.to change(Export, :count).by(1)
      end

      it 'redirects to the exports index page' do
        post(exports_url, params:)

        expect(response).to redirect_to(exports_url)
      end

      it 'enqueues a job to process the export' do
        ActiveJob::Base.queue_adapter = :test

        expect { post exports_url, params: }.to have_enqueued_job(ExportJob)
      end
    end

    context 'with invalid parameters' do
      let(:params) { { start_at: nil, end_at: nil } }

      it 'does not create a new Export' do
        expect { post exports_url, params: }.to change(Export, :count).by(0)
      end

      it 'renders a response with 422 status (i.e. to display the "new" template)' do
        post(exports_url, params:)

        expect(response).to have_http_status(:unprocessable_content)
      end
    end
  end

  describe 'DELETE /destroy' do
    let!(:export) { create(:export, user:, name: 'export.json') }

    before { sign_in user }

    it 'destroys the requested export' do
      expect { delete export_url(export) }.to change(Export, :count).by(-1)
    end

    it 'redirects to the exports list' do
      delete export_url(export)

      expect(response).to redirect_to(exports_url)
    end
  end
end

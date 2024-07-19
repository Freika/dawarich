# frozen_string_literal: true

require 'rails_helper'

RSpec.describe '/settings/background_jobs', type: :request do
  before do
    stub_request(:any, 'https://api.github.com/repos/Freika/dawarich/tags')
      .to_return(status: 200, body: '[{"name": "1.0.0"}]', headers: {})
  end

  context 'when user is not authenticated' do
    it 'redirects to sign in page' do
      get settings_background_jobs_url

      expect(response).to redirect_to(new_user_session_url)
    end
  end

  context 'when user is authenticated' do
    before { sign_in create(:user) }

    context 'when user is not an admin' do
      it 'redirects to root page' do
        get settings_background_jobs_url

        expect(response).to redirect_to(root_url)
        expect(flash[:notice]).to eq('You are not authorized to perform this action.')
      end
    end

    context 'when user is an admin' do
      before { sign_in create(:user, :admin) }

      describe 'GET /index' do
        it 'renders a successful response' do
          get settings_background_jobs_url

          expect(response).to be_successful
        end
      end

      describe 'POST /create' do
        let(:params) { { job_name: 'start_reverse_geocoding' } }

        context 'with valid parameters' do
          it 'enqueues a new job' do
            expect do
              post settings_background_jobs_url, params:
            end.to have_enqueued_job(EnqueueReverseGeocodingJob)
          end

          it 'redirects to the created settings_background_job' do
            post(settings_background_jobs_url, params:)

            expect(response).to redirect_to(settings_background_jobs_url)
          end
        end
      end

      describe 'DELETE /destroy' do
        it 'clears the Sidekiq queue' do
          queue = instance_double(Sidekiq::Queue)
          allow(Sidekiq::Queue).to receive(:new).and_return(queue)

          expect(queue).to receive(:clear)

          delete settings_background_job_url('queue_name')
        end

        it 'redirects to the settings_background_jobs list' do
          delete settings_background_job_url('queue_name')

          expect(response).to redirect_to(settings_background_jobs_url)
        end
      end
    end
  end
end

# frozen_string_literal: true

require 'rails_helper'

RSpec.describe '/settings/background_jobs', type: :request do
  context 'when Dawarich is in self-hosted mode' do
    before do
      allow(DawarichSettings).to receive(:self_hosted?).and_return(true)
    end

    context 'when user is not authenticated' do
      it 'redirects to sign in page' do
        get settings_background_jobs_url

        expect(response).to redirect_to(root_url)
        expect(flash[:alert]).to eq('You are not authorized to perform this action.')
      end
    end

    context 'when user is authenticated' do
      let(:user) { create(:user, admin: false) }

      before { sign_in user }

      context 'when user is not an admin' do
        it 'redirects to root page' do
          get settings_background_jobs_url

          expect(response).to redirect_to(root_url)
          expect(flash[:alert]).to eq('You are not authorized to perform this action.')
        end

        context 'when job name is start_immich_import' do
          it 'redirects to imports page' do
            post settings_background_jobs_url, params: { job_name: 'start_immich_import' }

            expect(response).to redirect_to(imports_url)
          end

          it 'enqueues a new job' do
            expect do
              post settings_background_jobs_url, params: { job_name: 'start_immich_import' }
            end.to have_enqueued_job(EnqueueBackgroundJob)
          end
        end

        context 'when job name is start_photoprism_import' do
          it 'redirects to imports page' do
            get settings_background_jobs_url, params: { job_name: 'start_photoprism_import' }
          end

          it 'enqueues a new job' do
            expect do
              post settings_background_jobs_url, params: { job_name: 'start_photoprism_import' }
            end.to have_enqueued_job(EnqueueBackgroundJob)
          end
        end

        context 'when job name is start_google_photos_import' do
          it 'redirects to imports page' do
            post settings_background_jobs_url, params: { job_name: 'start_google_photos_import' }

            expect(response).to redirect_to(imports_url)
          end

          it 'enqueues a new job' do
            expect do
              post settings_background_jobs_url, params: { job_name: 'start_google_photos_import' }
            end.to have_enqueued_job(EnqueueBackgroundJob)
          end
        end

        context 'when job is submitted twice quickly (debounce)' do
          it 'blocks the second request' do
            post settings_background_jobs_url, params: { job_name: 'start_immich_import' }
            expect(response).to redirect_to(imports_url)
            expect(flash[:notice]).to eq('Job was successfully created.')

            post settings_background_jobs_url, params: { job_name: 'start_immich_import' }
            expect(response).to redirect_to(imports_url)
            expect(flash[:alert]).to eq('Please wait before starting another import job.')
          end

          it 'only enqueues one job' do
            expect do
              post settings_background_jobs_url, params: { job_name: 'start_immich_import' }
              post settings_background_jobs_url, params: { job_name: 'start_immich_import' }
            end.to have_enqueued_job(EnqueueBackgroundJob).exactly(:once)
          end

          it 'allows different job types to be submitted' do
            expect do
              post settings_background_jobs_url, params: { job_name: 'start_immich_import' }
              post settings_background_jobs_url, params: { job_name: 'start_photoprism_import' }
            end.to have_enqueued_job(EnqueueBackgroundJob).exactly(:twice)
          end
        end
      end

      context 'when user is an admin' do
        let(:admin_user) { create(:user, :admin) }

        before { sign_in admin_user }

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
              end.to have_enqueued_job(EnqueueBackgroundJob)
            end

            it 'redirects to the created settings_background_job' do
              post(settings_background_jobs_url, params:)

              expect(response).to redirect_to(settings_background_jobs_url)
            end
          end
        end

        describe 'PATCH /update' do
          it 'enables visits suggestions' do
            patch settings_background_jobs_url, params: { settings: { 'visits_suggestions_enabled' => 'true' } }

            expect(response).to redirect_to(settings_background_jobs_url)
            expect(flash[:notice]).to eq('Settings updated')
            expect(admin_user.reload.settings['visits_suggestions_enabled']).to eq('true')
          end

          it 'disables visits suggestions' do
            patch settings_background_jobs_url, params: { settings: { 'visits_suggestions_enabled' => 'false' } }

            expect(response).to redirect_to(settings_background_jobs_url)
            expect(admin_user.reload.settings['visits_suggestions_enabled']).to eq('false')
          end
        end
      end

      context 'when non-admin user patches update' do
        it 'rejects the request' do
          patch settings_background_jobs_url, params: { settings: { 'visits_suggestions_enabled' => 'true' } }

          expect(response).to redirect_to(root_url)
          expect(flash[:alert]).to eq('You are not authorized to perform this action.')
        end
      end
    end
  end

  context 'when Dawarich is not in self-hosted mode' do
    before do
      allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
    end

    context 'when user is not authenticated' do
      it 'redirects to sign in page' do
        get settings_background_jobs_url

        expect(response).to redirect_to(root_url)
        expect(flash[:alert]).to eq('You are not authorized to perform this action.')
      end
    end

    context 'when user is authenticated' do
      let(:user) { create(:user) }

      before { sign_in user }

      describe 'GET /index' do
        it 'redirects to root page' do
          get settings_background_jobs_url

          expect(response).to redirect_to(root_url)
          expect(flash[:alert]).to eq('You are not authorized to perform this action.')
        end

        context 'when user is an admin' do
          before { sign_in create(:user, :admin) }

          it 'redirects to root page' do
            get settings_background_jobs_url

            expect(response).to redirect_to(root_url)
            expect(flash[:alert]).to eq('You are not authorized to perform this action.')
          end
        end
      end

      describe 'POST /create' do
        it 'redirects to root page' do
          post settings_background_jobs_url, params: { job_name: 'start_reverse_geocoding' }

          expect(response).to redirect_to(root_url)
          expect(flash[:alert]).to eq('You are not authorized to perform this action.')
        end

        context 'when job name is start_immich_import' do
          it 'redirects to imports page' do
            post settings_background_jobs_url, params: { job_name: 'start_immich_import' }

            expect(response).to redirect_to(root_url)
            expect(flash[:alert]).to eq('You are not authorized to perform this action.')
          end
        end

        context 'when job name is start_photoprism_import' do
          it 'redirects to imports page' do
            post settings_background_jobs_url, params: { job_name: 'start_photoprism_import' }

            expect(response).to redirect_to(root_url)
            expect(flash[:alert]).to eq('You are not authorized to perform this action.')
          end
        end

        context 'when user is an admin' do
          before { sign_in create(:user, :admin) }

          it 'redirects to root page' do
            get settings_background_jobs_url

            expect(response).to redirect_to(root_url)
            expect(flash[:alert]).to eq('You are not authorized to perform this action.')
          end
        end
      end
    end
  end
end

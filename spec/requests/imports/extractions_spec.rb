# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Imports::Extractions' do
  include ActiveJob::TestHelper

  let(:user) { create(:user) }
  let(:import) do
    create(:import, user: user, source: :google_phone_takeout,
                    additional_data_extraction_status: :completed,
                    additional_data_extraction: { 'counts' => { 'visits' => 1 } })
  end

  describe 'DELETE /imports/:import_id/extraction' do
    context 'when signed in as the owner' do
      before { sign_in user }

      it 'enqueues removal of the extracted artifacts' do
        place = create(:place, user: user, import_id: import.id)
        create(:visit, user: user, place: place, import_id: import.id)

        expect { delete import_extraction_path(import) }
          .to have_enqueued_job(EnhancedImport::DestroyJob).with(import.id)

        expect(response).to redirect_to(import_path(import))
      end

      it 'removes the artifacts when the job runs' do
        place = create(:place, user: user, import_id: import.id)
        create(:visit, user: user, place: place, import_id: import.id)

        delete import_extraction_path(import)
        perform_enqueued_jobs

        expect(Visit.where(import_id: import.id).count).to eq(0)
        expect(import.reload.additional_data_extraction_not_attempted?).to be true
      end

      it 'refuses when nothing has been extracted' do
        import.update_columns(
          additional_data_extraction_status: Import.additional_data_extraction_statuses[:not_attempted],
          additional_data_extraction: {}
        )

        delete import_extraction_path(import)

        expect(response).not_to have_http_status(:success)
      end
    end

    context 'when signed in as another user' do
      let(:intruder) { create(:user) }

      before { sign_in intruder }

      it 'does not remove anything' do
        place = create(:place, user: user, import_id: import.id)
        create(:visit, user: user, place: place, import_id: import.id)

        expect { delete import_extraction_path(import) }
          .not_to have_enqueued_job(EnhancedImport::DestroyJob)
      end
    end

    context 'when signed out' do
      it 'redirects to sign in' do
        delete import_extraction_path(import)

        expect(response).to redirect_to(new_user_session_path)
      end
    end
  end
end

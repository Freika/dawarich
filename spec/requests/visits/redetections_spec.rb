# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Visits::Redetections', type: :request do
  let(:user) { create(:user) }
  before { sign_in user }

  describe 'POST /redetections' do
    it 'enqueues the job and redirects with notice when no cooldown active' do
      # New accounts are born re-detected (DB default), which starts the cooldown.
      user.update!(visits_redetected_at: 2.hours.ago)

      expect do
        post visits_redetections_path
      end.to have_enqueued_job(Visits::FullHistoryRedetectJob).with(user.id)

      expect(response).to redirect_to(settings_visits_path)
      expect(flash[:notice]).to match(/queued/i)
    end

    it 'rejects with 429 when within cooldown' do
      user.update!(visits_redetected_at: 30.minutes.ago)

      expect { post visits_redetections_path }.not_to have_enqueued_job(Visits::FullHistoryRedetectJob)
      expect(response).to have_http_status(:too_many_requests)
    end

    it 'requires authentication' do
      sign_out user
      post visits_redetections_path
      expect(response).to redirect_to(new_user_session_path)
    end
  end
end

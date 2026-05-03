# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Tracks::Recalculations', type: :request do
  let(:user) { create(:user) }

  before { sign_in user }

  describe 'POST /tracks/recalculation' do
    it 'enqueues TransportationModeRecalculationJob and returns turbo-stream' do
      expect do
        post tracks_recalculation_path,
             headers: { 'Accept' => 'text/vnd.turbo-stream.html' }
      end.to have_enqueued_job(Tracks::TransportationModeRecalculationJob).with(user.id)

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq('text/vnd.turbo-stream.html')
      expect(response.body).to include('Re-classification started')
    end

    it 'is a no-op when recalculation is already in progress' do
      allow_any_instance_of(Tracks::TransportationRecalculationStatus)
        .to receive(:in_progress?).and_return(true)

      expect do
        post tracks_recalculation_path,
             headers: { 'Accept' => 'text/vnd.turbo-stream.html' }
      end.not_to have_enqueued_job(Tracks::TransportationModeRecalculationJob)

      expect(response.body).to include('already running')
    end
  end
end

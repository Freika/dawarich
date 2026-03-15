# frozen_string_literal: true

require 'rails_helper'

RSpec.describe VideoExportsController, type: :request do
  let(:user) { create(:user) }

  before do
    allow(DawarichSettings).to receive(:video_service_enabled?).and_return(true)
    sign_in user
  end

  describe 'GET /video_exports' do
    it 'returns success for authenticated user' do
      get video_exports_path

      expect(response).to have_http_status(:ok)
    end

    it 'shows only current user exports' do
      create(:video_export, user: user)
      create(:video_export) # other user's export

      get video_exports_path

      expect(response.body).to include('video_exports')
    end

    context 'when not authenticated' do
      before { sign_out user }

      it 'redirects to sign in' do
        get video_exports_path

        expect(response).to redirect_to(new_user_session_path)
      end
    end

    context 'when video service is disabled' do
      before do
        allow(DawarichSettings).to receive(:video_service_enabled?).and_return(false)
      end

      it 'redirects to root with alert' do
        get video_exports_path

        expect(response).to redirect_to(root_path)
        expect(flash[:alert]).to eq('Video service is not available.')
      end
    end
  end

  describe 'DELETE /video_exports/:id' do
    let!(:video_export) { create(:video_export, user: user) }

    it 'deletes the export and redirects' do
      expect do
        delete video_export_path(video_export)
      end.to change(VideoExport, :count).by(-1)

      expect(response).to redirect_to(video_exports_url)
    end

    it 'cannot delete another user export' do
      other_export = create(:video_export)

      expect do
        delete video_export_path(other_export)
      end.not_to change(VideoExport, :count)

      expect(response).to have_http_status(:not_found)
    end
  end
end

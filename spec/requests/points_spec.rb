# frozen_string_literal: true

require 'rails_helper'

RSpec.describe '/points', type: :request do
  describe 'GET /index' do
    before do
      stub_request(:any, 'https://api.github.com/repos/Freika/dawarich/tags')
        .to_return(status: 200, body: '[{"name": "1.0.0"}]', headers: {})
    end

    context 'when user is not logged in' do
      it 'redirects to login page' do
        get points_url
        expect(response).to redirect_to(new_user_session_path)
      end
    end

    context 'when user is logged in' do
      before do
        sign_in create(:user)
      end

      it 'renders a successful response' do
        get points_url

        expect(response).to be_successful
      end
    end
  end

  describe 'DELETE /bulk_destroy' do
    let(:user) { create(:user) }
    let(:point1) { create(:point, user:) }
    let(:point2) { create(:point, user:) }

    before do
      sign_in user
    end

    it 'destroys the selected points' do
      delete bulk_destroy_points_url, params: { point_ids: [point1.id, point2.id] }

      expect(Point.find_by(id: point1.id)).to be_nil
      expect(Point.find_by(id: point2.id)).to be_nil
    end

    it 'returns a 303 status code' do
      delete bulk_destroy_points_url, params: { point_ids: [point1.id, point2.id] }

      expect(response).to have_http_status(303)
    end

    it 'redirects to the points list' do
      delete bulk_destroy_points_url, params: { point_ids: [point1.id, point2.id] }

      expect(response).to redirect_to(points_url)
    end

    it 'preserves the start_at and end_at parameters' do
      delete bulk_destroy_points_url,
             params: { point_ids: [point1.id, point2.id], start_at: '2021-01-01', end_at: '2021-01-02' }

      expect(response).to redirect_to(points_url(start_at: '2021-01-01', end_at: '2021-01-02'))
    end
  end
end

# frozen_string_literal: true

require 'rails_helper'

RSpec.describe '/points', type: :request do
  describe 'GET /index' do
    context 'when user is not logged in' do
      it 'redirects to login page' do
        get points_url
        expect(response).to redirect_to(new_user_session_path)
      end
    end

    context 'when user is logged in' do
      let(:user) { create(:user) }

      before do
        sign_in user
      end

      it 'renders a successful response' do
        get points_url

        expect(response).to be_successful
      end

      context 'when reverse geocoding is enabled' do
        let(:recent_timestamp) { 1.day.ago.to_i }

        before do
          allow(DawarichSettings).to receive(:reverse_geocoding_enabled?).and_return(true)
        end

        it 'displays address from geodata properties when available' do
          create(:point, user:, timestamp: recent_timestamp, geodata: {
                   'properties' => { 'street' => 'Main St', 'city' => 'Berlin', 'country' => 'Germany' }
                 })

          get points_url

          expect(response.body).to include('Main St, Berlin, Germany')
        end

        it 'falls back to city and country_name when geodata is empty' do
          create(:point, user:, timestamp: recent_timestamp, geodata: {}, city: 'Paris', country: 'France')

          get points_url

          expect(response.body).to include('Paris, France')
        end

        it 'falls back to city and country_name when geodata has no properties' do
          create(:point, user:, timestamp: recent_timestamp,
                         geodata: { 'type' => 'Feature' }, city: 'Tokyo', country: 'Japan')

          get points_url

          expect(response.body).to include('Tokyo, Japan')
        end
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

    context 'when no points are selected' do
      it 'redirects to the points list' do
        delete bulk_destroy_points_url, params: { point_ids: [] }

        expect(response).to redirect_to(points_url)
        expect(flash[:alert]).to eq('No points selected.')
      end
    end
  end
end

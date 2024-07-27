# frozen_string_literal: true

require 'rails_helper'

RSpec.describe '/api/v1/areas', type: :request do
  let(:user) { create(:user) }

  describe 'GET /index' do
    it 'renders a successful response' do
      get api_v1_areas_url(api_key: user.api_key)
      expect(response).to be_successful
    end
  end

  describe 'POST /create' do
    context 'with valid parameters' do
      let(:valid_attributes) do
        attributes_for(:area)
      end

      it 'creates a new Area' do
        expect do
          post api_v1_areas_url(api_key: user.api_key), params: { area: valid_attributes }
        end.to change(Area, :count).by(1)
      end

      it 'redirects to the created api_v1_area' do
        post api_v1_areas_url(api_key: user.api_key), params: { area: valid_attributes }

        expect(response).to have_http_status(:created)
      end
    end

    context 'with invalid parameters' do
      let(:invalid_attributes) do
        attributes_for(:area, name: nil)
      end

      it 'does not create a new Area' do
        expect do
          post api_v1_areas_url(api_key: user.api_key), params: { area: invalid_attributes }
        end.to change(Area, :count).by(0)
      end

      it 'renders a response with 422 status' do
        post api_v1_areas_url(api_key: user.api_key), params: { area: invalid_attributes }
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end

  describe 'PATCH /update' do
    context 'with valid parameters' do
      let(:area) { create(:area, user:) }

      let(:new_attributes) { attributes_for(:area).merge(name: 'New Name') }

      it 'updates the requested api_v1_area' do
        patch api_v1_area_url(area, api_key: user.api_key), params: { area: new_attributes }
        area.reload

        expect(area.reload.name).to eq('New Name')
      end

      it 'redirects to the api_v1_area' do
        patch api_v1_area_url(area, api_key: user.api_key), params: { area: new_attributes }
        area.reload

        expect(response).to have_http_status(:ok)
      end
    end

    context 'with invalid parameters' do
      let(:area) { create(:area, user:) }
      let(:invalid_attributes) { attributes_for(:area, name: nil) }

      it 'renders a response with 422 status' do
        patch api_v1_area_url(area, api_key: user.api_key), params: { area: invalid_attributes }

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end

  describe 'DELETE /destroy' do
    let!(:area) { create(:area, user:) }

    it 'destroys the requested api_v1_area' do
      expect do
        delete api_v1_area_url(area, api_key: user.api_key)
      end.to change(Area, :count).by(-1)
    end

    it 'redirects to the api_v1_areas list' do
      delete api_v1_area_url(area, api_key: user.api_key)

      expect(response).to have_http_status(:ok)
    end
  end
end

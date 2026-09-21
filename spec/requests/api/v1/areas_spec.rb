# frozen_string_literal: true

require 'rails_helper'

RSpec.describe '/api/v1/areas', type: :request do
  let(:user) { create(:user) }

  describe 'GET /index' do
    it 'renders a successful response' do
      get api_v1_areas_url, headers: { 'Authorization' => "Bearer #{user.api_key}" }
      expect(response).to be_successful
    end

    it 'serves a legacy Area whose stored radius is not positive' do
      area = create(:area, user:)
      area.update_column(:radius, 0)

      get api_v1_areas_url, headers: { 'Authorization' => "Bearer #{user.api_key}" }

      expect(response).to be_successful
      expect(response.parsed_body).to contain_exactly(
        include('id' => area.id, 'radius' => Place.column_defaults['visit_radius'])
      )
    end
  end

  describe 'POST /create' do
    context 'with valid parameters' do
      let(:valid_attributes) do
        attributes_for(:area)
      end

      it 'creates a new Area' do
        expect do
          post api_v1_areas_url, headers: { 'Authorization' => "Bearer #{user.api_key}" },
                                 params: { area: valid_attributes }
        end.to change(Area, :count).by(1)
      end

      it 'creates and returns a canonical Place behind the legacy Area ID' do
        expect do
          post api_v1_areas_url, headers: { 'Authorization' => "Bearer #{user.api_key}" },
                                 params: { area: valid_attributes }
        end.to change(Place, :count).by(1)

        area = Area.last
        place = LegacyAreaPlaceMapping.find_by!(area:).place
        expect(place).to have_attributes(name: area.name, visit_radius: area.radius)
        expect(response.parsed_body).to include('id' => area.id, 'radius' => place.visit_radius)
        expect(response.headers['Deprecation']).to eq('true')
      end

      it 'redirects to the created api_v1_area' do
        post api_v1_areas_url, headers: { 'Authorization' => "Bearer #{user.api_key}" },
                              params: { area: valid_attributes }

        expect(response).to have_http_status(:created)
      end
    end

    context 'with invalid parameters' do
      let(:invalid_attributes) do
        attributes_for(:area, name: nil)
      end

      it 'does not create a new Area' do
        expect do
          post api_v1_areas_url, headers: { 'Authorization' => "Bearer #{user.api_key}" },
                                 params: { area: invalid_attributes }
        end.to change(Area, :count).by(0)
      end

      it 'renders a response with 422 status' do
        post api_v1_areas_url, headers: { 'Authorization' => "Bearer #{user.api_key}" },
                               params: { area: invalid_attributes }

        expect(response).to have_http_status(:unprocessable_content)
      end
    end
  end

  describe 'PATCH /update' do
    context 'with valid parameters' do
      let(:area) { create(:area, user:) }

      let(:new_attributes) { attributes_for(:area).merge(name: 'New Name') }

      it 'updates the requested api_v1_area' do
        patch api_v1_area_url(area), headers: { 'Authorization' => "Bearer #{user.api_key}" },
                                     params: { area: new_attributes }
        area.reload

        expect(area.reload.name).to eq('New Name')
        expect(LegacyAreaPlaceMapping.find_by!(area:).place.name).to eq('New Name')
      end

      it 'redirects to the api_v1_area' do
        patch api_v1_area_url(area), headers: { 'Authorization' => "Bearer #{user.api_key}" },
                                     params: { area: new_attributes }
        area.reload

        expect(response).to have_http_status(:ok)
      end
    end

    context 'with invalid parameters' do
      let(:area) { create(:area, user:) }
      let(:invalid_attributes) { attributes_for(:area, name: nil) }

      it 'renders a response with 422 status' do
        patch api_v1_area_url(area), headers: { 'Authorization' => "Bearer #{user.api_key}" },
                                     params: { area: invalid_attributes }

        expect(response).to have_http_status(:unprocessable_content)
      end
    end
  end

  describe 'DELETE /destroy' do
    let!(:area) { create(:area, user:) }

    it 'destroys the requested api_v1_area' do
      expect do
        delete api_v1_area_url(area), headers: { 'Authorization' => "Bearer #{user.api_key}" }
      end.to change(Area, :count).by(-1)
    end

    it 'preserves Visits when deleting through the compatibility adapter' do
      place = Places::LegacyAreaAdapter.new(user:).resolve(area)
      visit = create(:visit, user:, area:, place:, status: :confirmed)

      delete api_v1_area_url(area), headers: { 'Authorization' => "Bearer #{user.api_key}" }

      expect(visit.reload).to have_attributes(area_id: nil, place_id: nil)
    end

    it 'redirects to the api_v1_areas list' do
      delete api_v1_area_url(area), headers: { 'Authorization' => "Bearer #{user.api_key}" }

      expect(response).to have_http_status(:ok)
    end
  end
end

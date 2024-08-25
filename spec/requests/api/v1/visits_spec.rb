# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Visits', type: :request do
  let(:user) { create(:user) }

  let(:api_key) { user.api_key }
  describe 'PUT /api/v1/visits/:id' do
    let(:visit) { create(:visit, user:) }

    let(:valid_attributes) do
      {
        visit: {
          name: 'New name'
        }
      }
    end

    let(:invalid_attributes) do
      {
        visit: {
          name: nil
        }
      }
    end

    context 'with valid parameters' do
      it 'updates the requested visit' do
        put api_v1_visit_url(visit, api_key:), params: valid_attributes

        expect(visit.reload.name).to eq('New name')
      end

      it 'renders a JSON response with the visit' do
        put api_v1_visit_url(visit, api_key:), params: valid_attributes

        expect(response).to have_http_status(:ok)
      end
    end

    context 'with invalid parameters' do
      it 'renders a JSON response with errors for the visit' do
        put api_v1_visit_url(visit, api_key:), params: invalid_attributes

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end
end

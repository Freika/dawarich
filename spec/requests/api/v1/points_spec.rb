require 'rails_helper'

RSpec.describe "Api::V1::Points", type: :request do
  describe "POST /api/v1/points" do
    context 'with valid params' do
      let(:params) do
        { lat: 1.0, lon: 1.0, tid: 'test', tst: Time.now.to_i, topic: 'iPhone 12 pro' }
      end

      it "returns http success" do
        post api_v1_points_path, params: params

        expect(response).to have_http_status(:success)
      end
    end

    context 'with invalid params' do
      let(:params) do
        { lat: 1.0, lon: 1.0, tid: 'test', tst: Time.now.to_i }
      end

      it "returns http unprocessable_entity" do
        post api_v1_points_path, params: params

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.body).to eq("{\"topic\":[\"can't be blank\"]}")
      end
    end
  end
end
